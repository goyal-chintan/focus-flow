import AppKit
import Foundation
import SwiftData

/// Tracks app foreground time, records per-app usage, and sends nudge notifications.
@MainActor
final class AppUsageTracker {
    static let shared = AppUsageTracker()

    private var trackingTimer: Timer?
    private var idleSeconds: Int = 0
    private var isTracking = false
    private var nudgeCount: Int = 0
    private weak var timerVM: TimerViewModel?
    private var modelContext: ModelContext?
    private var tickCount: Int = 0

    // Coach signal tracking
    private var appSwitchTimestamps: [Date] = []
    private var lastFrontmostBundleId: String = ""
    private var inactivitySeconds: Int = 0
    private var hasEngagedProductively: Bool = false
    private var startDelaySeconds: Double = 0
    private var lastFrontmostCategory: AppUsageEntry.AppCategory = .neutral

    // MARK: - SuspiciousContextObservation callback
    /// Called whenever a new app comes to the foreground. Subscriber (coach engine) can route
    /// the observation into drift classification / guardian logic.
    var onSuspiciousObservation: ((SuspiciousContextObservation) -> Void)?

    // MARK: - Public context accessors (used by FocusCoachContext builder)

    /// The localized name of the current foreground app (nil when FocusFlow is front, or unknown).
    var currentFrontmostAppName: String? {
        guard !lastFrontmostBundleId.isEmpty,
              lastFrontmostBundleId != Bundle.main.bundleIdentifier else { return nil }
        return NSRunningApplication
            .runningApplications(withBundleIdentifier: lastFrontmostBundleId)
            .first?.localizedName
    }

    var currentFrontmostBundleId: String? {
        guard !lastFrontmostBundleId.isEmpty,
              lastFrontmostBundleId != Bundle.main.bundleIdentifier else { return nil }
        return lastFrontmostBundleId
    }

    /// The `AppUsageEntry.AppCategory` of the current foreground app (for TimerViewModel usage).
    var currentFrontmostCategory: AppUsageEntry.AppCategory { lastFrontmostCategory }

    /// The AppUsageCategory of the current foreground app (for FocusCoachContext usage).
    var currentFrontmostAppUsageCategory: AppUsageCategory {
        switch lastFrontmostCategory {
        case .productive:   return .productive
        case .neutral:      return .neutral
        case .distracting:  return .distracting
        }
    }

    private init() {}

        // MARK: - Lifecycle

    func start(timerVM: TimerViewModel, modelContext: ModelContext) {
        guard !isTracking else { return }
        trackingTimer?.invalidate()
        self.timerVM = timerVM
        self.modelContext = modelContext
        isTracking = true
        idleSeconds = 0
        nudgeCount = 0
        tickCount = 0
        appSwitchTimestamps = []
        lastFrontmostBundleId = ""
        inactivitySeconds = 0
        hasEngagedProductively = false
        startDelaySeconds = 0
        lastFrontmostCategory = .neutral

        trackingTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        if let timer = trackingTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
        log("Started tracking")
    }

    func stop() {
        trackingTimer?.invalidate()
        trackingTimer = nil
        isTracking = false
        idleSeconds = 0
        nudgeCount = 0
        log("Stopped tracking")
    }

    // MARK: - Tick

    private func tick() {
        guard let vm = timerVM else { return }

        tickCount += 1
        let isFocusing = vm.state == .focusing
        trackFrontmostApp(isFocusing: isFocusing)

        // Feed coach signals every 30 seconds during focus
        if isFocusing, vm.settings?.coachRealtimeEnabled == true, tickCount % 30 == 0 {
            feedCoachSignals(vm: vm)
        }

        // Only count idle time when not in a session
        let isIdle = vm.state == .idle && !vm.isOvertime
        if isIdle {
            idleSeconds += 1

            let threshold = vm.settings?.antiProcrastinationThresholdMinutes ?? 5
            let enabled = vm.settings?.antiProcrastinationEnabled ?? true

            if enabled {
                let nextNudgeSeconds = nudgeInterval(for: nudgeCount, baseMinutes: threshold)
                if idleSeconds >= nextNudgeSeconds {
                    vm.evaluateIdleStarterIntervention(
                        idleSeconds: idleSeconds,
                        escalationLevel: nudgeCount,
                        frontmostCategory: lastFrontmostCategory
                    )
                    let presentedInAppPrompt = vm.showCoachInterventionWindow
                        || vm.activeCoachInterventionDecision != nil
                        || vm.currentIdleStarterDecision != nil
                    // Notifications are intentionally de-prioritized for anti-procrastination
                    // because users quickly habituate to them. The in-app guardian is primary.
                    _ = presentedInAppPrompt
                    nudgeCount += 1
                }
            }
        } else {
            if idleSeconds > 0 {
                idleSeconds = 0
                nudgeCount = 0
                vm.currentIdleStarterDecision = nil
            }
        }
    }

