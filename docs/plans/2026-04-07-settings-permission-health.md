# Settings Permission Health Implementation Plan

> **For Claude:** Use /executing-plans to implement this plan task-by-task.

**Goal:** Add a final Settings section that shows the live health of FocusFlow’s core permissions and gives users a direct recovery action for each one.
**Architecture:** Keep existing integration controls where they are, but add a dedicated permission-health builder plus a shared Settings row component so one section can render Notifications, Calendar, Reminders, Browser Automation, and Screen Recording truthfully. Use TDD and source-contract tests first, then minimal production code, then review evidence.
**Tech Stack:** SwiftUI, EventKit, UserNotifications, CoreGraphics, Core Services Apple Events, XCTest

---

### Task 1: Add failing contract tests for the new Settings health section

**Files:**
- Modify: `Tests/FocusFlowTests/ReviewContractsTests.swift`

**Step 1: Write the failing test**
Add source-contract assertions that require:
- a `Permission & Integration Health` section in `SettingsView`
- all five labels: `Notifications`, `Calendar`, `Reminders`, `Browser Automation`, `Screen Recording`
- accessibility identifiers for every row CTA

**Step 2: Run test to verify it fails**
Run: `swift test --filter ReviewContractsTests`
Expected: FAIL because the section and CTA identifiers do not exist yet.

**Step 3: Write the minimal implementation later**
Do not touch production code in this task.

**Step 4: Commit**
```bash
git add Tests/FocusFlowTests/ReviewContractsTests.swift
git commit -m "test: require settings permission health section"
```

### Task 2: Add failing unit tests for permission-health state mapping

**Files:**
- Create: `Tests/FocusFlowTests/PermissionHealthServiceTests.swift`
- Modify: `Sources/FocusFlow/Services/BrowserDomainResolver.swift`

**Step 1: Write the failing test**
Add tests for a new builder/service that maps:
- notifications auth states
- calendar auth states
- reminders auth states
- screen recording access
- browser automation aggregate status for installed/blocked/ready/no-browser cases

**Step 2: Run test to verify it fails**
Run: `swift test --filter PermissionHealthServiceTests`
Expected: FAIL because the service and browser target metadata do not exist yet.

**Step 3: Write the minimal implementation later**
Do not add production code in this task.

**Step 4: Commit**
```bash
git add Tests/FocusFlowTests/PermissionHealthServiceTests.swift \
        Sources/FocusFlow/Services/BrowserDomainResolver.swift
git commit -m "test: cover permission health state mapping"
```

### Task 3: Build the permission-health service

**Files:**
- Create: `Sources/FocusFlow/Services/PermissionHealthService.swift`
- Modify: `Sources/FocusFlow/Services/BrowserDomainResolver.swift`

**Step 1: Write the minimal implementation**
Create:
- row/status/action model types
- mapping helpers for notifications, calendar, reminders, automation, and screen recording
- supported browser target metadata exposed from `BrowserDomainResolver`
- automation probing via Apple Events permission checks without prompting

**Step 2: Run the focused unit tests**
Run: `swift test --filter PermissionHealthServiceTests`
Expected: PASS

**Step 3: Refactor**
Keep browser metadata DRY between resolver and permission-health service.

**Step 4: Commit**
```bash
git add Sources/FocusFlow/Services/PermissionHealthService.swift \
        Sources/FocusFlow/Services/BrowserDomainResolver.swift \
        Tests/FocusFlowTests/PermissionHealthServiceTests.swift
git commit -m "feat: add permission health service"
```

### Task 4: Render the new Settings health section

**Files:**
- Modify: `Sources/FocusFlow/Views/Companion/SettingsView.swift`
- Modify: `Sources/FocusFlow/Review/AccessibilityContract.swift`

**Step 1: Add the section**
Render `permissionHealthSection` as the final Settings section after `aboutSection`.

**Step 2: Add the shared row UI**
Render each row with:
- icon
- title
- status badge
- reason text
- optional browser detail lines
- 44pt primary action button

**Step 3: Wire actions**
Use permission-specific actions:
- request Notifications
- request Calendar
- request Reminders
- open Automation settings
- open Screen Recording settings
- scroll to integration controls for already-ready Calendar/Reminders rows

**Step 4: Register accessibility contract entries**
Add any new CTA identifiers/labels to `AccessibilityContract`.

**Step 5: Run contract tests**
Run: `swift test --filter ReviewContractsTests`
Expected: PASS

**Step 6: Commit**
```bash
git add Sources/FocusFlow/Views/Companion/SettingsView.swift \
        Sources/FocusFlow/Review/AccessibilityContract.swift \
        Tests/FocusFlowTests/ReviewContractsTests.swift
git commit -m "feat: add settings permission health panel"
```

### Task 5: Refresh Settings behavior after permission changes

**Files:**
- Modify: `Sources/FocusFlow/Views/Companion/SettingsView.swift`
- Modify: `Sources/FocusFlow/Services/NotificationService.swift` (only if needed)

**Step 1: Ensure live refresh**
Refresh the new health section:
- on Settings appear
- after Notifications/Calendar/Reminders request flows complete
- after the app returns from System Settings

**Step 2: Keep focus restoration behavior**
Maintain the existing companion-window restoration after request flows.

**Step 3: Run targeted tests**
Run:
- `swift test --filter SettingsViewTests`
- `swift test --filter ReviewContractsTests`
Expected: PASS

**Step 4: Commit**
```bash
git add Sources/FocusFlow/Views/Companion/SettingsView.swift \
        Sources/FocusFlow/Services/NotificationService.swift \
        Tests/FocusFlowTests/SettingsViewTests.swift \
        Tests/FocusFlowTests/ReviewContractsTests.swift
git commit -m "fix: refresh settings permission health states"
```

### Task 6: Run Apple-grade validation

**Files:**
- Modify if required by evidence failures:
  - `Tests/FocusFlowTests/UIEvidenceCaptureTests.swift`
  - `Tests/FocusFlowTests/ReviewQualityGateTests.swift`
  - `Sources/FocusFlow/Review/AccessibilityContract.swift`

**Step 1: Run targeted evidence**
Run:
```bash
FOCUSFLOW_REVIEW_FLOW_FILTER=settings_domain_tracking FOCUSFLOW_REVIEW_APPEARANCE_FILTER=light,dark swift test --filter UIEvidenceCaptureTests/testCaptureReviewArtifactsForAllRequiredFlows
```
Expected: PASS with updated Settings evidence.

**Step 2: Run review gate**
Run:
```bash
swift test --filter ReviewQualityGateTests
```
Expected: PASS

**Step 3: Commit**
```bash
git add Tests/FocusFlowTests/UIEvidenceCaptureTests.swift \
        Tests/FocusFlowTests/ReviewQualityGateTests.swift \
        Sources/FocusFlow/Review/AccessibilityContract.swift
git commit -m "test: validate settings permission health evidence"
```

### Task 7: Run full verification and update the installed app

**Files:**
- No new files unless verification requires follow-up

**Step 1: Run full repo verification**
Run:
```bash
swift build
swift test
bash Scripts/run.sh
```
Expected: PASS and bundled app launches.

**Step 2: Update the installed app**
Run:
```bash
cp -R .build/debug/FocusFlow.app ~/Applications/FocusFlow.app
```
Expected: the installed app contains the new Settings health section.

**Step 3: Commit**
```bash
git add .
git commit -m "feat: add settings permission health dashboard"
```
