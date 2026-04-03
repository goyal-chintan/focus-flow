# Sparkle Updater Implementation Plan

> **For Claude:** Use /executing-plans to implement this plan task-by-task.

**Goal:** Add true in-app updates to FocusFlow using Sparkle, with automatic background checks and a manual **Check for Updates...** action in **Settings > About**.
**Architecture:** Introduce a small app-scoped updater integration layer that owns Sparkle lifecycle and exposes a thin UI state to `SettingsView`. Update the app bundle metadata and packaging scripts so Sparkle is embedded correctly in local/release app bundles, then extend release automation to publish a Sparkle feed and signed update artifacts.
**Tech Stack:** Swift 6.2, SwiftUI, Swift Package Manager, Sparkle 2, shell scripts, GitHub Actions

---

### Task 1: Add Sparkle dependency and updater scaffold

**Files:**
- Modify: `Package.swift`
- Modify: `Sources/FocusFlow/FocusFlowApp.swift`
- Create: `Sources/FocusFlow/Services/AppUpdater.swift`
- Test: `Tests/FocusFlowTests/AppUpdaterTests.swift`

**Step 1: Write the failing tests**
```swift
@MainActor
func testVersionStringUsesBundleShortVersion() {
    let updater = AppUpdater(
        bundleInfo: [
            "CFBundleShortVersionString": "1.2.3"
        ],
        updaterControllerFactory: .noop
    )

    XCTAssertEqual(updater.currentVersion, "1.2.3")
}

@MainActor
func testManualCheckBridgesToSparkleController() {
    let probe = SparkleProbe()
    let updater = AppUpdater(
        bundleInfo: [:],
        updaterControllerFactory: { probe.controller }
    )

    updater.checkForUpdates()

    XCTAssertEqual(probe.checkForUpdatesCallCount, 1)
}
```

**Step 2: Run test to verify it fails**
Run: `swift test --filter AppUpdaterTests`
Expected: FAIL with missing `AppUpdater` / Sparkle bridge types

**Step 3: Write minimal implementation**
```swift
import Observation
import Sparkle

@MainActor
@Observable
final class AppUpdater {
    private let controller: SPUStandardUpdaterController
    let currentVersion: String

    init(bundleInfo: [String: Any] = Bundle.main.infoDictionary ?? [:],
         updaterControllerFactory: () -> SPUStandardUpdaterController = {
             SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
         }) {
        self.controller = updaterControllerFactory()
        self.currentVersion = bundleInfo["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
```

**Step 4: Wire the updater into the app**
```swift
@State private var appUpdater = AppUpdater()

Settings {
    CompanionWindowView()
        .environment(timerVM)
        .environment(appUpdater)
}
```

**Step 5: Run targeted tests and build**
Run:
```bash
swift test --filter AppUpdaterTests
swift build
```
Expected: New updater tests pass, build succeeds

**Step 6: Commit**
```bash
git add Package.swift Sources/FocusFlow/FocusFlowApp.swift Sources/FocusFlow/Services/AppUpdater.swift Tests/FocusFlowTests/AppUpdaterTests.swift
git commit -m "feat: scaffold Sparkle updater integration"
```

### Task 2: Add bundle metadata and release defaults for Sparkle

**Files:**
- Modify: `Sources/FocusFlow/Info.plist`
- Modify: `Scripts/build-dmg.sh`
- Modify: `Scripts/run.sh`
- Modify: `Scripts/install-and-register-smart.sh`

**Step 1: Add the failing metadata assertions**
```swift
func testInfoPlistContainsSparkleFeedDefaults() throws {
    let plist = try loadPlist("Sources/FocusFlow/Info.plist")
    XCTAssertEqual(plist["SUEnableAutomaticChecks"] as? Bool, true)
    XCTAssertNotNil(plist["SUFeedURL"])
}
```

**Step 2: Run test to verify it fails**
Run: `swift test --filter AppUpdaterTests/testInfoPlistContainsSparkleFeedDefaults`
Expected: FAIL because Sparkle keys are missing