    /// Returns the idle seconds threshold for the Nth nudge.
    /// First nudge at base threshold, then escalating: base, base+5min, base+15min, then every 15min.
    private func nudgeInterval(for count: Int, baseMinutes: Int) -> Int {
        switch count {
        case 0: return baseMinutes * 60
        case 1: return (baseMinutes + 5) * 60
        case 2: return (baseMinutes + 15) * 60
        default: return (baseMinutes + 15 + (count - 2) * 15) * 60
        }
    }

    // MARK: - App Tracking

    private func trackFrontmostApp(isFocusing: Bool) {
        guard let ctx = modelContext else { return }

        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return }
        let bundleId = frontApp.bundleIdentifier ?? "unknown"
        let appName = frontApp.localizedName ?? "Unknown"
        lastFrontmostCategory = AppUsageEntry.classify(bundleIdentifier: bundleId, appName: appName)

        // Skip FocusFlow itself
        if bundleId == Bundle.main.bundleIdentifier { return }

        // Track app switches for coach signals
        if bundleId != lastFrontmostBundleId {
            if !lastFrontmostBundleId.isEmpty {
                appSwitchTimestamps.append(Date())
                // Keep only last 2 minutes of timestamps
                let cutoff = Date().addingTimeInterval(-120)
                appSwitchTimestamps.removeAll { $0 < cutoff }
            }
            lastFrontmostBundleId = bundleId
            inactivitySeconds = 0

            // Emit SuspiciousContextObservation for coach / guardian layer
            let obs = buildObservation(
                bundleId: bundleId,
                appName: appName,
                isInSession: isFocusing,
                selectedProjectId: timerVM?.selectedProject?.id,
                selectedWorkMode: timerVM?.selectedProject?.workMode
            )
            onSuspiciousObservation?(obs)
        } else {
            inactivitySeconds += 1
        }

        let today = Calendar.current.startOfDay(for: Date())

