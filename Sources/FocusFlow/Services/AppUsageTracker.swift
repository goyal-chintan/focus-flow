import AppKit
import CoreGraphics
import Foundation
import SwiftData

/// Tracks app foreground time, records per-app usage, and sends nudge notifications.
@MainActor
final class AppUsageTracker {
    static let shared = AppUsageTracker()

    // MARK: - Adaptive Tracking Cadence

    enum TrackingCadence: Equatable {
        /// 1 s polling during active focus — full precision for usage attribution.
        case precision
        /// 4 s polling outside focus — reduces energy impact while idle/background.
        case eco

        var interval: TimeInterval {
            switch self {
            case .precision: return 1
            case .eco: return 4
            }
        }

        /// Browser context refresh interval. Shorter during focus for accurate domain
        /// attribution; longer when idle to reduce AX/CGWindow queries.
        var browserRefreshInterval: TimeInterval {
            switch self {
            case .precision: return 12
            case .eco: return 30
            }
        }

        static func forState(isFocusing: Bool) -> TrackingCadence {
            isFocusing ? .precision : .eco
        }
    }

    struct FrontmostContextPresentation: Equatable {
        let browserHost: String?
        let displayLabel: String
        let domainLabel: String?
        let effectiveWindowTitle: String
        let category: AppUsageEntry.AppCategory
    }

    struct ObservationProjectScope: Equatable {
        let selectedProjectId: UUID?
        let selectedProjectName: String?
        let selectedWorkMode: WorkMode?
    }

    /// A single app/domain entry detected as distracting during the most recent focus session.
    struct SessionDistractingEntry: Sendable {
        let bundleIdentifier: String
        let displayLabel: String
        /// "app:<bundleId>" or "domain:<host>"
        let normalizedKey: String
        let seconds: Int

        var isBrowserDomain: Bool { normalizedKey.hasPrefix("domain:") }

        /// The raw host (for domains) or bundle identifier (for apps).
        var domainOrBundleKey: String {
            isBrowserDomain
                ? String(normalizedKey.dropFirst("domain:".count))
                : bundleIdentifier
        }
    }

    private struct UsageDelta {
        var duringFocusSeconds: Int = 0
        var outsideFocusSeconds: Int = 0

        var hasChanges: Bool {
            duringFocusSeconds > 0 || outsideFocusSeconds > 0
        }

        mutating func addSeconds(_ seconds: Int, isFocusing: Bool) {
            if isFocusing {
                duringFocusSeconds += seconds
            } else {
                outsideFocusSeconds += seconds
            }
        }
    }

    private struct AppliedUsageDelta {
        let bundleId: String
        let delta: UsageDelta
        let entry: AppUsageEntry
        let wasInserted: Bool
    }

    private var trackingTimer: Timer?
    private var currentCadence: TrackingCadence = .eco
    private var lastSampleAt: Date?
    private var sampleRemainder: TimeInterval = 0
    private var idleSeconds: Int = 0
    private var isTracking = false
    private var nudgeCount: Int = 0
    private weak var timerVM: TimerViewModel?
    private var modelContext: ModelContext?
    private var tickCount: Int = 0
    private var currentTrackingDay: Date = Calendar.current.startOfDay(for: Date())
    private var appEntriesByBundleID: [String: AppUsageEntry] = [:]
    private var pendingUsageDeltasByBundleID: [String: UsageDelta] = [:]
    private var pendingAppNamesByBundleID: [String: String] = [:]
    private var totalFocusSecondsToday: Int = 0
    private var distractingFocusSecondsToday: Int = 0

    // Session-scoped distraction tracking — reset at session start, captured at session end.
    private var sessionDistractingAppSeconds: [String: Int] = [:]   // sessionKey → seconds
    private var sessionDistractingAppNames: [String: String] = [:]  // sessionKey → display label
    private var sessionDistractingAppBundleIds: [String: String] = [:] // sessionKey → bundleId
    private var lastPersistAt: Date = .distantPast
    private let persistInterval: TimeInterval = 30
    #if DEBUG
    private var testingShouldFailNextSave = false
    #endif

    // Coach signal tracking
    private var appSwitchTimestamps: [Date] = []
    private var lastFrontmostBundleId: String = ""
    private var lastFrontmostWindowTitle: String = ""
    private var lastFrontmostBrowserHost: String?
    private var lastFrontmostDisplayLabel: String?
    private var lastFrontmostDomainLabel: String?
    private var lastBrowserContextRefreshAt: Date = .distantPast
    private let browserDomainResolver: BrowserDomainResolver
    private let appUsageCaptureWriter: AppUsageCaptureWriter
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

