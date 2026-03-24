import Foundation
import SwiftUI
import SwiftData

enum TimerState: Equatable {
    case idle
    case focusing
    case paused
    case onBreak(SessionType)
}

#if DEBUG
extension TimerViewModel {
    /// Lightweight setup used by UI evidence/snapshot tests to avoid side effects
    /// from full app configuration (timers, tracker bootstrapping, save observers).
    func configureForEvidence(modelContext: ModelContext, settings: AppSettings) {
        timer?.invalidate()
        pauseTimer?.invalidate()
        midnightTimer?.invalidate()

        timer = nil
        pauseTimer = nil
        midnightTimer = nil

        self.modelContext = modelContext
        self.settings = settings
        isConfigured = true
        coachEngine.configureStore(SwiftDataCoachStore(modelContext: modelContext))
    }

    /// Seeds deterministic completion/overtime state without running timers.
    func seedEvidenceCompletionState(
        sessionType: SessionType,
        project: Project?,
        customLabel: String?,
        duration: TimeInterval,
        overtimeSeconds: Int
    ) {
        let session = FocusSession(
            type: sessionType,
            duration: duration,
            project: project,
            customLabel: customLabel
        )
        session.startedAt = Date().addingTimeInterval(-duration)
        session.endedAt = Date()
        session.completed = true

        selectedProject = project
        state = .idle
        remainingSeconds = 0
        totalSeconds = duration

        lastCompletedSession = session
        lastCompletionWasBreak = (sessionType != .focus)
        if sessionType == .focus {
            lastCompletedFocusSession = session
            lastCompletedDuration = duration
            lastCompletedLabel = session.label
        } else {
            lastCompletedDuration = nil
            lastCompletedLabel = nil
        }

        isOvertime = overtimeSeconds > 0
        self.overtimeSeconds = max(0, overtimeSeconds)
        showSessionComplete = true
        isManualStop = false
    }
}
#endif

enum PostCompletionAction {
    case continueOvertime
    case continueFocusing
    case takeBreak
    case endSession
}

// MARK: - Crash Recovery State
/// Lightweight checkpoint written to UserDefaults every 30s during active focus.
/// Survives crashes because macOS flushes UserDefaults to plist automatically.
struct CrashRecoveryState: Codable {
    let sessionId: UUID
    var remainingSeconds: TimeInterval
    let totalSeconds: TimeInterval
    var isPaused: Bool
    var checkpointDate: Date
    let projectId: UUID?
    let customLabel: String?
    let completedFocusSessions: Int

    private static let key = "FocusFlow.crashRecoveryState"
    /// Maximum age before recovery is considered stale.
    static let maxRecoveryAge: TimeInterval = 2 * 60 * 60 // 2 hours

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }

    static func load() -> CrashRecoveryState? {
        guard let data = UserDefaults.standard.data(forKey: Self.key) else { return nil }
        return try? JSONDecoder().decode(CrashRecoveryState.self, from: data)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: Self.key)
    }
}

@MainActor
@Observable
final class TimerViewModel {
    // MARK: - State
    var state: TimerState = .idle
    var remainingSeconds: TimeInterval = 0
    var totalSeconds: TimeInterval = 0
    var completedFocusSessions: Int = 0
    var selectedProject: Project?
    var customLabel: String = ""

    // MARK: - Custom Duration
    var selectedMinutes: Int = 25

    var focusDuration: TimeInterval {
        TimeInterval(max(5, selectedMinutes) * 60)
    }

    // MARK: - Pause Tracking
    var pauseStartTime: Date? = nil
    var pauseElapsed: TimeInterval = 0
    private var pauseTimer: Timer? = nil

    // MARK: - Crash Recovery
    /// Set during `configure()` if a recoverable session is detected from a previous crash.
    var recoveryState: CrashRecoveryState? = nil
    /// The project associated with the recoverable session (fetched from DB).
    var recoveryProject: Project? = nil

    /// Focus sessions shorter than this are treated as test/noise sessions and removed from history.
    private static let minimumRetainedFocusSeconds: TimeInterval = 5 * 60

    var pauseTimeString: String {
        let mins = Int(pauseElapsed) / 60
        let secs = Int(pauseElapsed) % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    enum PauseWarningLevel {
        case normal      // < 2 min
        case warning     // 2-5 min
        case critical    // > 5 min

        var color: Color {
            switch self {
            case .normal: return .secondary
            case .warning: return .orange
            case .critical: return .red
            }
        }
    }

    var pauseWarningLevel: PauseWarningLevel {
        if pauseElapsed > 300 { return .critical }
        if pauseElapsed > 120 { return .warning }
        return .normal
    }

    var pauseWarningMessage: String {
        switch pauseWarningLevel {
        case .normal:   return "Deep work momentum is fading..."
        case .warning:  return "2 min paused — focus is slipping away"
        case .critical: return "5+ min paused — consider restarting"
        }
    }

    // MARK: - Start Error Feedback
    var startError: String? = nil

    // MARK: - Save Error Feedback
    var saveError: String? = nil

    // MARK: - Session Completion
    var showSessionComplete: Bool = false
    /// True when user manually stopped mid-session (vs natural timer completion).
    var isManualStop: Bool = false
    var hasStaleBlocking: Bool = false
    var lastCompletedDuration: TimeInterval? = nil
    var lastCompletedLabel: String? = nil
    private(set) var lastCompletedSession: FocusSession? = nil
    private(set) var lastCompletedFocusSession: FocusSession? = nil
    private(set) var lastCompletionWasBreak: Bool = false

    // MARK: - Overtime
    var isOvertime: Bool = false
    var overtimeSeconds: Int = 0

    /// True when the completed session was a focus session (not a break).
    var isFocusOvertime: Bool { isOvertime && lastCompletedSession?.type == .focus }
    /// True when the completed session was a break (break ran past its duration).
    var isBreakOvertime: Bool { isOvertime && lastCompletedSession?.type != .focus }

    // MARK: - Today Stats
    var todayFocusTime: TimeInterval = 0
    var todaySessionCount: Int = 0

    // MARK: - Day Boundary
    private var currentDay: Date = Calendar.current.startOfDay(for: Date())
    private var midnightTimer: Timer?

    // MARK: - Window Lifecycle
    /// Set by FocusFlowApp to open the session-complete window from any context
    var openCompletionWindow: (() -> Void)?
    /// Set by FocusFlowApp to open the strong coach intervention window
    var openCoachInterventionWindow: (() -> Void)?
    /// Set by FocusFlowApp to request foreground activation based on policy.
    var requestAppActivation: (() -> Void)?

    /// Direct reference to the MenuBarExtra's hosting window.
    /// Set by PopoverWindowAccessor embedded in MenuBarPopoverView.
    /// Using a direct reference avoids the fragile responder-chain
    /// `NSApp.sendAction(NSPopover.performClose)` that silently fails
    /// when another window is key.
    weak var popoverWindow: NSWindow?

    /// Reliably closes the menu bar popover using direct window reference.
    func closePopover() {
        popoverWindow?.close()
    }

    // MARK: - Private
    private var timer: Timer?
    private var modelContext: ModelContext?
    private var currentSession: FocusSession?
    private(set) var settings: AppSettings?

    // MARK: - Focus Coach
    private(set) var coachEngine = FocusCoachEngine()
    private let coachPlanner = FocusCoachInterventionPlanner()
    private let coachOpportunityModel = FocusCoachOpportunityModel()
    private let guardianAdvisor = FocusCoachGuardianAdvisor()
    private var coachTickCounter: Int = 0
    private var pauseCountThisSession: Int = 0
    private var strongPromptsShownThisSession: Int = 0
    private var lastIdleInterventionAt: Date?
    private var guardianReleaseUntil: Date?

    /// Whether the reason chip sheet should be shown (driven by coach engine anomaly detection)
    var showCoachReasonSheet: Bool = false
    var pendingReasonKind: FocusCoachInterruptionKind = .drift
    /// Non-blocking inline reason chips shown when resuming from an extended pause (≥2 min).
    var showPauseReasonChips: Bool = false
    var showCoachInterventionWindow: Bool = false
    var activeCoachInterventionDecision: FocusCoachDecision?
    var currentCoachQuickPromptDecision: FocusCoachDecision?
    var currentIdleStarterDecision: FocusCoachDecision?
    var idleStarterSummary: String?
    var idleStarterRecommendedMinutes: Int?

    var activeCoachPopoverDecision: FocusCoachDecision? {
        currentCoachQuickPromptDecision ?? currentIdleStarterDecision
    }

    var isGuardianInReleaseWindow: Bool {
        guard let guardianReleaseUntil else { return false }
        return Date() < guardianReleaseUntil
    }

    /// Pre-session intention data (set from IdlePopoverContent, persisted on startFocus)
    var coachTaskType: FocusCoachTaskType = .deepWork
    var coachResistance: Int = 3

    // MARK: - Computed
    var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        if isOvertime {
            // During overtime, progress exceeds 1.0 — used by TimerRingView for overtime ring fill
            return 1.0 + (Double(overtimeSeconds) / totalSeconds)
        }
        return 1 - (remainingSeconds / totalSeconds)
    }