**Step 3: Add Sparkle keys to app metadata**
```xml
<key>SUFeedURL</key>
<string>https://goyal-chintan.github.io/focus-flow/appcast.xml</string>
<key>SUEnableAutomaticChecks</key>
<true/>
<key>SUPublicEDKey</key>
<string>__SPARKLE_PUBLIC_KEY__</string>
```

**Step 4: Mirror the same metadata into bundle-building scripts**
Add the same Sparkle keys to the inline `Info.plist` blocks in:
- `Scripts/build-dmg.sh`
- `Scripts/run.sh`
- `Scripts/install-and-register-smart.sh`

**Step 5: Verify plist syntax and build**
Run:
```bash
plutil -lint Sources/FocusFlow/Info.plist
swift build
```
Expected: `OK` from `plutil`, build succeeds

**Step 6: Commit**
```bash
git add Sources/FocusFlow/Info.plist Scripts/build-dmg.sh Scripts/run.sh Scripts/install-and-register-smart.sh
git commit -m "feat: add Sparkle bundle metadata"
```

### Task 3: Expose updater state in Settings > About

**Files:**
- Modify: `Sources/FocusFlow/Views/Companion/SettingsView.swift`
- Test: `Tests/FocusFlowTests/ReviewContractsTests.swift`
- Test: `Tests/FocusFlowTests/ReviewQualityGateTests.swift`

**Step 1: Add the failing UI contract tests**
```swift
func testSettingsAboutIncludesCheckForUpdatesAction() throws {
    let source = try String(contentsOfFile: settingsViewPath)
    XCTAssertTrue(source.contains("Check for Updates"))
    XCTAssertTrue(source.contains("Current Version"))
}
```

**Step 2: Run test to verify it fails**
Run: `swift test --filter ReviewContractsTests/testSettingsAboutIncludesCheckForUpdatesAction`
Expected: FAIL because About still hardcodes `v1.0`

**Step 3: Implement the About updater UI**
```swift
@Environment(AppUpdater.self) private var appUpdater

VStack(spacing: 10) {
    Text("Current Version")
    Text(appUpdater.currentVersion)

    Button("Check for Updates...") {
        appUpdater.checkForUpdates()
    }
    .buttonStyle(.glass)
    .buttonBorderShape(.capsule)
    .accessibilityLabel("Check for updates")
}
```

**Step 4: Preserve FocusFlow design-system constraints**
- Keep the updater controls inside the existing `LiquidGlassPanel`
- Use app design-system buttons, not a native `Form`
- Keep the panel content readable in dark mode
- Do not add a new popover action

**Step 5: Run targeted tests and build**
Run:
```bash
swift test --filter ReviewContractsTests
swift test --filter ReviewQualityGateTests
swift build
```
Expected: Updated UI contract tests pass, build succeeds

**Step 6: Commit**
```bash
git add Sources/FocusFlow/Views/Companion/SettingsView.swift Tests/FocusFlowTests/ReviewContractsTests.swift Tests/FocusFlowTests/ReviewQualityGateTests.swift
git commit -m "feat: add updater controls to settings about"
```

### Task 4: Package Sparkle correctly in local and release app bundles

**Files:**
- Modify: `Scripts/build-dmg.sh`
- Modify: `Scripts/run.sh`
- Modify: `Scripts/install-and-register-smart.sh`
- Modify: `Package.swift`

**Step 1: Add a failing packaging assertion**
```swift
func testBuildDMGScriptCopiesSparkleFrameworks() throws {
    let source = try String(contentsOfFile: buildDMGPath)
    XCTAssertTrue(source.contains("Frameworks"))
    XCTAssertTrue(source.contains("Sparkle.framework"))
}
```

**Step 2: Run test to verify it fails**
Run: `swift test --filter AppUpdaterTests/testBuildDMGScriptCopiesSparkleFrameworks`
Expected: FAIL because scripts only package the app binary/resources today

