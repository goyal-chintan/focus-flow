# System-Wide Blocking Implementation Plan

> **For Claude:** Use /executing-plans to implement this plan task-by-task.

**Goal:** Add website, app, and notification blocking during focus sessions with global + per-project profiles.
**Architecture:** BlockingService singleton coordinates three engines: `/etc/hosts` for websites, AppleScript + NSWorkspace for apps, AppleScript for notification muting. BlockProfile SwiftData model stores per-profile configuration. Privileged helper script handles `/etc/hosts` writes.
**Tech Stack:** SwiftUI, SwiftData, Foundation.Process, NSAppleScript, NSWorkspace

---

### Task 1: BlockProfile Data Model

**Files:**
- Create: `Sources/FocusFlow/Models/BlockProfile.swift`
- Modify: `Sources/FocusFlow/Models/Project.swift`
- Modify: `Sources/FocusFlow/FocusFlowApp.swift`

**Step 1: Create BlockProfile model**
```swift
// Sources/FocusFlow/Models/BlockProfile.swift
import Foundation
import SwiftData

@Model
final class BlockProfile {
    var id: UUID
    var name: String
    var blockedWebsitesRaw: String  // comma-separated domains
    var blockedAppsRaw: String      // comma-separated bundle IDs
    var mutedNotifAppsRaw: String   // comma-separated bundle IDs
    var isDefault: Bool
    var createdAt: Date

    init(name: String, websites: [String] = [], apps: [String] = [], mutedApps: [String] = [], isDefault: Bool = false) {
        self.id = UUID()
        self.name = name
        self.blockedWebsitesRaw = websites.joined(separator: ",")
        self.blockedAppsRaw = apps.joined(separator: ",")
        self.mutedNotifAppsRaw = mutedApps.joined(separator: ",")
        self.isDefault = isDefault
        self.createdAt = Date()
    }

    var blockedWebsites: [String] {
        get { blockedWebsitesRaw.split(separator: ",").map(String.init).filter { !$0.isEmpty } }
        set { blockedWebsitesRaw = newValue.joined(separator: ",") }
    }

    var blockedApps: [String] {
        get { blockedAppsRaw.split(separator: ",").map(String.init).filter { !$0.isEmpty } }
        set { blockedAppsRaw = newValue.joined(separator: ",") }
    }

    var mutedNotificationApps: [String] {
        get { mutedNotifAppsRaw.split(separator: ",").map(String.init).filter { !$0.isEmpty } }
        set { mutedNotifAppsRaw = newValue.joined(separator: ",") }
    }
}
```

**Step 2: Add blockProfile to Project**
Add to `Project.swift`:
```swift
var blockProfile: BlockProfile?
```

**Step 3: Add BlockProfile to ModelContainer schema in FocusFlowApp.swift**
Update the schema array to include `BlockProfile.self`.

**Step 4: Build**
```bash
swift build
```

**Step 5: Commit**
```bash
git add Sources/FocusFlow/Models/BlockProfile.swift Sources/FocusFlow/Models/Project.swift Sources/FocusFlow/FocusFlowApp.swift
git commit -m "feat: add BlockProfile SwiftData model and Project relationship"
```

---

### Task 2: Blocking Helper Script

**Files:**
- Create: `Sources/FocusFlow/Services/BlockingHelper.swift`