        // Find or create entry for this app + today
        let descriptor = FetchDescriptor<AppUsageEntry>(
            predicate: #Predicate { entry in
                entry.date == today && entry.bundleIdentifier == bundleId
            }
        )

        do {
            let existing = try ctx.fetch(descriptor)
            if let entry = existing.first {
                if isFocusing {
                    entry.duringFocusSeconds += 1
                } else {
                    entry.outsideFocusSeconds += 1
                }
            } else {
                let entry = AppUsageEntry(
                    date: today,
                    appName: appName,
                    bundleIdentifier: bundleId,
                    duringFocusSeconds: isFocusing ? 1 : 0,
                    outsideFocusSeconds: isFocusing ? 0 : 1
                )
                ctx.insert(entry)
            }

            // Save periodically (every 30 seconds) to avoid constant writes
            if tickCount % 30 == 0 {
                try ctx.save()
            }
        } catch {
            log("Failed to track app usage: \(error)")
        }
    }

    // MARK: - Coach Signal Feed

    private func feedCoachSignals(vm: TimerViewModel) {
        let switchRate = FocusCoachEngine.computeAppSwitchRate(
            switchTimestamps: appSwitchTimestamps,
            windowSeconds: 60
        )

        // Compute non-work foreground ratio from today's during-focus entries
        var totalFocusSeconds: Int = 0
        var distractingFocusSeconds: Int = 0
        if let ctx = modelContext {
            let today = Calendar.current.startOfDay(for: Date())
            let descriptor = FetchDescriptor<AppUsageEntry>(
                predicate: #Predicate { $0.date == today }
            )
            if let entries = try? ctx.fetch(descriptor) {
                for entry in entries {
                    totalFocusSeconds += entry.duringFocusSeconds
                    if entry.category == .distracting {
                        distractingFocusSeconds += entry.duringFocusSeconds
                    }
                }
            }
        }
        let nonWorkRatio = totalFocusSeconds > 0
            ? Double(distractingFocusSeconds) / Double(totalFocusSeconds)
            : 0

        // Start delay: track time until user engages with a productive (non-distracting) app
        if !hasEngagedProductively {
            if nonWorkRatio < 0.5 && totalFocusSeconds > 5 {
                hasEngagedProductively = true
            } else if let sessionStart = vm.coachEngine.sessionStartedAt {
                startDelaySeconds = Date().timeIntervalSince(sessionStart)
            }
        }

        var signals = vm.coachEngine.currentSignals
        signals.appSwitchesPerMinute = switchRate
        signals.nonWorkForegroundRatio = nonWorkRatio
        signals.inactivityBurstSeconds = Double(inactivitySeconds)
        signals.startDelaySeconds = startDelaySeconds
        vm.coachEngine.recordBehaviorSample(signals)
    }

    // MARK: - SuspiciousContextObservation Builder

    private func buildObservation(
        bundleId: String,
        appName: String,
        isInSession: Bool,
        selectedProjectId: UUID?,
        selectedWorkMode: WorkMode?
    ) -> SuspiciousContextObservation {
        var obs = SuspiciousContextObservation(
            bundleIdentifier: bundleId,
            localizedAppName: appName,
            selectedProjectId: selectedProjectId,
            selectedWorkMode: selectedWorkMode,
            isInSession: isInSession
        )

        if isBrowser(bundleId: bundleId) {
            obs.browserHost = extractBrowserDomain(appName: appName, bundleId: bundleId)
            obs.browserPageTitle = extractBrowserTitle(appName: appName)
        }

        if isTerminalOrEditor(bundleId: bundleId) {
            obs.terminalWorkspace = detectGitRepoRoot()
            obs.editorWorkspace = extractEditorWorkspace(bundleId: bundleId, appName: appName)
        }

        return obs
    }

    private func isBrowser(bundleId: String) -> Bool {
        let browsers = ["com.apple.Safari", "com.google.Chrome", "company.thebrowser.Browser",
                        "org.mozilla.firefox", "com.microsoft.edgemac", "com.operasoftware.Opera"]
        return browsers.contains(bundleId)
    }

    private func isTerminalOrEditor(bundleId: String) -> Bool {
        let tools = ["com.apple.Terminal", "com.googlecode.iterm2", "com.github.warp.1",
                     "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92",
                     "com.jetbrains.intellij", "com.sublimetext.4", "com.panic.Nova"]
        return tools.contains(bundleId)
            || bundleId.contains("jetbrains")
            || bundleId.contains("cursor")
    }

    private func extractBrowserDomain(appName: String, bundleId: String) -> String? {
        // Fallback: derive domain from window-title keywords until AX API access is confirmed.
        let name = appName.lowercased()
        let knownDomains: [(needle: String, domain: String)] = [
            ("youtube", "youtube.com"), ("reddit", "reddit.com"),
            ("twitter", "twitter.com"), ("x.com", "x.com"),
            ("instagram", "instagram.com"), ("facebook", "facebook.com"),
            ("tiktok", "tiktok.com"), ("netflix", "netflix.com"),
            ("github", "github.com"), ("stackoverflow", "stackoverflow.com"),
            ("linkedin", "linkedin.com"), ("twitch", "twitch.tv")
        ]
        return knownDomains.first(where: { name.contains($0.needle) })?.domain
    }

    private func extractBrowserTitle(appName: String) -> String? {
        return nil  // Placeholder — AX API enrichment in future iteration
    }

    private func detectGitRepoRoot() -> String? {
        // Walk up from the frontmost terminal/editor bundle URL looking for a .git directory.
        guard let bundleURL = NSWorkspace.shared.runningApplications
            .first(where: { isTerminalOrEditor(bundleId: $0.bundleIdentifier ?? "") })?
            .bundleURL else { return nil }
        var url = bundleURL
        for _ in 0..<3 {
            let gitDir = url.appendingPathComponent(".git")
            if FileManager.default.fileExists(atPath: gitDir.path) {
                return url.lastPathComponent
            }
            url = url.deletingLastPathComponent()
        }
        return nil
    }

    private func extractEditorWorkspace(bundleId: String, appName: String) -> String? {
        return nil  // Placeholder for workspace name extraction
    }

    // MARK: - Logging

    private func log(_ message: String) {
        #if DEBUG
        print("[AppUsageTracker] \(message)")
        #endif
    }
}