**Step 3: Update bundle assembly scripts**
```sh
FRAMEWORKS="$CONTENTS/Frameworks"
mkdir -p "$FRAMEWORKS"
cp -R "$BUILD_DIR"/Frameworks/Sparkle.framework "$FRAMEWORKS/"
```

**Step 4: Verify local app assembly still works**
Run:
```bash
bash Scripts/run.sh
```
Expected: App bundle launches with embedded Sparkle framework

**Step 5: Verify release bundle assembly**
Run:
```bash
VERSION=1.0.0-test Scripts/build-dmg.sh
```
Expected: DMG is created and contains a Sparkle-capable app bundle

**Step 6: Commit**
```bash
git add Scripts/build-dmg.sh Scripts/run.sh Scripts/install-and-register-smart.sh Package.swift
git commit -m "feat: package Sparkle in app bundles"
```

### Task 5: Add appcast generation and release automation

**Files:**
- Modify: `.github/workflows/release.yml`
- Create: `Scripts/generate-appcast.sh`
- Modify: `README.md`

**Step 1: Add a failing release-tooling test**
```swift
func testReleaseWorkflowPublishesAppcast() throws {
    let workflow = try String(contentsOfFile: releaseWorkflowPath)
    XCTAssertTrue(workflow.contains("appcast"))
}
```

**Step 2: Run test to verify it fails**
Run: `swift test --filter AppUpdaterTests/testReleaseWorkflowPublishesAppcast`
Expected: FAIL because the current workflow uploads only a DMG

**Step 3: Add appcast generation script**
```sh
#!/bin/sh
set -eu

SPARKLE_BIN="${SPARKLE_BIN:?}"
"$SPARKLE_BIN/generate_appcast" Artifacts --download-url-prefix "https://github.com/goyal-chintan/focus-flow/releases/download/${TAG}/"
```

**Step 4: Extend the release workflow**
- Build the DMG
- Generate/sign the Sparkle appcast
- Upload `appcast.xml` alongside the DMG
- Document required secrets/environment for the private signing key and public key

**Step 5: Update README install/update docs**
- Explain that FocusFlow now supports in-app updates
- Keep Homebrew / DMG install instructions factual
- Note any signing/notarization limitation if still applicable

**Step 6: Verify release tooling shape**
Run:
```bash
rg -n "appcast|generate_appcast|SUPublicEDKey|SUFeedURL" .github/workflows/release.yml Scripts README.md Sources/FocusFlow/Info.plist
```
Expected: all Sparkle release requirements are referenced in code/docs

**Step 7: Commit**
```bash
git add .github/workflows/release.yml Scripts/generate-appcast.sh README.md
git commit -m "feat: automate Sparkle release feed publishing"
```

### Task 6: Record decisions, capture evidence, and push the branch

**Files:**
- Modify: `docs/project-memory/decisions/DECISIONS.md`
- Test: `Tests/FocusFlowTests/UIEvidenceCaptureTests.swift`
- Optional evidence outputs: `docs/screenshots/review/latest/...`

**Step 1: Add/update decision log entry**
Record:
- why Sparkle was chosen over a custom updater
- why updater controls live in Settings > About instead of the popover
- any release-signing assumptions that now become required

**Step 2: Add/update UI evidence coverage**
Add a capture or contract check covering the Settings > About updater surface so the new button/version block is reviewable.

**Step 3: Run final verification**
Run:
```bash
swift build
swift test
```
Expected:
- `swift build` passes
- `swift test` should only show the pre-existing `TimerCompletionFlowTests.testIdleEscalationFiringOutsideWorkHoursWhenNotificationWasIgnored` failure unless that baseline issue is separately fixed

**Step 4: Commit**
```bash
git add docs/project-memory/decisions/DECISIONS.md Tests/FocusFlowTests/UIEvidenceCaptureTests.swift docs/screenshots/review/latest
git commit -m "docs: record Sparkle updater decisions and evidence"
```

**Step 5: Push**
```bash
git push -u origin feature/sparkle-updater
```