**Step 1: Create the helper that manages /etc/hosts**
```swift
// Sources/FocusFlow/Services/BlockingHelper.swift
import Foundation

struct BlockingHelper {
    private static let startMarker = "# FocusFlow-Block-Start"
    private static let endMarker = "# FocusFlow-Block-End"
    private static let hostsPath = "/etc/hosts"

    /// Block domains by adding them to /etc/hosts (requires admin via osascript)
    static func blockWebsites(_ domains: [String]) {
        guard !domains.isEmpty else { return }

        var entries = [startMarker]
        for domain in domains {
            let clean = domain.trimmingCharacters(in: .whitespaces).lowercased()
            entries.append("127.0.0.1 \(clean)")
            if !clean.hasPrefix("www.") {
                entries.append("127.0.0.1 www.\(clean)")
            }
        }
        entries.append(endMarker)

        let block = entries.joined(separator: "\n")
        let script = """
        do shell script "echo '\(block)' >> \(hostsPath) && killall -HUP mDNSResponder 2>/dev/null || true" with administrator privileges
        """
        runAppleScript(script)
    }

    /// Unblock by removing FocusFlow entries from /etc/hosts
    static func unblockWebsites() {
        let script = """
        do shell script "sed -i '' '/\(startMarker)/,/\(endMarker)/d' \(hostsPath) && killall -HUP mDNSResponder 2>/dev/null || true" with administrator privileges
        """
        runAppleScript(script)
    }

    /// Check if blocking entries exist (for crash recovery)
    static func isBlockingActive() -> Bool {
        guard let contents = try? String(contentsOfFile: hostsPath, encoding: .utf8) else { return false }
        return contents.contains(startMarker)
    }

    private static func runAppleScript(_ source: String) {
        let script = NSAppleScript(source: source)
        var error: NSDictionary?
        script?.executeAndReturnError(&error)
        if let error {
            print("AppleScript error: \(error)")
        }
    }
}
```

**Step 2: Build**
```bash
swift build
```

**Step 3: Commit**
```bash
git add Sources/FocusFlow/Services/BlockingHelper.swift
git commit -m "feat: add BlockingHelper for /etc/hosts website blocking"
```

---

### Task 3: App Blocking via AppleScript + NSWorkspace

**Files:**
- Create: `Sources/FocusFlow/Services/AppBlocker.swift`

**Step 1: Create the app blocker**
```swift
// Sources/FocusFlow/Services/AppBlocker.swift
import Foundation
import AppKit

@MainActor
final class AppBlocker {
    private var blockedBundleIDs: Set<String> = []
    private var monitorTimer: Timer?
    private var workspaceObserver: Any?

    func activate(bundleIDs: [String]) {
        guard !bundleIDs.isEmpty else { return }
        blockedBundleIDs = Set(bundleIDs)

        // Quit currently running blocked apps
        terminateBlockedApps()

        // Start polling to prevent relaunching
        monitorTimer?.invalidate()
        let t = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.terminateBlockedApps()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        monitorTimer = t
    }

    func deactivate() {
        monitorTimer?.invalidate()
        monitorTimer = nil
        blockedBundleIDs.removeAll()
    }

    var isActive: Bool { !blockedBundleIDs.isEmpty }

    private func terminateBlockedApps() {
        let running = NSWorkspace.shared.runningApplications
        for app in running {
            guard let bundleID = app.bundleIdentifier else { continue }
            if blockedBundleIDs.contains(bundleID) {
                app.terminate()
            }
        }
    }

    /// Get list of user-facing installed applications for the picker UI
    static func installedApps() -> [(name: String, bundleID: String)] {
        let workspace = NSWorkspace.shared
        let appURLs = FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask)
            + FileManager.default.urls(for: .applicationDirectory, in: .systemDomainMask)

        var apps: [(name: String, bundleID: String)] = []
        let skipPrefixes = ["com.apple."] // Skip most Apple system apps

        for dir in appURLs {
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil
            ) else { continue }

            for url in contents where url.pathExtension == "app" {
                guard let bundle = Bundle(url: url),
                      let bundleID = bundle.bundleIdentifier,
                      let name = bundle.infoDictionary?["CFBundleName"] as? String
                        ?? bundle.infoDictionary?["CFBundleDisplayName"] as? String
                else { continue }

                // Skip system apps but keep common ones users might want to block
                let allowedApple = ["com.apple.Safari", "com.apple.mail", "com.apple.MobileSMS"]
                if bundleID.hasPrefix("com.apple.") && !allowedApple.contains(bundleID) { continue }

                apps.append((name: name, bundleID: bundleID))
            }
        }

        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
```

**Step 2: Build**
```bash
swift build
```

**Step 3: Commit**
```bash
git add Sources/FocusFlow/Services/AppBlocker.swift
git commit -m "feat: add AppBlocker — quit and prevent relaunch of blocked apps"
```

---

### Task 4: BlockingService (Central Coordinator)

**Files:**
- Create: `Sources/FocusFlow/Services/BlockingService.swift`