    var timeString: String {
        let minutes = Int(remainingSeconds) / 60
        let seconds = Int(remainingSeconds) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var overtimeTimeString: String {
        let mins = overtimeSeconds / 60
        let secs = overtimeSeconds % 60
        return String(format: "+%02d:%02d", mins, secs)
    }

    var isRunning: Bool {
        switch state {
        case .focusing, .onBreak: return true
        default: return false
        }
    }

    var isBlockingActive: Bool { BlockingService.shared.isActive }

    var sessionLabel: String {
        selectedProject?.name ?? (customLabel.isEmpty ? "Focus" : customLabel)
    }

    var sessionsBeforeLongBreak: Int {
        settings?.sessionsBeforeLongBreak ?? 4
    }

    /// Progress through the current Pomodoro cycle (0.0 → 1.0).
    /// At 1.0 the user has earned a long break — celebrate completion.
    var cycleProgress: Double {
        let total = max(1, sessionsBeforeLongBreak)
        let position = completedFocusSessions % total
        return position == 0 && completedFocusSessions > 0 ? 1.0 : Double(position) / Double(total)
    }

    // MARK: - Setup
    private var isConfigured = false

    func configure(modelContext: ModelContext) {
        guard !isConfigured else { return }
        isConfigured = true
        self.modelContext = modelContext
        log("configure() called")
        loadSettings()
        log("settings loaded: \(settings != nil)")
        seedDefaultProfiles()
        cleanupOrphanedSessions()
        checkForRecoverableSession()
        purgeShortFocusSessions()
        loadTodayStats()
        // Don't call BlockingService.cleanupIfNeeded() here — it prompts for
        // admin password if stale /etc/hosts entries exist, which is jarring on
        // app launch. Instead, cleanup happens in deactivateBlocking().
        // Refresh notification authorization on the main actor so the Settings
        // banner accurately reflects whether notifications are enabled.
        Task { @MainActor in
            NotificationService.shared.refreshAuthorizationStatus()
        }
        if BlockingHelper.isBlockingActive() {
            hasStaleBlocking = true
            log("WARNING: Stale website blocking detected from previous crash")
        }
        scheduleMidnightRefresh()
        // Refresh today-total whenever a session is manually logged from the Companion window.
        NotificationCenter.default.addObserver(forName: .focusSessionLoggedManually, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.purgeShortFocusSessions()
                self?.loadTodayStats()
            }
        }
        // Start app usage tracking and nudge timer at launch (not deferred to popover open)
        AppUsageTracker.shared.start(timerVM: self, modelContext: modelContext)
        // Wire Focus Coach to persistent SwiftData store
        coachEngine.configureStore(SwiftDataCoachStore(modelContext: modelContext))
        log("configure() complete")
    }

    func ensureConfigured(modelContext: ModelContext) {
        if !isConfigured {
            configure(modelContext: modelContext)
        }
    }

