import AppKit
import CoreGraphics
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
    private var currentTrackingDay: Date = Calendar.current.startOfDay(for: Date())
    private var appEntriesByBundleID: [String: AppUsageEntry] = [:]
    private var totalFocusSecondsToday: Int = 0
    private var distractingFocusSecondsToday: Int = 0
    private var lastPersistAt: Date = .distantPast
    private let persistInterval: TimeInterval = 30

    // Coach signal tracking
    private var appSwitchTimestamps: [Date] = []
    private var lastFrontmostBundleId: String = ""
    private var lastFrontmostWindowTitle: String = ""
    private var lastFrontmostBrowserHost: String?
    private var lastFrontmostDisplayLabel: String?
    private var lastFrontmostDomainLabel: String?
    private var lastBrowserContextRefreshAt: Date = .distantPast
    private let browserContextRefreshInterval: TimeInterval = 12
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

    var currentFrontmostDisplayLabel: String? {
        guard !lastFrontmostBundleId.isEmpty,
              lastFrontmostBundleId != Bundle.main.bundleIdentifier else { return nil }
        return lastFrontmostDisplayLabel
    }

    var currentFrontmostDomainLabel: String? {
        guard !lastFrontmostBundleId.isEmpty,
              lastFrontmostBundleId != Bundle.main.bundleIdentifier else { return nil }
        return lastFrontmostDomainLabel
    }

    var recentAppSwitchTimestamps: [Date] {
        appSwitchTimestamps
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
        lastFrontmostWindowTitle = ""
        lastFrontmostBrowserHost = nil
        lastFrontmostDisplayLabel = nil
        lastFrontmostDomainLabel = nil
        lastBrowserContextRefreshAt = .distantPast
        inactivitySeconds = 0
        hasEngagedProductively = false
        startDelaySeconds = 0
        lastFrontmostCategory = .neutral
        appEntriesByBundleID.removeAll()
        totalFocusSecondsToday = 0
        distractingFocusSecondsToday = 0
        currentTrackingDay = Calendar.current.startOfDay(for: Date())
        hydrateDailyCache()
        lastPersistAt = Date()

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
        persistIfNeeded(force: true)
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
        rolloverDayIfNeeded()

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
        let now = Date()
        let windowTitle: String
        let browserHost: String?
        if isBrowser(bundleId: bundleId) {
            let shouldRefreshBrowserContext =
                bundleId != lastFrontmostBundleId
                || now.timeIntervalSince(lastBrowserContextRefreshAt) >= browserContextRefreshInterval
            if shouldRefreshBrowserContext {
                let resolvedTitle = currentWindowTitle(processID: frontApp.processIdentifier) ?? appName
                let resolvedHost = extractBrowserDomain(
                    windowTitle: resolvedTitle,
                    appName: appName,
                    bundleId: bundleId
                )
                lastFrontmostWindowTitle = resolvedTitle
                lastFrontmostBrowserHost = resolvedHost
                lastBrowserContextRefreshAt = now
                windowTitle = resolvedTitle
                browserHost = resolvedHost
            } else {
                windowTitle = lastFrontmostWindowTitle.isEmpty ? appName : lastFrontmostWindowTitle
                browserHost = lastFrontmostBrowserHost
            }
        } else {
            windowTitle = appName
            browserHost = nil
            lastFrontmostWindowTitle = windowTitle
            lastFrontmostBrowserHost = nil
            lastBrowserContextRefreshAt = .distantPast
        }
        let domainLabel = browserHost.map { AppUsageEntry.recommendationDisplayLabel(for: $0) }
        let appLabel = AppUsageEntry.recommendationDisplayLabel(for: "app:\(bundleId)")
        lastFrontmostDomainLabel = domainLabel
        lastFrontmostDisplayLabel = domainLabel ?? appLabel
        lastFrontmostCategory = AppUsageEntry.classify(
            bundleIdentifier: bundleId,
            appName: appName,
            windowTitle: windowTitle,
            browserHost: browserHost
        )

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
                windowTitle: windowTitle,
                browserHost: browserHost,
                isInSession: isFocusing,
                selectedProjectId: timerVM?.selectedProject?.id,
                selectedProjectName: timerVM?.selectedProject?.name,
                selectedWorkMode: timerVM?.selectedProject?.workMode
            )
            onSuspiciousObservation?(obs)
        } else {
            inactivitySeconds += 1
        }

        let entry = entryForCurrentDay(bundleId: bundleId, appName: appName, context: ctx)
        if isFocusing {
            entry.duringFocusSeconds += 1
            totalFocusSecondsToday += 1
            if entry.category == .distracting {
                distractingFocusSecondsToday += 1
            }
        } else {
            entry.outsideFocusSeconds += 1
        }

        persistIfNeeded()
    }

    // MARK: - Coach Signal Feed

    private func feedCoachSignals(vm: TimerViewModel) {
        let switchRate = FocusCoachEngine.computeAppSwitchRate(
            switchTimestamps: appSwitchTimestamps,
            windowSeconds: 60
        )

        // Reuse in-memory counters to avoid recurring full-day fetches.
        let totalFocusSeconds = totalFocusSecondsToday
        let distractingFocusSeconds = distractingFocusSecondsToday
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

    private func hydrateDailyCache() {
        guard let ctx = modelContext else { return }
        let day = currentTrackingDay
        let descriptor = FetchDescriptor<AppUsageEntry>(
            predicate: #Predicate { $0.date == day }
        )
        do {
            let entries = try ctx.fetch(descriptor)
            appEntriesByBundleID = Dictionary(uniqueKeysWithValues: entries.map { ($0.bundleIdentifier, $0) })
            totalFocusSecondsToday = entries.reduce(0) { $0 + $1.duringFocusSeconds }
            distractingFocusSecondsToday = entries.reduce(0) { sum, entry in
                sum + (entry.category == .distracting ? entry.duringFocusSeconds : 0)
            }
        } catch {
            appEntriesByBundleID.removeAll()
            totalFocusSecondsToday = 0
            distractingFocusSecondsToday = 0
            log("Failed to hydrate app usage cache: \(error)")
        }
    }

    private func rolloverDayIfNeeded() {
        let today = Calendar.current.startOfDay(for: Date())
        guard today != currentTrackingDay else { return }
        persistIfNeeded(force: true)
        currentTrackingDay = today
        appEntriesByBundleID.removeAll()
        totalFocusSecondsToday = 0
        distractingFocusSecondsToday = 0
        hydrateDailyCache()
    }

    private func entryForCurrentDay(
        bundleId: String,
        appName: String,
        context: ModelContext
    ) -> AppUsageEntry {
        if let cached = appEntriesByBundleID[bundleId] {
            if cached.appName != appName {
                cached.appName = appName
            }
            return cached
        }

        let day = currentTrackingDay
        let descriptor = FetchDescriptor<AppUsageEntry>(
            predicate: #Predicate { entry in
                entry.date == day && entry.bundleIdentifier == bundleId
            }
        )

        if let existing = try? context.fetch(descriptor).first {
            if existing.appName != appName {
                existing.appName = appName
            }
            appEntriesByBundleID[bundleId] = existing
            return existing
        }

        let newEntry = AppUsageEntry(
            date: day,
            appName: appName,
            bundleIdentifier: bundleId,
            duringFocusSeconds: 0,
            outsideFocusSeconds: 0
        )
        context.insert(newEntry)
        appEntriesByBundleID[bundleId] = newEntry
        return newEntry
    }

    private func persistIfNeeded(force: Bool = false) {
        guard let ctx = modelContext else { return }
        let now = Date()
        guard force || now.timeIntervalSince(lastPersistAt) >= persistInterval else { return }
        do {
            try ctx.save()
            lastPersistAt = now
        } catch {
            log("Failed to persist app usage: \(error)")
        }
    }

    // MARK: - SuspiciousContextObservation Builder

    private func buildObservation(
        bundleId: String,
        appName: String,
        windowTitle: String?,
        browserHost: String?,
        isInSession: Bool,
        selectedProjectId: UUID?,
        selectedProjectName: String?,
        selectedWorkMode: WorkMode?
    ) -> SuspiciousContextObservation {
        var obs = SuspiciousContextObservation(
            bundleIdentifier: bundleId,
            localizedAppName: appName,
            selectedProjectId: selectedProjectId,
            selectedProjectName: selectedProjectName,
            selectedWorkMode: selectedWorkMode,
            isInSession: isInSession
        )

        if isBrowser(bundleId: bundleId) {
            obs.browserHost = browserHost
            obs.browserPageTitle = windowTitle ?? extractBrowserTitle(appName: appName)
        }

        if isTerminalOrEditor(bundleId: bundleId) {
            obs.terminalWorkspace = detectGitRepoRoot()
            obs.editorWorkspace = extractEditorWorkspace(bundleId: bundleId, appName: appName)
        }

        // Classify preliminary disposition during active focus sessions
        if isInSession {
            obs.suggestedDisposition = classifyDisposition(
                bundleId: bundleId,
                appName: appName,
                browserHost: obs.browserHost
            )
        }

        return obs
    }

    /// Infers a preliminary ContextDisposition for an observation made during a focus session.
    private func classifyDisposition(
        bundleId: String,
        appName: String,
        browserHost: String?
    ) -> ContextDisposition {
        // Docs / notes apps → least suspicious
        let docsApps = ["com.apple.Notes", "com.notion.id", "md.obsidian",
                        "com.evernote.Evernote", "com.microsoft.Word",
                        "com.apple.iWork.Pages", "net.shinyfrog.bear"]
        if docsApps.contains(bundleId) || bundleId.contains("notion") || bundleId.contains("obsidian") {
            return .plannedResearch
        }

        // Terminals / editors → required context switch (working, just elsewhere)
        if isTerminalOrEditor(bundleId: bundleId) {
            return .requiredContextSwitch
        }

        // AI / chat tools → procrastinating by default (user can override)
        if isAIChatTool(bundleId, appName) {
            return .procrastinating
        }

        // Browsers: check the specific domain for stronger signal
        if isBrowser(bundleId: bundleId) {
            let socialEntertainment: [String] = [
                "youtube.com", "twitter.com", "x.com", "reddit.com",
                "instagram.com", "tiktok.com", "netflix.com", "twitch.tv",
                "facebook.com", "9gag.com", "buzzfeed.com"
            ]
            let newsForums: [String] = [
                "news.ycombinator.com", "medium.com", "substack.com",
                "theverge.com", "techcrunch.com", "hackernews.com",
                "bbc.com", "cnn.com", "nytimes.com"
            ]
            if let host = browserHost {
                if socialEntertainment.contains(where: { host.contains($0) }) {
                    return .procrastinating
                }
                if newsForums.contains(where: { host.contains($0) }) {
                    return .lowPriorityWork
                }
            }
            // Unknown browser context → procrastinating by default during focus
            return .procrastinating
        }

        // Default for unrecognised apps during focus
        return .procrastinating
    }

    /// Returns true for AI assistants, chat tools, and messaging apps
    /// that are typically unrelated to focused work.
    private func isAIChatTool(_ bundleId: String, _ appName: String) -> Bool {
        let id = bundleId.lowercased()
        let name = appName.lowercased()
        let idMatches = id.contains("anthropic") || id.contains("openai") ||
                        id.contains("slack") || id.contains("discord") ||
                        id.contains("telegram") || id.contains("whatsapp") ||
                        id.contains("copilot")
        let nameMatches = name.contains("claude") || name.contains("chatgpt") ||
                          name.contains("cursor ai") || name.contains("copilot") ||
                          name.contains("slack") || name.contains("discord") ||
                          name.contains("telegram") || name.contains("whatsapp")
        return idMatches || nameMatches
    }
    private func isBrowser(bundleId: String) -> Bool {
        let browsers = ["com.apple.Safari", "com.google.Chrome", "company.thebrowser.Browser",
                        "org.mozilla.firefox", "com.microsoft.edgemac", "com.operasoftware.Opera"]
        return browsers.contains(bundleId)
    }

    private func isTerminalOrEditor(bundleId: String) -> Bool {
        let tools = ["com.apple.Terminal", "com.googlecode.iterm2", "com.github.warp.1",
                     "com.mitchellh.ghostty", "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92",
                     "com.jetbrains.intellij", "com.sublimetext.4", "com.panic.Nova"]
        return tools.contains(bundleId)
            || bundleId.contains("jetbrains")
            || bundleId.contains("cursor")
    }

    private func currentWindowTitle(processID: pid_t) -> String? {
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return nil
        }
        for window in windows {
            guard let ownerPid = window[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPid == processID else { continue }
            guard let layer = window[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            guard let title = window[kCGWindowName as String] as? String else { continue }
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
    }

    private func extractBrowserDomain(windowTitle: String, appName: String, bundleId: String) -> String? {
        let text = "\(windowTitle) \(appName) \(bundleId)".lowercased()
        if let range = text.range(of: #"([a-z0-9-]+\.)+[a-z]{2,}"#, options: .regularExpression) {
            let host = String(text[range])
                .replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression)
            if !host.isEmpty {
                return host
            }
        }
        let knownDomains: [(needle: String, domain: String)] = [
            ("youtube", "youtube.com"), ("reddit", "reddit.com"),
            ("twitter", "twitter.com"), ("x.com", "x.com"),
            ("instagram", "instagram.com"), ("facebook", "facebook.com"),
            ("tiktok", "tiktok.com"), ("netflix", "netflix.com"),
            ("github", "github.com"), ("stackoverflow", "stackoverflow.com"),
            ("linkedin", "linkedin.com"), ("twitch", "twitch.tv")
        ]
        return knownDomains.first(where: { text.contains($0.needle) })?.domain
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