**Step 1: Create the coordinator**
```swift
// Sources/FocusFlow/Services/BlockingService.swift
import Foundation

@MainActor
final class BlockingService {
    static let shared = BlockingService()
    private init() {}

    let appBlocker = AppBlocker()
    private(set) var isActive = false
    private var activeProfile: BlockProfile?

    func activate(profile: BlockProfile) {
        guard !isActive else { return }
        activeProfile = profile
        isActive = true

        // Website blocking
        let websites = profile.blockedWebsites
        if !websites.isEmpty {
            BlockingHelper.blockWebsites(websites)
        }

        // App blocking
        let apps = profile.blockedApps
        if !apps.isEmpty {
            appBlocker.activate(bundleIDs: apps)
        }

        // Notification muting (via AppleScript)
        let mutedApps = profile.mutedNotificationApps
        for bundleID in mutedApps {
            muteNotifications(for: bundleID)
        }
    }

    func deactivate() {
        guard isActive else { return }

        // Unblock websites
        BlockingHelper.unblockWebsites()

        // Stop app blocking
        appBlocker.deactivate()

        // Unmute notifications
        if let profile = activeProfile {
            for bundleID in profile.mutedNotificationApps {
                unmuteNotifications(for: bundleID)
            }
        }

        activeProfile = nil
        isActive = false
    }

    /// Crash recovery — clean up stale blocking on app launch
    func cleanupIfNeeded() {
        if BlockingHelper.isBlockingActive() {
            BlockingHelper.unblockWebsites()
        }
    }

    /// Resolve the effective profile: project-specific or default
    func resolveProfile(for project: Project?, modelContext: Any?) -> BlockProfile? {
        // Use project's profile if set
        if let profile = project?.blockProfile {
            return profile
        }
        // Fall back to default profile
        // Caller should query for BlockProfile where isDefault == true
        return nil
    }

    // MARK: - Notification Muting

    private func muteNotifications(for bundleID: String) {
        // Use defaults write to disable notifications for specific app
        let script = """
        do shell script "defaults write \(bundleID) NSUserNotificationAlertStyle -string none"
        """
        let appleScript = NSAppleScript(source: script)
        var error: NSDictionary?
        appleScript?.executeAndReturnError(&error)
    }

    private func unmuteNotifications(for bundleID: String) {
        let script = """
        do shell script "defaults delete \(bundleID) NSUserNotificationAlertStyle"
        """
        let appleScript = NSAppleScript(source: script)
        var error: NSDictionary?
        appleScript?.executeAndReturnError(&error)
    }
}
```

**Step 2: Build**
```bash
swift build
```

**Step 3: Commit**
```bash
git add Sources/FocusFlow/Services/BlockingService.swift
git commit -m "feat: add BlockingService — central coordinator for all blocking engines"
```

---

### Task 5: Wire Blocking into TimerViewModel

**Files:**
- Modify: `Sources/FocusFlow/ViewModels/TimerViewModel.swift`

**Step 1: Add blocking activation/deactivation**

In `startFocus()`, after creating the session and starting the timer, resolve and activate blocking:
```swift
// After startTimer() call in startFocus():
activateBlocking()
```

Add methods:
```swift
// MARK: - Blocking
var isBlockingActive: Bool { BlockingService.shared.isActive }

private func activateBlocking() {
    // Try project-specific profile first
    if let profile = selectedProject?.blockProfile {
        BlockingService.shared.activate(profile: profile)
        return
    }
    // Fall back to default profile
    let predicate = #Predicate<BlockProfile> { $0.isDefault == true }
    let descriptor = FetchDescriptor<BlockProfile>(predicate: predicate)
    if let defaultProfile = try? modelContext?.fetch(descriptor).first {
        BlockingService.shared.activate(profile: defaultProfile)
    }
}

private func deactivateBlocking() {
    BlockingService.shared.deactivate()
}
```

In `stop()`, `abandonSession()`, and `continueAfterCompletion(.endSession)`, call `deactivateBlocking()`.

In `startBreak()` — do NOT deactivate (blocking stays during breaks).

In `continueAfterCompletion(.takeBreak)` — do NOT deactivate.

In `configure()`, add crash recovery:
```swift
BlockingService.shared.cleanupIfNeeded()
```

**Step 2: Build**
```bash
swift build
```

**Step 3: Commit**
```bash
git commit -am "feat: wire blocking activation into timer lifecycle"
```

---

### Task 6: Seed Default Profiles