    /// Schedules a timer to fire at midnight to refresh today's stats
    private func scheduleMidnightRefresh() {
        midnightTimer?.invalidate()
        let calendar = Calendar.current
        guard let nextMidnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date())) else { return }
        let interval = nextMidnight.timeIntervalSinceNow + 1 // 1 sec after midnight

        let t = Timer(fire: Date().addingTimeInterval(interval), interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.handleDayChange()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        midnightTimer = t
    }

    @MainActor
    private func handleDayChange() {
        currentDay = Calendar.current.startOfDay(for: Date())
        completedFocusSessions = 0
        loadTodayStats()
        // Schedule next midnight refresh
        scheduleMidnightRefresh()
    }

    private func cleanupOrphanedSessions() {
        let predicate = #Predicate<FocusSession> { $0.endedAt == nil }
        let descriptor = FetchDescriptor<FocusSession>(predicate: predicate)
        guard let orphans = try? modelContext?.fetch(descriptor) else { return }
        let recoveryId = CrashRecoveryState.load()?.sessionId
        for session in orphans {
            // Don't touch the session if crash recovery is pointing to it
            if session.id == recoveryId { continue }
            let elapsed = Date().timeIntervalSince(session.startedAt)
            let minimumKeep = session.type == .focus ? Self.minimumRetainedFocusSeconds : 60
            if elapsed < minimumKeep {
                modelContext?.delete(session)
            } else {
                session.endedAt = session.startedAt.addingTimeInterval(min(elapsed, session.duration))
                session.completed = false
            }
        }
        saveContext()
    }

    /// Checks UserDefaults for a crash recovery checkpoint and populates `recoveryState` if valid.
    private func checkForRecoverableSession() {
        guard let saved = CrashRecoveryState.load() else { return }

        let timeSinceCrash = Date().timeIntervalSince(saved.checkpointDate)

        // Too stale — discard recovery state
        if timeSinceCrash > CrashRecoveryState.maxRecoveryAge {
            log("Recovery state too stale (\(Int(timeSinceCrash))s) — clearing")
            CrashRecoveryState.clear()
            return
        }

        // Verify the session still exists in the database
        let sessionId = saved.sessionId
        let predicate = #Predicate<FocusSession> { $0.id == sessionId }
        let descriptor = FetchDescriptor<FocusSession>(predicate: predicate)
        guard let session = try? modelContext?.fetch(descriptor).first else {
            log("Recovery session not found in DB — clearing")
            CrashRecoveryState.clear()
            return
        }

        // Calculate adjusted remaining time
        var adjustedRemaining = saved.remainingSeconds
        if !saved.isPaused {
            // Timer was running — subtract time elapsed since crash
            adjustedRemaining -= timeSinceCrash
        }

        if adjustedRemaining <= 0 {
            // Session would have completed while app was down — mark complete
            log("Recovery: session completed while away — marking complete")
            session.endedAt = session.startedAt.addingTimeInterval(session.duration)
            session.completed = true
            saveContext()
            CrashRecoveryState.clear()
            loadTodayStats()
            return
        }

        // Valid recovery — populate observable state for UI banner
        var recovery = saved
        recovery.remainingSeconds = adjustedRemaining
        recovery.checkpointDate = saved.checkpointDate
        recoveryState = recovery

        // Fetch the associated project for display
        if let projectId = saved.projectId {
            let projPredicate = #Predicate<Project> { $0.id == projectId }
            let projDescriptor = FetchDescriptor<Project>(predicate: projPredicate)
            recoveryProject = try? modelContext?.fetch(projDescriptor).first
        }

        log("Recovery available: \(Int(adjustedRemaining))s remaining, paused=\(saved.isPaused), crashed \(Int(timeSinceCrash))s ago")
    }

    /// Resumes a focus session from crash recovery state.
    func resumeFromRecovery() {
        guard let recovery = recoveryState else { return }
        log("Resuming from crash recovery: \(Int(recovery.remainingSeconds))s remaining")

        // Fetch the session from DB
        let sessionId = recovery.sessionId
        let predicate = #Predicate<FocusSession> { $0.id == sessionId }
        let descriptor = FetchDescriptor<FocusSession>(predicate: predicate)
        guard let session = try? modelContext?.fetch(descriptor).first else {
            log("Recovery session vanished from DB — aborting resume")
            discardRecovery()
            return
        }

        // Restore timer state
        currentSession = session
        session.endedAt = nil // Re-open the session
        remainingSeconds = recovery.remainingSeconds
        totalSeconds = recovery.totalSeconds
        selectedProject = recoveryProject
        customLabel = recovery.customLabel ?? ""
        completedFocusSessions = recovery.completedFocusSessions
        isOvertime = false
        overtimeSeconds = 0

        if recovery.isPaused {
            state = .paused
            pauseStartTime = Date()
            pauseElapsed = 0
            startPauseTimer()
        } else {
            state = .focusing
            startTimer()
        }

        // Re-activate blocking if the project has a blocking profile
        activateBlocking()

        // Restart coach for this session
        coachEngine.startSession(id: session.id)
        pauseCountThisSession = 0
        strongPromptsShownThisSession = 0
        coachTickCounter = 0

        saveContext()
        saveCrashRecoveryCheckpoint()

        // Clear recovery UI state
        recoveryState = nil
        recoveryProject = nil

        log("Session resumed successfully")
    }

    /// Discards crash recovery state without resuming. Session record stays in DB as-is.
    func discardRecovery() {
        log("Discarding crash recovery")
        clearCrashRecoveryState()
        recoveryState = nil
        recoveryProject = nil
        loadTodayStats()
    }

    private func purgeShortFocusSessions() {
        let descriptor = FetchDescriptor<FocusSession>()
        guard let sessions = try? modelContext?.fetch(descriptor) else { return }
        let recoveryId = recoveryState?.sessionId

        var deletedAny = false
        for session in sessions where session.type == .focus && session.endedAt != nil && session.actualDuration < Self.minimumRetainedFocusSeconds {
            if session.id == recoveryId { continue }
            if lastCompletedSession?.id == session.id {
                lastCompletedSession = nil
                lastCompletedDuration = nil
                lastCompletedLabel = nil
            }
            modelContext?.delete(session)
            deletedAny = true
        }

        if deletedAny {
            saveContext()
        }
    }

    private func loadSettings() {
        let descriptor = FetchDescriptor<AppSettings>()
        settings = try? modelContext?.fetch(descriptor).first
        if settings == nil {
            let newSettings = AppSettings()
            modelContext?.insert(newSettings)
            saveContext()
            settings = newSettings
        }
        if var settings {
            FocusCoachSettingsNormalizer.normalize(&settings)
            selectedMinutes = Int(settings.focusDuration / 60)
            if selectedProject == nil,
               let lastId = settings.lastUsedProjectId,
               let uuid = UUID(uuidString: lastId) {
                let descriptor = FetchDescriptor<Project>(predicate: #Predicate { $0.id == uuid && !$0.archived })
                selectedProject = try? modelContext?.fetch(descriptor).first
            }
        }
    }

    func loadTodayStats() {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: startOfDay),
              let yesterday = calendar.date(byAdding: .day, value: -1, to: startOfDay) else { return }
        var descriptor = FetchDescriptor<FocusSession>(
            predicate: #Predicate<FocusSession> { session in
                session.startedAt >= yesterday
            }
        )
        descriptor.sortBy = [SortDescriptor(\.startedAt, order: .reverse)]
        guard let recentSessions = try? modelContext?.fetch(descriptor) else { return }
        let focusSessions = recentSessions.filter { session in
            guard session.type == .focus else { return false }
            if session.endedAt != nil, session.actualDuration < Self.minimumRetainedFocusSeconds {
                return false
            }
            let sessionEnd = session.endedAt ?? session.startedAt.addingTimeInterval(session.actualDuration)
            return sessionEnd > startOfDay && session.startedAt < tomorrow
        }
        let newCount = focusSessions.filter(\.completed).count
        let newFocusTime = focusSessions.reduce(0) { sum, session in
            let sessionEnd = session.endedAt ?? session.startedAt.addingTimeInterval(session.actualDuration)
            let overlapStart = max(session.startedAt, startOfDay)
            let overlapEnd = min(sessionEnd, tomorrow)
            return sum + max(0, overlapEnd.timeIntervalSince(overlapStart))
        }
        // Only update @Observable properties if values actually changed (avoids unnecessary re-renders)
        if todaySessionCount != newCount { todaySessionCount = newCount }
        // Reconcile with DB — allow up to 60s drift from live tick incrementing
        if abs(todayFocusTime - newFocusTime) > 60 { todayFocusTime = newFocusTime }
        if completedFocusSessions != newCount { completedFocusSessions = newCount }
    }

    // MARK: - Actions
    func startFocus() {
        startError = nil
        guard settings != nil, !isOvertime else {
            log("startFocus: settings nil or overtime, aborting")
            startError = settings == nil ? "Settings not loaded. Please restart the app." : "Complete the current session first."
            return
        }
        guard state == .idle else {
            log("startFocus: not idle (state=\(state)), aborting")
            startError = "A session is already in progress."
            return
        }
        let duration = focusDuration
        guard duration >= 300 else {
            log("startFocus: duration \(duration) < 300, aborting")
            startError = "Minimum session duration is 5 minutes."
            return
        }
        log("startFocus: duration=\(duration), project=\(selectedProject?.name ?? "none")")
        totalSeconds = duration
        remainingSeconds = duration
        state = .focusing

        let session = FocusSession(
            type: .focus,
            duration: duration,
            project: selectedProject,
            customLabel: customLabel.isEmpty ? nil : customLabel
        )
        modelContext?.insert(session)
        currentSession = session
        if let project = selectedProject {
            settings?.lastUsedProjectId = project.id.uuidString
        }
        saveContext() // Persist session immediately — crash safety
        saveCrashRecoveryCheckpoint() // Write initial recovery state to UserDefaults
        startTimer()
        // Focus Coach: start session tracking
        pauseCountThisSession = 0
        strongPromptsShownThisSession = 0
        lastIdleInterventionAt = nil
        showCoachInterventionWindow = false
        activeCoachInterventionDecision = nil
        currentCoachQuickPromptDecision = nil
        currentIdleStarterDecision = nil
        idleStarterSummary = nil
        idleStarterRecommendedMinutes = nil
        guardianReleaseUntil = nil
        coachEngine.promptBudget = settings?.coachPromptBudgetPerSession ?? 4
        coachEngine.currentTaskResistance = coachResistance
        coachEngine.startSession(id: session.id)
        // Persist TaskIntent from pre-session check-in if coach is enabled
        if settings?.coachRealtimeEnabled == true {
            let taskTitle = selectedProject?.name ?? (customLabel.isEmpty ? "Focus" : customLabel)
            let intent = TaskIntent(
                title: taskTitle,
                taskType: coachTaskType,
                expectedResistance: coachResistance,
                suggestedDurationMinutes: selectedMinutes,
                sessionId: session.id
            )
            modelContext?.insert(intent)
            coachEngine.currentTaskIntentId = intent.id
            saveContext()
        }
        coachResistance = 3
        // Project-based blocking only: activate if selected project has a profile.
        activateBlocking()
        closePopover()
    }

    /// Switches to a different project mid-session, splitting the current session.
    /// - The current session is saved with elapsed time (project A).
    /// - A new session starts with the remaining time (project B).
    /// - Blocking profile swaps if the new project has a different one.
    func switchProject(to newProject: Project?, reason: FocusCoachReason) {
        guard state == .focusing || state == .paused, let _ = settings else { return }
        let wasState = state

        // 1. Save elapsed time on current session
        let elapsed = totalSeconds - remainingSeconds
        if let session = currentSession {
            session.endedAt = Date()
            session.completed = false
            if elapsed >= Self.minimumRetainedFocusSeconds {
                saveContext()
            } else {
                modelContext?.delete(session)
                saveContext()
            }
        }

        // 2. Record the switch as a coach interruption
        coachEngine.recordAnomaly(kind: .projectSwitch, reason: reason, sessionId: currentSession?.id)

        // 3. Deactivate old blocking profile
        deactivateBlocking()

        // 4. Switch project and start new session with remaining time
        selectedProject = newProject
        let newDuration = max(remainingSeconds, 60) // at least 1 min
        totalSeconds = newDuration
        remainingSeconds = newDuration
        state = .focusing

        let session = FocusSession(
            type: .focus,
            duration: newDuration,
            project: selectedProject,
            customLabel: customLabel.isEmpty ? nil : customLabel
        )
        modelContext?.insert(session)
        currentSession = session
        saveContext()

        // 5. Resume timer if we were paused
        if wasState == .paused {
            pauseTimer?.invalidate()
            pauseTimer = nil
            pauseStartTime = nil
            pauseElapsed = 0
        }
        startTimer()

        // 6. Activate new blocking profile
        activateBlocking()

        log("switchProject: switched to \(newProject?.name ?? "none"), remaining=\(Int(newDuration))s")
    }

    private func log(_ msg: String) {
        #if DEBUG
        let path = "/tmp/focusflow_debug.log"
        let entry = "[\(Date())] \(msg)\n"
        if FileManager.default.fileExists(atPath: path) {
            if let handle = FileHandle(forWritingAtPath: path) {
                handle.seekToEndOfFile()
                handle.write(entry.data(using: .utf8)!)
                handle.closeFile()
            }
        } else {
            try? entry.write(toFile: path, atomically: true, encoding: .utf8)
        }
        #endif
    }

    /// Saves the model context, logging errors. Non-critical saves (cleanup, stats refresh)
    /// use this to avoid disrupting the user.
    private func saveContext(caller: String = #function) {
        do {
            try modelContext?.save()
        } catch {
            log("Save failed in \(caller): \(error.localizedDescription)")
            saveError = error.localizedDescription
            // Auto-clear after 5 seconds
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(5))
                if self?.saveError == error.localizedDescription {
                    self?.saveError = nil
                }
            }
        }
    }

    /// Called on app termination to flush active session state to disk.
    func saveSessionBeforeTermination() {
        guard let currentSession, currentSession.endedAt == nil else { return }
        currentSession.endedAt = Date()
        saveContext(caller: "appTermination")
        saveCrashRecoveryCheckpoint()
    }

    /// Writes current timer state to UserDefaults for crash recovery.
    private func saveCrashRecoveryCheckpoint() {
        guard let session = currentSession, state == .focusing || state == .paused else { return }
        let checkpoint = CrashRecoveryState(
            sessionId: session.id,
            remainingSeconds: remainingSeconds,
            totalSeconds: totalSeconds,
            isPaused: state == .paused,
            checkpointDate: Date(),
            projectId: session.project?.id,
            customLabel: session.customLabel,
            completedFocusSessions: completedFocusSessions
        )
        checkpoint.save()
    }

    /// Clears crash recovery state from UserDefaults — called on every normal session ending.
    private func clearCrashRecoveryState() {
        CrashRecoveryState.clear()
    }

    func startBreak() {
        guard let settings, !isOvertime else { return }
        // Guard against zero/negative sessionsBeforeLongBreak to prevent division-by-zero
        let sessionsPerCycle = max(1, settings.sessionsBeforeLongBreak)
        let isLongBreak = completedFocusSessions > 0
            && (completedFocusSessions % sessionsPerCycle) == 0
        let type: SessionType = isLongBreak ? .longBreak : .shortBreak
        let duration = isLongBreak ? settings.longBreakDuration : settings.shortBreakDuration

        totalSeconds = duration
        remainingSeconds = duration
        state = .onBreak(type)

        let session = FocusSession(type: type, duration: duration)
        modelContext?.insert(session)
        currentSession = session
        clearCrashRecoveryState() // Focus session ended, break doesn't need recovery
        startTimer()
        closePopover()
    }

    func pause() {
        guard state == .focusing, !isOvertime else { return }
        timer?.invalidate()
        timer = nil
        state = .paused
        pauseStartTime = Date()
        pauseElapsed = 0
        pauseCountThisSession += 1
        coachEngine.updatePauseCount(pauseCountThisSession)
        startPauseTimer()
        saveCrashRecoveryCheckpoint() // Persist paused state for crash recovery
    }

    /// Maximum single session duration: 4 hours (prevents runaway extension)
    private static let maxSessionSeconds: TimeInterval = 4 * 60 * 60

    func extendTimer(by seconds: TimeInterval = 300) {
        guard state == .focusing, !isOvertime else { return }
        // Don't allow reducing below 60 seconds remaining
        if seconds < 0 && remainingSeconds + seconds < 60 { return }
        // Don't allow extending beyond 4-hour ceiling
        if seconds > 0 && totalSeconds + seconds > Self.maxSessionSeconds { return }
        remainingSeconds += seconds
        totalSeconds += seconds
        currentSession?.duration += seconds
    }

    /// True when -5min button can act (more than 5m + 60s buffer remaining)
    var canReduceTime: Bool {
        state == .focusing && !isOvertime && remainingSeconds > 360
    }

    /// True when +5min button can act (not at the 4-hour ceiling)
    var canExtendTime: Bool {
        state == .focusing && !isOvertime && totalSeconds + 300 <= Self.maxSessionSeconds
    }

    func resume() {
        guard state == .paused else { return }
        let wasPauseExtended = pauseElapsed >= 120 // 2+ min pause
        pauseTimer?.invalidate()
        pauseTimer = nil
        pauseStartTime = nil
        pauseElapsed = 0
        state = .focusing
        startTimer()
        saveCrashRecoveryCheckpoint() // Persist resumed state for crash recovery

        if wasPauseExtended && settings?.coachReasonPromptsEnabled == true {
            showPauseReasonChips = true
            pendingReasonKind = .drift
        }

        closePopover()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        pauseTimer?.invalidate()
        pauseTimer = nil
        pauseStartTime = nil
        pauseElapsed = 0
        isOvertime = false
        overtimeSeconds = 0
        isManualStop = false
        showSessionComplete = false
        showCoachReasonSheet = false
        showPauseReasonChips = false
        pendingReasonKind = .drift
        showCoachInterventionWindow = false
        activeCoachInterventionDecision = nil
        currentCoachQuickPromptDecision = nil
        currentIdleStarterDecision = nil
        idleStarterSummary = nil
        idleStarterRecommendedMinutes = nil
        strongPromptsShownThisSession = 0
        lastIdleInterventionAt = nil
        coachEngine.endSession()
        clearCrashRecoveryState()
        if let session = currentSession {
            session.endedAt = Date()
            session.completed = false
            // Keep only meaningful focus sessions in history.
            let minimumKeep = session.type == .focus ? Self.minimumRetainedFocusSeconds : 60
            if session.actualDuration < minimumKeep {
                modelContext?.delete(session)
            }
            saveContext()
        }
        loadTodayStats()
        deactivateBlocking()
        currentSession = nil
        state = .idle
        remainingSeconds = 0
        totalSeconds = 0
    }

    /// Routes a mid-session stop through SessionCompleteWindow so the user
    /// can record mood, achievement, and splits before the session is finalised.
    /// Only used when the session is long enough to be worth reflecting on (≥60s).
    func stopForReflection() {
        log("stopForReflection called, currentSession=\(currentSession != nil)")
        guard let session = currentSession else {
            stop()   // nothing to save
            return
        }
        // Too short to be worth a reflection window — just discard
        let elapsed = Date().timeIntervalSince(session.startedAt)
        log("stopForReflection: elapsed=\(elapsed)s, openCompletionWindow set=\(openCompletionWindow != nil)")
        if elapsed < Self.minimumRetainedFocusSeconds {
            abandonSession()
            return
        }
        timer?.invalidate()
        timer = nil
        pauseTimer?.invalidate()
        pauseTimer = nil
        pauseStartTime = nil
        pauseElapsed = 0

        session.endedAt = Date()
        session.completed = false
        saveContext()
        clearCrashRecoveryState()

        lastCompletedDuration = session.duration
        lastCompletedLabel = session.label
        lastCompletedSession = session
        lastCompletedFocusSession = session
        lastCompletionWasBreak = false
        currentSession = nil

        isManualStop = true
        isOvertime = false
        overtimeSeconds = 0
        state = .idle
        remainingSeconds = 0
        totalSeconds = 0
        showCoachInterventionWindow = false
        activeCoachInterventionDecision = nil
        currentCoachQuickPromptDecision = nil

        // Focus Coach: detect mid-session stop anomaly for reason capture
        if settings?.coachReasonPromptsEnabled == true, let lastSession = lastCompletedSession {
            let elapsed = lastSession.endedAt.map { $0.timeIntervalSince(lastSession.startedAt) } ?? 0
            let classifier = FocusCoachAnomalyClassifier()
            let event = FocusCoachAnomalyClassifier.SessionEvent.midSessionStop(
                elapsedSeconds: Int(elapsed),
                totalSeconds: Int(lastSession.duration)
            )
            if classifier.shouldPromptReason(event: event) {
                showCoachReasonSheet = true
                pendingReasonKind = .midSessionStop
            }
        }

        showSessionComplete = true
        closePopover()
        DispatchQueue.main.async { [weak self] in
            self?.openCompletionWindow?()
            self?.requestAppActivation?()
        }
        log("stopForReflection: showSessionComplete=\(showSessionComplete), openCompletionWindow called")
    }

    /// Called from SessionCompleteWindow "Discard" button after a manual stop.
    /// Deletes the session that was provisionally saved by stopForReflection().
    func discardManualStop() {
        if let session = lastCompletedSession {
            modelContext?.delete(session)
            saveContext()
        }
        isManualStop = false
        showSessionComplete = false
        showCoachReasonSheet = false
        showPauseReasonChips = false
        pendingReasonKind = .drift
        showCoachInterventionWindow = false
        activeCoachInterventionDecision = nil
        currentCoachQuickPromptDecision = nil
        lastCompletedSession = nil
        lastCompletedFocusSession = nil
        lastCompletionWasBreak = false
        lastCompletedDuration = nil
        lastCompletedLabel = nil
        loadTodayStats()
    }

    /// Called when SessionComplete window is closed without explicit action.
    /// Preserves the session (doesn't delete it) and resets UI state.
    func preserveManualStop() {
        isManualStop = false
        showSessionComplete = false
        showCoachReasonSheet = false
        showPauseReasonChips = false
        pendingReasonKind = .drift
        showCoachInterventionWindow = false
        activeCoachInterventionDecision = nil
        currentCoachQuickPromptDecision = nil
        lastCompletedSession = nil
        lastCompletedFocusSession = nil
        lastCompletionWasBreak = false
        lastCompletedDuration = nil
        lastCompletedLabel = nil
        loadTodayStats()
    }

    func abandonSession() {
        timer?.invalidate()
        timer = nil
        pauseTimer?.invalidate()
        pauseTimer = nil
        pauseStartTime = nil
        pauseElapsed = 0

        isOvertime = false
        overtimeSeconds = 0
        isManualStop = false
        showSessionComplete = false
        showCoachReasonSheet = false
        showPauseReasonChips = false
        pendingReasonKind = .drift
        showCoachInterventionWindow = false
        activeCoachInterventionDecision = nil
        currentCoachQuickPromptDecision = nil
        currentIdleStarterDecision = nil
        idleStarterSummary = nil
        idleStarterRecommendedMinutes = nil
        strongPromptsShownThisSession = 0
        lastIdleInterventionAt = nil
        coachEngine.endSession()
        clearCrashRecoveryState()
        guardianReleaseUntil = nil
        if let session = currentSession {
            modelContext?.delete(session)
            saveContext()
        }
        loadTodayStats()
        deactivateBlocking()
        currentSession = nil
        state = .idle
        remainingSeconds = 0
        totalSeconds = 0
        closePopover()
    }

    func skipBreak() {
        timer?.invalidate()
        timer = nil
        isOvertime = false
        overtimeSeconds = 0
        showSessionComplete = false
        showCoachInterventionWindow = false
        activeCoachInterventionDecision = nil
        currentCoachQuickPromptDecision = nil
        if currentSession?.type == .shortBreak || currentSession?.type == .longBreak {
            currentSession?.endedAt = Date()
            currentSession?.completed = false
        }
        saveContext()
        clearCrashRecoveryState()
        currentSession = nil
        // "Skip break" means continue momentum into the next focus block.
        state = .idle
        remainingSeconds = 0
        totalSeconds = 0
        loadTodayStats()
        startFocus()
    }

    // MARK: - Blocking
    var blockUntilGoalMet: Bool = false

    private func activateBlocking() {
        log("activateBlocking called")
        if let profile = selectedProject?.blockProfile {
            log("Using project-specific profile: \(profile.name)")
            BlockingService.shared.activate(profile: profile)
            return
        }
        log("No blocking profile assigned to selected project; skipping blocking.")
    }

    private func deactivateBlocking() {
        guard BlockingService.shared.isActive else { return }
        // If block-until-goal is enabled, keep blocking until daily goal is met
        if blockUntilGoalMet {
            let goal = settings?.dailyFocusGoal ?? 7200
            if todayFocusTime < goal {
                log("Block-until-goal: \(Int(todayFocusTime))s < \(Int(goal))s goal — keeping blocks active")
                return
            }
        }
        BlockingService.shared.deactivate()
        hasStaleBlocking = false
    }

    // MARK: - Timer
    private func startTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func startPauseTimer() {
        pauseTimer?.invalidate()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tickPause()
            }
        }
        pauseTimer = t
        RunLoop.main.add(t, forMode: .common)
    }

    @MainActor
    private func tickPause() {
        guard let pauseStartTime else { return }
        pauseElapsed = Date().timeIntervalSince(pauseStartTime)

        // Send notifications at thresholds
        if Int(pauseElapsed) == 120 { // 2 min
            NotificationService.shared.sendPauseWarning(minutes: 2)
        } else if Int(pauseElapsed) == 300 { // 5 min
            NotificationService.shared.sendPauseCritical(minutes: 5)
        }
    }

    @MainActor
    private func tick() {
        if isOvertime {
            overtimeSeconds += 1
            currentSession?.endedAt = Date()
            updateBreakOverrunReasonPromptIfNeeded()
            // Increment live focus time counter (no DB query needed)
            if state == .focusing || isOvertime {
                todayFocusTime += 1
            }
            if overtimeSeconds % 30 == 0 {
                saveContext()
                loadTodayStats() // Reconcile with DB periodically
            }
            return
        }
        guard remainingSeconds > 0 else { return }
        remainingSeconds -= 1
        // Increment live focus time during active focus
        if state == .focusing {
            todayFocusTime += 1
        }

        // Checkpoint save every 30s — crash recovery for session progress
        coachTickCounter += 1
        if coachTickCounter % 30 == 0 {
            currentSession?.endedAt = Date()
            saveContext()
            saveCrashRecoveryCheckpoint()
        }

        // Focus Coach: tick every 30 seconds during active focus
        if state == .focusing, settings?.coachRealtimeEnabled == true {
            if coachTickCounter % 30 == 0 {
                if let decision = coachEngine.tick() {
                    routeCoachDecision(decision)
                }
                // Check if engine triggered reason sheet
                if coachEngine.shouldShowReasonSheet, !showCoachReasonSheet {
                    showCoachReasonSheet = true
                    pendingReasonKind = coachEngine.pendingAnomalyKind ?? .drift
                    coachEngine.shouldShowReasonSheet = false
                }
            }
        }

        // Focus Coach: feed break overrun signal during breaks
        if case .onBreak = state, settings?.coachRealtimeEnabled == true {
            if remainingSeconds <= 0 {
                let overrunSeconds = Double(overtimeSeconds)
                coachEngine.updateBreakOverrun(overrunSeconds)
                // Check for break overrun anomaly (≥2 min) — only check every 30s
                if overtimeSeconds % 30 == 0 {
                    let classifier = FocusCoachAnomalyClassifier()
                    if classifier.shouldPromptReason(event: .breakOverrun(seconds: Int(overrunSeconds))),
                       !showCoachReasonSheet {
                        showCoachReasonSheet = true
                        pendingReasonKind = .breakOverrun
                    }
                }
            }
        }

        // Break duration monitoring — send warnings for long breaks
        if case .onBreak = state, let session = currentSession {
            let breakElapsed = Date().timeIntervalSince(session.startedAt)
            let breakElapsedInt = Int(breakElapsed)
            if breakElapsedInt == 120 {
                NotificationService.shared.sendBreakWarning(minutes: 2)
            } else if breakElapsedInt == 300 {
                NotificationService.shared.sendBreakCritical(minutes: 5)
            }
        }

        if remainingSeconds <= 0 {
            Task { @MainActor in
                await timerCompleted()
            }
        }
    }

    @MainActor
    private func timerCompleted() async {
        // Don't invalidate timer — continues for overtime
        currentSession?.endedAt = Date()
        currentSession?.completed = true
        saveContext()
        clearCrashRecoveryState()

        let wasType = currentSession?.type

        // Capture completion info
        lastCompletedSession = currentSession
        lastCompletionWasBreak = (wasType != .focus)
        if wasType == .focus {
            lastCompletedDuration = currentSession?.duration
            lastCompletedLabel = currentSession?.label
            lastCompletedFocusSession = currentSession
        }

        if wasType == .focus {
            completedFocusSessions += 1
            let sound = settings?.completionSound ?? "Glass"
            let label = currentSession?.label ?? "Focus"
            let duration = currentSession?.duration ?? 0
            NotificationService.shared.sendSessionCompletePrompt(duration: duration, label: label, sound: sound)

            // Calendar integration
            if settings?.calendarIntegrationEnabled == true, let session = currentSession {
                let calName = settings?.calendarName ?? "FocusFlow"
                let calId = settings?.selectedCalendarId
                let eventId = CalendarService.shared.createEvent(
                    title: session.label,
                    startDate: session.startedAt,
                    endDate: session.endedAt ?? Date(),
                    notes: session.achievement,
                    calendarName: calName,
                    calendarId: (calId?.isEmpty ?? true) ? nil : calId
                )
                session.calendarEventId = eventId
                saveContext()
            }
        } else {
            NotificationService.shared.sendBreakComplete(
                sessionCount: todaySessionCount,
                dailyGoalMinutes: Int((settings?.dailyFocusGoal ?? 7200) / 60),
                completedMinutes: Int(todayFocusTime / 60),
                sound: settings?.completionSound ?? "Glass"
            )
        }

        // Enter overtime — timer keeps running, counting up
        // State goes idle so popover doesn't show pause/stop
        loadTodayStats()
        isOvertime = true
        overtimeSeconds = 0
        remainingSeconds = 0
        state = .idle
        showSessionComplete = true
        closePopover()
        DispatchQueue.main.async { [weak self] in
            self?.openCompletionWindow?()
            self?.requestAppActivation?()
        }
        currentCoachQuickPromptDecision = nil
        activeCoachInterventionDecision = nil
        showCoachInterventionWindow = false
    }

    // MARK: - Reflection

    @MainActor
    func saveReflection(
        mood: FocusMood?,
        achievement: String?,
        reminderIdsToComplete: [String] = [],
        splits: [TimeSplitView.SplitEntry]? = nil
    ) async {
        guard let session = lastCompletedSession else { return }
        session.mood = mood
        session.achievement = achievement

        // Save splits if provided — skip zero/negative durations to prevent stat corruption
        if let splits, !splits.isEmpty, splits.count > 1 {
            for split in splits {
                let splitSeconds = TimeInterval(split.minutes * 60)
                guard splitSeconds > 0 else { continue }
                let timeSplit = TimeSplit(
                    project: split.project,
                    customLabel: split.customLabel.isEmpty ? nil : split.customLabel,
                    duration: splitSeconds
                )
                timeSplit.session = session
                modelContext?.insert(timeSplit)
            }
        }

        if !reminderIdsToComplete.isEmpty {
            for reminderId in reminderIdsToComplete {
                let ok = RemindersService.shared.completeReminder(identifier: reminderId)
                if !ok {
                    print("[TimerViewModel] Failed to complete reminder: \(reminderId)")
                }
            }
        }

        if let eventId = session.calendarEventId, !eventId.isEmpty {
            var noteLines: [String] = []
            if let achievement, !achievement.isEmpty {
                noteLines.append("Achievements:")
                for line in achievement
                    .components(separatedBy: .newlines)
                    .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
                    .filter({ !$0.isEmpty }) {
                    noteLines.append("• \(line)")
                }
            }
            if !reminderIdsToComplete.isEmpty {
                noteLines.append("")
                noteLines.append("Completed reminders: \(reminderIdsToComplete.count)")
            }
            let duration = Int(session.actualDuration / 60)
            noteLines.append("")
            noteLines.append("Duration: \(duration) minutes")
            noteLines.append("Recorded by FocusFlow")
            _ = CalendarService.shared.updateEvent(
                eventId: eventId,
                title: session.label,
                notes: noteLines.joined(separator: "\n"),
                startDate: session.startedAt,
                endDate: session.endedAt ?? Date()
            )
        }

        saveContext()
    }

    private func seedDefaultProfiles() {
        let descriptor = FetchDescriptor<BlockProfile>()
        let existing = (try? modelContext?.fetch(descriptor)) ?? []
        guard existing.isEmpty else { return }
        let social = BlockProfile(
            name: "Social Media",
            websites: ["youtube.com", "x.com", "twitter.com", "reddit.com", "instagram.com", "facebook.com", "tiktok.com"]
        )
        let fullFocus = BlockProfile(
            name: "Full Focus",
            websites: ["youtube.com", "x.com", "twitter.com", "reddit.com", "instagram.com", "facebook.com", "tiktok.com", "news.ycombinator.com", "netflix.com", "twitch.tv"],
            apps: ["com.tinyspeck.slackmacgap", "com.hnc.Discord", "ph.telegra.Telegraph", "net.whatsapp.WhatsApp"],
            mutedApps: ["com.tinyspeck.slackmacgap", "com.hnc.Discord"]
        )
        modelContext?.insert(social)
        modelContext?.insert(fullFocus)
        saveContext()
    }

    func continueAfterCompletion(action: PostCompletionAction) {
        if showCoachReasonSheet && pendingReasonKind == .breakOverrun {
            recordCoachReason(kind: .breakOverrun, reason: nil)
        }
        showSessionComplete = false
        isManualStop = false
        showCoachReasonSheet = false
        showPauseReasonChips = false
        pendingReasonKind = .drift

        if action == .continueOvertime {
            // Keep overtime state and timer running.
            return
        }

        closePopover()

        // Resolve completion and leave overtime mode.
        timer?.invalidate()
        timer = nil
        isOvertime = false
        overtimeSeconds = 0

        if let session = lastCompletedSession ?? currentSession {
            if session.type == .focus && session.actualDuration < Self.minimumRetainedFocusSeconds {
                modelContext?.delete(session)
            } else {
                session.endedAt = Date()
            }
            saveContext()
        }
        loadTodayStats()

        switch action {
        case .continueOvertime:
            break
        case .continueFocusing:
            startFocus()
        case .takeBreak:
            startBreak()
        case .endSession:
            deactivateBlocking()
            state = .idle
            loadTodayStats()
            currentSession = nil
        }
    }

    func updateBreakOverrunReasonPromptIfNeeded(completedSessionType: SessionType? = nil) {
        let sessionType = completedSessionType ?? lastCompletedSession?.type
        guard settings?.coachReasonPromptsEnabled == true,
              sessionType != .focus,
              overtimeSeconds >= 120,
              !showCoachReasonSheet else { return }
        showCoachReasonSheet = true
        pendingReasonKind = .breakOverrun
    }

    /// Records the pause extension reason and dismisses the inline chips.
    func recordPauseReason(_ reason: FocusCoachReason?) {
        coachEngine.recordAnomaly(kind: .drift, reason: reason, sessionId: currentSession?.id)
        showPauseReasonChips = false
    }

    /// Dismisses pause reason chips without recording (auto-timeout or user swipe).
    func dismissPauseReasonChips() {
        showPauseReasonChips = false
    }

    // MARK: - Focus Coach Actions

    /// Records an anomaly reason (user-selected chip) via the coach engine.
    func recordCoachReason(kind: FocusCoachInterruptionKind, reason: FocusCoachReason?) {
        coachEngine.recordAnomaly(kind: kind, reason: reason, sessionId: currentSession?.id)
    }

    /// Handles a coach quick action selection.
    func handleCoachAction(_ action: FocusCoachQuickAction, skipReason: FocusCoachSkipReason? = nil) {
        applyGuardianRelease(reason: skipReason, action: action)
        switch action {
        case .returnNow:
            coachEngine.recordInterventionOutcome(.improved)
            if state == .paused { resume() }
            currentCoachQuickPromptDecision = nil
            currentIdleStarterDecision = nil
            closePopover()
        case .cleanRestart5m:
            coachEngine.recordInterventionOutcome(.improved)
            currentCoachQuickPromptDecision = nil
            currentIdleStarterDecision = nil
            abandonSession()
            selectedMinutes = 5
            startFocus()
        case .snooze10m:
            coachEngine.snooze(minutes: settings?.coachDefaultSnoozeMinutes ?? 10, skipReason: skipReason)
            currentCoachQuickPromptDecision = nil
            currentIdleStarterDecision = nil
        case .startFocusNow:
            coachEngine.recordInterventionOutcome(.improved)
            currentCoachQuickPromptDecision = nil
            currentIdleStarterDecision = nil
            if let recommended = idleStarterRecommendedMinutes {
                selectedMinutes = recommended
            }
            startFocus()
        case .blockForProject:
            coachEngine.recordInterventionOutcome(.improved)
            applyProjectBlockRecommendation()
            currentCoachQuickPromptDecision = nil
            currentIdleStarterDecision = nil
        case .skipCheck:
            coachEngine.snooze(minutes: settings?.coachDefaultSnoozeMinutes ?? 10, skipReason: skipReason)
            currentCoachQuickPromptDecision = nil
            currentIdleStarterDecision = nil
        }
        // NOTE: Do NOT call dismissCoachInterventionWindow() here.
        // The view's dismiss() is the single owner of window lifecycle.
    }

    /// Dismisses the current coach prompt.
    func dismissCoachPrompt() {
        coachEngine.recordInterventionOutcome(.dismissed)
        currentCoachQuickPromptDecision = nil
        currentIdleStarterDecision = nil
    }

    func dismissCoachInterventionWindow() {
        showCoachInterventionWindow = false
        activeCoachInterventionDecision = nil
        if let prompt = currentCoachQuickPromptDecision, prompt.kind == .quickPrompt {
            currentCoachQuickPromptDecision = nil
        }
    }

    private func appendBlockActionIfRecommended(
        actions: [FocusCoachQuickAction],
        context: FocusCoachContext
    ) -> [FocusCoachQuickAction] {
        guard context.hasBlockRecommendation else { return actions }
        if actions.contains(.blockForProject) { return actions }
        return actions + [.blockForProject]
    }

    private func contextualMessage(base: String?, context: FocusCoachContext) -> String {
        if context.inReleaseWindow {
            return "You marked yourself off-duty. Guardian checks are paused until the release window ends."
        }
        if let reason = context.blockRecommendationReason, !reason.isEmpty {
            return reason
        }
        if let app = context.frontmostAppName, context.frontmostAppCategory == .distracting {
            return "\(app) looks off-plan for your current focus intent. Planned or drift?"
        }
        if let base, !base.isEmpty {
            return base
        }
        if let project = context.selectedProjectName, !project.isEmpty {
            return "Protect \(project) now with a short focused block."
        }
        return "Current context looks off-plan. Choose the next best action."
    }

    private func applyGuardianRelease(reason: FocusCoachSkipReason?, action: FocusCoachQuickAction) {
        guard action == .snooze10m || action == .skipCheck else { return }
        guard let duration = guardianAdvisor.releaseDuration(for: reason) else { return }
        guardianReleaseUntil = Date().addingTimeInterval(duration)
    }

    private func applyProjectBlockRecommendation() {
        guard let target = activeCoachInterventionDecision?.context?.suggestedBlockTarget
            ?? currentCoachQuickPromptDecision?.context?.suggestedBlockTarget
            ?? currentIdleStarterDecision?.context?.suggestedBlockTarget else { return }
        guard let project = selectedProject else { return }
        if project.blockProfile == nil {
            let profile = BlockProfile(name: "\(project.name) Guard", websites: [target])
            modelContext?.insert(profile)
            project.blockProfile = profile
            saveContext()
            if state == .focusing || state == .paused {
                deactivateBlocking()
                activateBlocking()
            }
            return
        }
        guard let profile = project.blockProfile else { return }
        var websites = profile.blockedWebsites
        if websites.contains(target) { return }
        websites.append(target)
        profile.blockedWebsites = websites
        saveContext()
        if state == .focusing || state == .paused {
            deactivateBlocking()
            activateBlocking()
        }
    }

    private func shouldAutoOpenStrongPromptSurface() -> Bool {
        settings?.coachAutoOpenPopoverOnStrongPrompt ?? true
    }

    private func shouldBringAppToFrontForStrongPrompt() -> Bool {
        settings?.coachBringAppToFrontOnStrongPrompt ?? true
    }

    private func routeCoachDecision(_ decision: FocusCoachDecision) {
        guard let settings else { return }
        if isGuardianInReleaseWindow {
            currentCoachQuickPromptDecision = nil
            activeCoachInterventionDecision = nil
            showCoachInterventionWindow = false
            return
        }
        let mode = settings.coachInterventionMode
        let route = coachPlanner.routeActiveDecision(
            decision,
            mode: mode,
            riskScore: coachEngine.riskScore,
            strongShownCount: strongPromptsShownThisSession,
            maxStrongPrompts: settings.coachMaxStrongPromptsPerSession,
            allowSkipAction: settings.coachAllowSkipAction
        )

        if let quick = route.quickPromptDecision {
            let coachCtx = buildCoachContext(
                idleSeconds: 0,
                frontmostCategory: AppUsageTracker.shared.currentFrontmostCategory,
                frontmostAppName: AppUsageTracker.shared.currentFrontmostAppName
            )
            let quickActions = appendBlockActionIfRecommended(
                actions: quick.suggestedActions,
                context: coachCtx
            )
            currentCoachQuickPromptDecision = FocusCoachDecision(
                kind: quick.kind,
                suggestedActions: quickActions,
                message: contextualMessage(base: quick.message, context: coachCtx),
                context: coachCtx
            )
        } else {
            currentCoachQuickPromptDecision = nil
        }

        if let strongDecision = route.strongWindowDecision {
            // Build personalisation context for in-session drift
            let rawCategory = AppUsageTracker.shared.currentFrontmostCategory
            let entryCategory: AppUsageEntry.AppCategory
            switch rawCategory {
            case .productive:  entryCategory = .productive
            case .neutral:     entryCategory = .neutral
            case .distracting: entryCategory = .distracting
            }
            let coachCtx = buildCoachContext(
                idleSeconds: 0,
                frontmostCategory: entryCategory,
                frontmostAppName: AppUsageTracker.shared.currentFrontmostAppName
            )
            let contextualDecision = FocusCoachDecision(
                kind: strongDecision.kind,
                suggestedActions: appendBlockActionIfRecommended(
                    actions: strongDecision.suggestedActions,
                    context: coachCtx
                ),
                message: contextualMessage(base: strongDecision.message, context: coachCtx),
                context: coachCtx
            )
            let shouldAutoOpen = shouldAutoOpenStrongPromptSurface()
            if shouldAutoOpen {
                activeCoachInterventionDecision = contextualDecision
                showCoachInterventionWindow = true
                // Single-surface orchestration: strong prompt window suppresses popover prompt.
                currentCoachQuickPromptDecision = nil
            } else {
                // Keep intervention inside popover when auto-open is disabled.
                activeCoachInterventionDecision = nil
                showCoachInterventionWindow = false
                currentCoachQuickPromptDecision = contextualDecision
            }
            coachEngine.recordDeliveredIntervention(kind: .strongPrompt, riskScore: coachEngine.riskScore)
            if route.didConsumeStrongBudget {
                strongPromptsShownThisSession += 1
            }
            if shouldAutoOpen {
                closePopover()
                DispatchQueue.main.async { [weak self] in
                    self?.openCoachInterventionWindow?()
                    if self?.shouldBringAppToFrontForStrongPrompt() == true {
                        self?.requestAppActivation?()
                    }
                }
            }
        } else if route.quickPromptDecision != nil {
            coachEngine.recordDeliveredIntervention(kind: .quickPrompt, riskScore: coachEngine.riskScore)
        }
    }

    func evaluateIdleStarterIntervention(
        idleSeconds: Int,
        escalationLevel: Int,
        frontmostCategory: AppUsageEntry.AppCategory
    ) {
        guard state == .idle, !isOvertime, let settings else { return }
        if isGuardianInReleaseWindow {
            currentIdleStarterDecision = nil
            return
        }
        guard settings.antiProcrastinationEnabled, settings.coachIdleStarterEnabled else {
            currentIdleStarterDecision = nil
            return
        }

        let now = Date()
        let hour = Calendar.current.component(.hour, from: now)
        let opportunityContext = coachOpportunityModel.idleStarterContext(
            idleSeconds: idleSeconds,
            escalationLevel: escalationLevel,
            frontmostCategory: frontmostCategory,
            hourOfDay: hour,
            minutesUntilNextCalendarEvent: nil,
            defaultMinutes: max(5, selectedMinutes)
        )
        let route = coachPlanner.routeIdleStarter(
            driftConfidence: opportunityContext.driftConfidence,
            focusOpportunity: opportunityContext.focusOpportunity,
            mode: settings.coachInterventionMode,
            allowSkipAction: settings.coachAllowSkipAction
        )

        if route.shouldPresent, var decision = route.decision {
            if let last = lastIdleInterventionAt, Date().timeIntervalSince(last) < 120 {
                return
            }
            idleStarterSummary = opportunityContext.summary
            idleStarterRecommendedMinutes = opportunityContext.recommendedDurationMinutes

            // Build personalisation context snapshot
            let coachCtx = buildCoachContext(
                idleSeconds: idleSeconds,
                frontmostCategory: frontmostCategory,
                frontmostAppName: AppUsageTracker.shared.currentFrontmostAppName
            )

            if decision.suggestedActions.contains(.startFocusNow) {
                decision = FocusCoachDecision(
                    kind: decision.kind,
                    suggestedActions: decision.suggestedActions,
                    message: "\(opportunityContext.summary)",
                    context: coachCtx
                )
            }
            decision = FocusCoachDecision(
                kind: decision.kind,
                suggestedActions: appendBlockActionIfRecommended(
                    actions: decision.suggestedActions,
                    context: coachCtx
                ),
                message: contextualMessage(base: decision.message, context: coachCtx),
                context: coachCtx
            )
            let shouldEscalateToWindow = escalationLevel >= 1 || settings.coachInterventionMode == .sessionRescue
            if shouldEscalateToWindow {
                let strongDecision = FocusCoachDecision(
                    kind: .strongPrompt,
                    suggestedActions: decision.suggestedActions,
                    message: contextualMessage(base: decision.message, context: coachCtx),
                    context: coachCtx
                )
                let shouldAutoOpen = shouldAutoOpenStrongPromptSurface()
                if shouldAutoOpen {
                    activeCoachInterventionDecision = strongDecision
                    showCoachInterventionWindow = true
                    // Single-surface orchestration: strong prompt window suppresses popover prompt.
                    currentIdleStarterDecision = nil
                } else {
                    activeCoachInterventionDecision = nil
                    showCoachInterventionWindow = false
                    currentIdleStarterDecision = strongDecision
                }
                coachEngine.recordDeliveredIntervention(
                    kind: .strongPrompt,
                    riskScore: opportunityContext.driftConfidence,
                    sessionId: nil
                )
                if shouldAutoOpen {
                    closePopover()
                    DispatchQueue.main.async { [weak self] in
                        self?.openCoachInterventionWindow?()
                        if self?.shouldBringAppToFrontForStrongPrompt() == true {
                            self?.requestAppActivation?()
                        }
                    }
                }
            } else {
                currentIdleStarterDecision = decision
            }
            lastIdleInterventionAt = Date()
        } else {
            currentIdleStarterDecision = nil
        }
    }

    // MARK: - Coach Context Builder

    /// Builds a personalised `FocusCoachContext` snapshot from current state.
    /// Called whenever an intervention decision is routed to the window.
    private func buildCoachContext(
        idleSeconds: Int,
        frontmostCategory: AppUsageEntry.AppCategory,
        frontmostAppName: String?
    ) -> FocusCoachContext {
        let hour = Calendar.current.component(.hour, from: Date())

        let appCategory: AppUsageCategory
        switch frontmostCategory {
        case .productive:   appCategory = .productive
        case .neutral:      appCategory = .neutral
        case .distracting:  appCategory = .distracting
        }

        // Query today's top distracting app from SwiftData
        var topDistractingName: String? = nil
        var topDistractingMinutes: Int = 0
        var entriesToday: [AppUsageEntry] = []
        if let ctx = modelContext {
            let today = Calendar.current.startOfDay(for: Date())
            let descriptor = FetchDescriptor<AppUsageEntry>(
                predicate: #Predicate { e in e.date >= today }
            )
            do {
                let entries = try ctx.fetch(descriptor)
                entriesToday = entries
                let topDistracting = entries
                    .filter { AppUsageEntry.classify(bundleIdentifier: $0.bundleIdentifier, appName: $0.appName) == .distracting }
                    .max { $0.outsideFocusSeconds < $1.outsideFocusSeconds }
                if let top = topDistracting, top.outsideFocusSeconds > 0 {
                    topDistractingName = top.appName
                    topDistractingMinutes = top.outsideFocusSeconds / 60
                }
            } catch {
                log("buildCoachContext: SwiftData fetch failed: \(error)")
            }
        }

        let recommendation = guardianAdvisor.recommendation(
            frontmostBundleId: AppUsageTracker.shared.currentFrontmostBundleId,
            frontmostAppName: frontmostAppName,
            entries: entriesToday,
            selectedProject: selectedProject
        )

        let isInActiveSession: Bool
        switch state {
        case .focusing, .paused, .onBreak:
            isInActiveSession = true
        case .idle:
            isInActiveSession = false
        }

        return FocusCoachContext(
            idleSeconds: idleSeconds,
            frontmostAppName: frontmostAppName,
            frontmostBundleIdentifier: AppUsageTracker.shared.currentFrontmostBundleId,
            frontmostAppCategory: appCategory,
            isInActiveSession: isInActiveSession,
            todayFocusSeconds: todayFocusTime,
            dailyGoalSeconds: settings?.dailyFocusGoal ?? 7200,
            todaySessionCount: todaySessionCount,
            selectedProjectName: selectedProject?.name,
            hourOfDay: hour,
            topDistractingAppName: topDistractingName,
            topDistractingAppMinutes: topDistractingMinutes,
            recentLowPriorityWorkCount: coachEngine.recentLowPrioritySkipCount(),
            suggestedBlockTarget: recommendation?.target,
            blockRecommendationReason: recommendation?.reason,
            inReleaseWindow: isGuardianInReleaseWindow
        )
    }
}