    var currentFrontmostBrowserHost: String? {
        guard !lastFrontmostBundleId.isEmpty,
              lastFrontmostBundleId != Bundle.main.bundleIdentifier else { return nil }
        return lastFrontmostBrowserHost
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

    static func frontmostContextPresentation(
        bundleIdentifier: String,
        appName: String,
        windowTitle: String,
        resolvedBrowserHost: String?,
        settings: AppSettings?,
        idleSeverityOverride: IdleDistractionSeverity? = nil
    ) -> FrontmostContextPresentation {
        let appLabel = AppUsageEntry.recommendationDisplayLabel(for: "app:\(bundleIdentifier)")
        let shouldCollectRawDomains = settings?.coachCollectRawDomains == true
        let browserHost = shouldCollectRawDomains
            ? AppUsageEntry.normalizedBrowserHost(from: resolvedBrowserHost)
            : nil
        let domainLabel = browserHost.map(AppUsageEntry.domainDisplayName(for:))
        let effectiveWindowTitle = shouldCollectRawDomains ? windowTitle : appName
        let displayLabel = domainLabel ?? appLabel
        let category = idleAdjustedCategory(
            frontmostCategory: AppUsageEntry.classify(
                bundleIdentifier: bundleIdentifier,
                appName: appName,
                windowTitle: effectiveWindowTitle,
                browserHost: browserHost
            ),
            idleSeverityOverride: idleSeverityOverride
        )

        return FrontmostContextPresentation(
            browserHost: browserHost,
            displayLabel: displayLabel,
            domainLabel: domainLabel,
            effectiveWindowTitle: effectiveWindowTitle,
            category: category
        )
    }

    static func idleAdjustedCategory(
        frontmostCategory: AppUsageEntry.AppCategory,
        idleSeverityOverride: IdleDistractionSeverity?
    ) -> AppUsageEntry.AppCategory {
        switch idleSeverityOverride {
        case .major:
            return .distracting
        case .minor, .allowed:
            return .neutral
        case nil:
            return frontmostCategory
        }
    }

    static func observationProjectScope(
        isInSession: Bool,
        selectedProjectId: UUID?,
        selectedProjectName: String?,
        selectedWorkMode: WorkMode?
    ) -> ObservationProjectScope {
        guard isInSession else {
            return ObservationProjectScope(
                selectedProjectId: nil,
                selectedProjectName: nil,
                selectedWorkMode: nil
            )
        }

        return ObservationProjectScope(
            selectedProjectId: selectedProjectId,
            selectedProjectName: selectedProjectName,
            selectedWorkMode: selectedWorkMode
        )
    }

    static func focusTotals(for entries: [AppUsageEntry]) -> (totalFocusSeconds: Int, distractingFocusSeconds: Int) {
        let totalFocusSeconds = entries.reduce(0) { sum, entry in
            guard !CompanionAnalyticsBuilder.isPersistedDomainBundleIdentifier(entry.bundleIdentifier) else {
                // Domain rows are additive browser detail, including malformed historical keys.
                return sum
            }
            return sum + entry.duringFocusSeconds
        }

        let distractingFocusSeconds = entries.reduce(0) { sum, entry in
            if let host = CompanionAnalyticsBuilder.validPersistedDomainHost(for: entry.bundleIdentifier) {
                let category = AppUsageEntry.classify(
                    bundleIdentifier: "domain:\(host)",
                    appName: entry.appName,
                    browserHost: host
                )
                return sum + (category == .distracting ? entry.duringFocusSeconds : 0)
            }

            guard !CompanionAnalyticsBuilder.isPersistedDomainBundleIdentifier(entry.bundleIdentifier) else {
                return sum
            }
            guard !AppUsageEntry.isBrowserBundleIdentifier(entry.bundleIdentifier) else {
                return sum
            }
            return sum + (entry.category == .distracting ? entry.duringFocusSeconds : 0)
        }

        return (totalFocusSeconds, distractingFocusSeconds)
    }

    static func shouldRefreshBrowserContext(
        bundleId: String,
        lastFrontmostBundleId: String,
        now: Date,
        lastRefreshAt: Date,
        cadence: TrackingCadence
    ) -> Bool {
        bundleId != lastFrontmostBundleId
            || now.timeIntervalSince(lastRefreshAt) >= cadence.browserRefreshInterval
    }

    private init(
        browserDomainResolver: BrowserDomainResolver = BrowserDomainResolver(),
        appUsageCaptureWriter: AppUsageCaptureWriter = AppUsageCaptureWriter()
    ) {
        self.browserDomainResolver = browserDomainResolver
        self.appUsageCaptureWriter = appUsageCaptureWriter
    }

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
        pendingUsageDeltasByBundleID.removeAll()
        pendingAppNamesByBundleID.removeAll()
        totalFocusSecondsToday = 0
        distractingFocusSecondsToday = 0
        currentTrackingDay = Calendar.current.startOfDay(for: Date())
        hydrateDailyCache()
        lastPersistAt = Date()
        currentCadence = TrackingCadence.forState(isFocusing: timerVM.state == .focusing)
        lastSampleAt = Date()
        sampleRemainder = 0

        trackingTimer = Timer.scheduledTimer(withTimeInterval: currentCadence.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
        if let timer = trackingTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
        log("Started tracking")
    }

    func syncCadence(isFocusing: Bool) {
        guard isTracking else { return }
        let desiredCadence = TrackingCadence.forState(isFocusing: isFocusing)
        guard desiredCadence != currentCadence else { return }
        flushElapsedSample(isFocusing: currentCadence == .precision)
        currentCadence = desiredCadence
        rescheduleTrackingTimer()
    }

    /// Clears session-scoped distraction data. Call at the start of every new focus session.
    func resetSessionDistractionTracking() {
        sessionDistractingAppSeconds.removeAll()
        sessionDistractingAppNames.removeAll()
        sessionDistractingAppBundleIds.removeAll()
    }

    /// Snapshot of apps/domains detected as distracting during the current (or most recent) focus session.
    /// Returns entries with ≥10 seconds of screen time, sorted by duration descending.
    var sessionDistractingEntries: [SessionDistractingEntry] {
        sessionDistractingAppSeconds
            .compactMap { sessionKey, secs -> SessionDistractingEntry? in
                guard secs >= 10 else { return nil }  // filter sub-10s noise
                let label = sessionDistractingAppNames[sessionKey]
                    ?? AppUsageEntry.recommendationDisplayLabel(for: sessionKey)
                let bundleId = sessionDistractingAppBundleIds[sessionKey] ?? bundleIdFromSessionKey(sessionKey)
                return SessionDistractingEntry(
                    bundleIdentifier: bundleId,
                    displayLabel: label,
                    normalizedKey: sessionKey,
                    seconds: secs
                )
            }
            .sorted { $0.seconds > $1.seconds }
    }

    private func bundleIdFromSessionKey(_ key: String) -> String {
        if key.hasPrefix("app:") {
            return String(key.dropFirst(4))
        }
        return "unknown"
    }

    func stop() {
        // Flush any elapsed time since the last tick so it's not lost on shutdown
        flushElapsedSample(isFocusing: currentCadence == .precision)
        persistIfNeeded(force: true)
        trackingTimer?.invalidate()
        trackingTimer = nil
        isTracking = false
        lastSampleAt = nil
        sampleRemainder = 0
        idleSeconds = 0
        nudgeCount = 0
        log("Stopped tracking")
    }

    private func flushElapsedSample(isFocusing: Bool, now: Date = Date()) {
        let elapsedSeconds = consumeElapsedSeconds(now: now)
        guard elapsedSeconds > 0 else { return }

        // Skip attribution when FocusFlow itself is frontmost (consistent with trackFrontmostApp)
        guard let bundleId = currentFrontmostBundleId else { return }

        if isFocusing {
            totalFocusSecondsToday += elapsedSeconds
            if lastFrontmostCategory == .distracting {
                distractingFocusSecondsToday += elapsedSeconds
            }
        }

        let appName = currentFrontmostAppName
            ?? pendingAppNamesByBundleID[bundleId]
            ?? AppUsageEntry.recommendationDisplayLabel(for: "app:\(bundleId)")

        recordUsageDelta(bundleId: bundleId, appName: appName, isFocusing: isFocusing, seconds: elapsedSeconds)

        if let identity = appUsageCaptureWriter.browserDomainUsageIdentity(
            resolvedHost: currentFrontmostBrowserHost,
            settings: timerVM?.settings
        ) {
            recordUsageDelta(
                bundleId: identity.bundleIdentifier,
                appName: identity.appName,
                isFocusing: isFocusing,
                seconds: elapsedSeconds
            )
        }
    }

    private func consumeElapsedSeconds(now: Date) -> Int {
        guard let lastSampleAt else {
            self.lastSampleAt = now
            return 0
        }

        let rawElapsed = max(0, sampleRemainder + now.timeIntervalSince(lastSampleAt))
        let wholeSeconds = Int(rawElapsed.rounded(.down))
        self.lastSampleAt = now
        sampleRemainder = rawElapsed - TimeInterval(wholeSeconds)
        return wholeSeconds
    }

    /// Re-creates the tracking timer at the current cadence interval.
    private func rescheduleTrackingTimer() {
        trackingTimer?.invalidate()
        trackingTimer = Timer.scheduledTimer(withTimeInterval: currentCadence.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
        if let timer = trackingTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
        log("Cadence switched to \(currentCadence == .precision ? "precision (1s)" : "eco (4s)")")
    }

    // MARK: - Tick

    private func tick() {
        guard let vm = timerVM else { return }
        rolloverDayIfNeeded()
        let now = Date()

        tickCount += 1
        let isFocusing = vm.state == .focusing

        // Switch tracking cadence when focus state changes
        let desiredCadence = TrackingCadence.forState(isFocusing: isFocusing)
        if desiredCadence != currentCadence {
            // Attribute elapsed seconds to previous focus state before switching cadence
            flushElapsedSample(isFocusing: currentCadence == .precision, now: now)
            currentCadence = desiredCadence
            rescheduleTrackingTimer()
        }

        let elapsedSeconds = consumeElapsedSeconds(now: now)
        trackFrontmostApp(isFocusing: isFocusing, elapsedSeconds: elapsedSeconds, now: now)

        // Feed coach signals every 30 seconds during focus
        if isFocusing, vm.settings?.coachRealtimeEnabled == true, tickCount % 30 == 0 {
            feedCoachSignals(vm: vm)
        }

        // Only count idle time when not in a session
        let isIdle = vm.state == .idle && !vm.isOvertime
        if isIdle {
            idleSeconds += elapsedSeconds

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

    private func trackFrontmostApp(isFocusing: Bool, elapsedSeconds: Int, now: Date) {
        guard modelContext != nil else { return }

        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return }
        let bundleId = frontApp.bundleIdentifier ?? "unknown"
        let appName = frontApp.localizedName ?? "Unknown"
        let windowTitle: String
        let resolvedBrowserHost: String?
        let shouldCollectRawDomains = timerVM?.settings?.coachCollectRawDomains == true
        if isBrowser(bundleId: bundleId) {
            let shouldRefreshBrowserContext = Self.shouldRefreshBrowserContext(
                bundleId: bundleId,
                lastFrontmostBundleId: lastFrontmostBundleId,
                now: now,
                lastRefreshAt: lastBrowserContextRefreshAt,
                cadence: currentCadence
            )
            if shouldRefreshBrowserContext {
                let resolvedTitle = shouldCollectRawDomains
                    ? (currentWindowTitle(processID: frontApp.processIdentifier) ?? appName)
                    : appName
                let resolvedHost = shouldCollectRawDomains
                    ? browserDomainResolver.resolve(
                        bundleIdentifier: bundleId,
                        windowTitle: resolvedTitle,
                        appName: appName
                    )?.host
                    : nil
                lastFrontmostWindowTitle = resolvedTitle
                lastFrontmostBrowserHost = resolvedHost
                lastBrowserContextRefreshAt = now
                windowTitle = resolvedTitle
                resolvedBrowserHost = resolvedHost
            } else {
                windowTitle = shouldCollectRawDomains
                    ? (lastFrontmostWindowTitle.isEmpty ? appName : lastFrontmostWindowTitle)
                    : appName
                resolvedBrowserHost = shouldCollectRawDomains ? lastFrontmostBrowserHost : nil
            }
        } else {
            windowTitle = appName
            resolvedBrowserHost = nil
            lastFrontmostWindowTitle = windowTitle
            lastFrontmostBrowserHost = nil
            lastBrowserContextRefreshAt = .distantPast
        }
        let contextPresentation = Self.frontmostContextPresentation(
            bundleIdentifier: bundleId,
            appName: appName,
            windowTitle: windowTitle,
            resolvedBrowserHost: resolvedBrowserHost,
            settings: timerVM?.settings
        )
        let browserHost = contextPresentation.browserHost

        // Skip FocusFlow itself — avoid mutating lastFrontmostCategory/labels so that
        // flushElapsedSample attributes seconds correctly when a cadence sync fires
        // while FocusFlow is frontmost.
        if bundleId == Bundle.main.bundleIdentifier { return }

        lastFrontmostDomainLabel = contextPresentation.domainLabel
        lastFrontmostDisplayLabel = contextPresentation.displayLabel
        lastFrontmostCategory = contextPresentation.category

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
            let projectScope = Self.observationProjectScope(
                isInSession: isFocusing,
                selectedProjectId: timerVM?.selectedProject?.id,
                selectedProjectName: timerVM?.selectedProject?.name,
                selectedWorkMode: timerVM?.selectedProject?.workMode
            )
            let obs = buildObservation(
                bundleId: bundleId,
                appName: appName,
                windowTitle: contextPresentation.effectiveWindowTitle,
                browserHost: browserHost,
                isInSession: isFocusing,
                selectedProjectId: projectScope.selectedProjectId,
                selectedProjectName: projectScope.selectedProjectName,
                selectedWorkMode: projectScope.selectedWorkMode
            )
            onSuspiciousObservation?(obs)
        } else {
            inactivitySeconds += elapsedSeconds
        }

        if elapsedSeconds > 0 {
            recordUsageDelta(
                bundleId: bundleId,
                appName: appName,
                isFocusing: isFocusing,
                seconds: elapsedSeconds
            )
            if isFocusing {
                totalFocusSecondsToday += elapsedSeconds
                if contextPresentation.category == .distracting {
                    distractingFocusSecondsToday += elapsedSeconds
                    // Session-scoped tracking: record for post-session distraction review.
                    // Use domain key when browser domain is resolved, otherwise app bundle key.
                    let sessionKey = browserHost.map { "domain:\($0)" } ?? "app:\(bundleId)"
                    sessionDistractingAppSeconds[sessionKey, default: 0] += elapsedSeconds
                    sessionDistractingAppNames[sessionKey] = contextPresentation.displayLabel
                    sessionDistractingAppBundleIds[sessionKey] = bundleId
                }
            }
        }

        // For browser tab contexts, optionally persist a domain-keyed entry so Guardian Recommendations
        // can aggregate time per website rather than per browser app.
        if let identity = appUsageCaptureWriter.browserDomainUsageIdentity(
            resolvedHost: browserHost,
            settings: timerVM?.settings
        ) {
            if elapsedSeconds > 0 {
                recordUsageDelta(
                    bundleId: identity.bundleIdentifier,
                    appName: identity.appName,
                    isFocusing: isFocusing,
                    seconds: elapsedSeconds
                )
            }
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
            let totals = Self.focusTotals(for: entries)
            totalFocusSecondsToday = totals.totalFocusSeconds
            distractingFocusSecondsToday = totals.distractingFocusSeconds
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
    ) -> (entry: AppUsageEntry, wasInserted: Bool) {
        if let cached = appEntriesByBundleID[bundleId] {
            if cached.appName != appName {
                cached.appName = appName
            }
            return (cached, false)
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
            return (existing, false)
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
        return (newEntry, true)
    }

    private func persistIfNeeded(force: Bool = false) {
        guard let ctx = modelContext else { return }
        let now = Date()
        guard force || now.timeIntervalSince(lastPersistAt) >= persistInterval else { return }

        let appliedDeltas = hasPendingUsageDeltas ? applyPendingUsageDeltas(context: ctx) : []

        do {
            try persistContext(ctx)
            clearPendingUsageDeltas()
            lastPersistAt = now
        } catch {
            if !appliedDeltas.isEmpty {
                revertAppliedUsageDeltas(appliedDeltas, context: ctx)
            }
            log("Failed to persist app usage: \(error)")
        }
    }

    private var hasPendingUsageDeltas: Bool {
        pendingUsageDeltasByBundleID.values.contains(where: \.hasChanges)
    }

    private func recordUsageDelta(bundleId: String, appName: String, isFocusing: Bool, seconds: Int) {
        var delta = pendingUsageDeltasByBundleID[bundleId, default: UsageDelta()]
        delta.addSeconds(seconds, isFocusing: isFocusing)
        pendingUsageDeltasByBundleID[bundleId] = delta
        pendingAppNamesByBundleID[bundleId] = appName
    }

    private func applyPendingUsageDeltas(context: ModelContext) -> [AppliedUsageDelta] {
        guard hasPendingUsageDeltas else { return [] }
        var appliedDeltas: [AppliedUsageDelta] = []

        for (bundleId, delta) in pendingUsageDeltasByBundleID where delta.hasChanges {
            let appName = pendingAppNamesByBundleID[bundleId]
                ?? appEntriesByBundleID[bundleId]?.appName
                ?? AppUsageEntry.recommendationDisplayLabel(for: "app:\(bundleId)")
            let resolved = entryForCurrentDay(bundleId: bundleId, appName: appName, context: context)
            resolved.entry.duringFocusSeconds += delta.duringFocusSeconds
            resolved.entry.outsideFocusSeconds += delta.outsideFocusSeconds
            appliedDeltas.append(
                AppliedUsageDelta(
                    bundleId: bundleId,
                    delta: delta,
                    entry: resolved.entry,
                    wasInserted: resolved.wasInserted
                )
            )
        }

        return appliedDeltas
    }

    private func clearPendingUsageDeltas() {
        pendingUsageDeltasByBundleID.removeAll()
        pendingAppNamesByBundleID.removeAll()
    }

    private func revertAppliedUsageDeltas(_ appliedDeltas: [AppliedUsageDelta], context: ModelContext) {
        for applied in appliedDeltas.reversed() {
            applied.entry.duringFocusSeconds -= applied.delta.duringFocusSeconds
            applied.entry.outsideFocusSeconds -= applied.delta.outsideFocusSeconds
            if applied.wasInserted,
               applied.entry.duringFocusSeconds == 0,
               applied.entry.outsideFocusSeconds == 0 {
                context.delete(applied.entry)
                appEntriesByBundleID.removeValue(forKey: applied.bundleId)
            }
        }
    }

    private func persistContext(_ context: ModelContext) throws {
        #if DEBUG
        if testingShouldFailNextSave {
            testingShouldFailNextSave = false
            throw NSError(
                domain: "AppUsageTrackerTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Injected AppUsageTracker save failure"]
            )
        }
        #endif

        try context.save()
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
        AppUsageEntry.isBrowserBundleIdentifier(bundleId)
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

#if DEBUG
extension AppUsageTracker {
    static func makeForTesting(
        browserDomainResolver: BrowserDomainResolver = BrowserDomainResolver(),
        appUsageCaptureWriter: AppUsageCaptureWriter = AppUsageCaptureWriter()
    ) -> AppUsageTracker {
        AppUsageTracker(
            browserDomainResolver: browserDomainResolver,
            appUsageCaptureWriter: appUsageCaptureWriter
        )
    }

    var testingPendingDeltaCount: Int {
        pendingUsageDeltasByBundleID.filter(\.value.hasChanges).count
    }

    var testingCurrentCadence: TrackingCadence {
        currentCadence
    }

    func testingConfigurePersistence(modelContext: ModelContext, day: Date) {
        self.modelContext = modelContext
        currentTrackingDay = Calendar.current.startOfDay(for: day)
        appEntriesByBundleID.removeAll()
        pendingUsageDeltasByBundleID.removeAll()
        pendingAppNamesByBundleID.removeAll()
        hydrateDailyCache()
    }

    func testingSetLastPersistAt(_ date: Date) {
        lastPersistAt = date
    }

    func testingRecordUsageDelta(bundleId: String, appName: String, isFocusing: Bool, seconds: Int = 1) {
        recordUsageDelta(bundleId: bundleId, appName: appName, isFocusing: isFocusing, seconds: seconds)
    }

    func testingPersistIfNeeded(force: Bool = false) {
        persistIfNeeded(force: force)
    }

    func testingFailNextSave() {
        testingShouldFailNextSave = true
    }

    func testingSetCurrentCadence(_ cadence: TrackingCadence) {
        currentCadence = cadence
    }

    func testingSetIsTracking(_ isTracking: Bool) {
        self.isTracking = isTracking
    }

    func testingSetFrontmostContext(
        bundleId: String,
        appName: String,
        browserHost: String? = nil,
        category: AppUsageEntry.AppCategory = .neutral
    ) {
        lastFrontmostBundleId = bundleId
        pendingAppNamesByBundleID[bundleId] = appName
        lastFrontmostBrowserHost = browserHost
        lastFrontmostCategory = category
    }

    func testingSetLastSampleAt(_ date: Date?) {
        lastSampleAt = date
    }

    func testingFlushElapsedSample(isFocusing: Bool, now: Date) {
        flushElapsedSample(isFocusing: isFocusing, now: now)
    }
}
#endif