**Files:**
- Modify: `Sources/FocusFlow/ViewModels/TimerViewModel.swift`

**Step 1: Add profile seeding in configure()**

After `loadSettings()`, add:
```swift
seedDefaultProfiles()
```

```swift
private func seedDefaultProfiles() {
    let descriptor = FetchDescriptor<BlockProfile>()
    let existing = (try? modelContext?.fetch(descriptor)) ?? []
    guard existing.isEmpty else { return }

    let social = BlockProfile(
        name: "Social Media",
        websites: ["youtube.com", "x.com", "twitter.com", "reddit.com", "instagram.com", "facebook.com", "tiktok.com"],
        isDefault: true
    )

    let fullFocus = BlockProfile(
        name: "Full Focus",
        websites: ["youtube.com", "x.com", "twitter.com", "reddit.com", "instagram.com", "facebook.com", "tiktok.com", "news.ycombinator.com", "netflix.com", "twitch.tv"],
        apps: ["com.tinyspeck.slackmacgap", "com.hnc.Discord", "ph.telegra.Telegraph", "net.whatsapp.WhatsApp"],
        mutedApps: ["com.tinyspeck.slackmacgap", "com.hnc.Discord"]
    )

    modelContext?.insert(social)
    modelContext?.insert(fullFocus)
    try? modelContext?.save()
}
```

**Step 2: Build and commit**
```bash
swift build
git commit -am "feat: seed Social Media and Full Focus default block profiles"
```

---

### Task 7: Blocking Settings UI

**Files:**
- Create: `Sources/FocusFlow/Views/Companion/BlockingSettingsView.swift`
- Create: `Sources/FocusFlow/Views/Companion/BlockProfileFormView.swift`
- Modify: `Sources/FocusFlow/Views/Companion/CompanionWindowView.swift`

**Step 1: Create BlockingSettingsView** — list of profiles with add/edit/delete, default selection.

**Step 2: Create BlockProfileFormView** — form to edit a profile: name, website list (add/remove), app picker (from installed apps), notification app picker.

**Step 3: Add "Blocking" tab to CompanionWindowView** — new case in CompanionTab enum.

**Step 4: Build and commit**
```bash
swift build
git commit -am "feat: blocking settings UI — profile list and form"
```

---

### Task 8: Project Form Block Profile Picker

**Files:**
- Modify: `Sources/FocusFlow/Views/Companion/ProjectFormView.swift`

**Step 1: Add block profile picker to project form**

Add a section with a Picker that lists available BlockProfiles + "None" option. Uses `@Query` to fetch profiles.

**Step 2: Build and commit**
```bash
swift build
git commit -am "feat: add block profile picker to project form"
```

---

### Task 9: Blocking Status Indicator in Popover

**Files:**
- Modify: `Sources/FocusFlow/Views/MenuBar/MenuBarPopoverView.swift`

**Step 1: Add shield icon when blocking is active**

In the footer area, add:
```swift
if timerVM.isBlockingActive {
    HStack(spacing: 4) {
        Image(systemName: "shield.checkered")
            .font(.caption)
            .foregroundStyle(.green)
        Text("Blocking active")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
```

**Step 2: Build and commit**
```bash
swift build
git commit -am "feat: show blocking status indicator in popover"
```

---

### Task 10: Integration Testing & Cleanup

**Step 1: Build full app**
```bash
swift build
```

**Step 2: Launch and test end-to-end**
```bash
bash Scripts/run.sh
```

Manual test checklist:
- [ ] Blocking tab visible in companion window
- [ ] Two default profiles seeded (Social Media, Full Focus)
- [ ] Can create/edit/delete profiles
- [ ] Can add websites and apps to profiles
- [ ] Can set a profile as default
- [ ] Can assign profiles to projects
- [ ] Starting a focus session activates blocking (admin prompt for websites)
- [ ] youtube.com unreachable in browser during focus
- [ ] Blocked app quits if launched during focus
- [ ] Stopping session removes /etc/hosts entries
- [ ] Abandoning session removes blocking
- [ ] App crash recovery cleans up /etc/hosts on next launch
- [ ] Blocking stays active during breaks

**Step 3: Final commit**
```bash
git commit -am "feat: system-wide blocking v1 — websites, apps, notifications"
```
