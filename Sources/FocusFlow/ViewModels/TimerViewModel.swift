import Foundation
import SwiftUI
import SwiftData


enum TimerState: Equatable {
    case idle
    case focusing
    case paused
    case onBreak(SessionType)
}

enum IdleStarterSuppressionReason: Equatable {
    case releaseWindowActive
    case screenShareSuppressed
    case antiProcrastinationDisabled
    case idleStarterDisabled
    case cooldownActive
    case snoozed
    case quietHours
    case outsideFocusWindow
    case onTrack
    case banditChoseSilent
    case calendarBusy
    case dailyPromptCapReached
    case strongPromptSpacing

    var debugLabel: String {
        switch self {
        case .releaseWindowActive: return "Release window active (Done for today)"
        case .screenShareSuppressed: return "Suppressed by screen-share guard"
        case .antiProcrastinationDisabled: return "Anti-procrastination disabled"
        case .idleStarterDisabled: return "Idle starter disabled"
        case .cooldownActive: return "Cooldown active (<120s since last prompt)"
        case .snoozed: return "Snoozed (Not now / Planned)"
        case .quietHours: return "Quiet hours"
        case .outsideFocusWindow: return "Outside your learned focus windows"
        case .onTrack: return "On track for today's goal"
        case .banditChoseSilent: return "Coach chose to stay silent"
        case .calendarBusy: return "Calendar shows a busy event now"
        case .dailyPromptCapReached: return "Daily prompt cap reached"
        case .strongPromptSpacing: return "Panel shown less than 2h ago"
        }
    }

    init?(verdict: CoachGuardrails.Verdict) {
        switch verdict {
        case .allowed, .sessionActive: return nil
        case .released: self = .releaseWindowActive
        case .screenShare: self = .screenShareSuppressed
        case .calendarBusy: self = .calendarBusy
        case .quietHours: self = .quietHours
        case .snoozed: self = .snoozed
        case .dailyCapReached: self = .dailyPromptCapReached
        case .panelTooSoon: self = .strongPromptSpacing
        }
    }
}

#if DEBUG
extension TimerViewModel {
    /// Test hook: back-dates the day the view model believes it is on, to simulate a rollover.
    func testingSetCurrentDay(_ day: Date) {
        currentDay = Calendar.current.startOfDay(for: day)
    }

    /// Test hook: lets the next idle evaluation run without the 120 s re-prompt cooldown.
    func testingResetIdleCooldown() {
        lastIdleInterventionAt = nil
    }

    /// Test hook: runs the timer-completion path for the current block now.
    func testingCompleteCurrentBlock() async {
        await timerCompleted()
    }

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
        isEvidenceMode = true
        isConfigured = true
        coachEngine.configureStore(SwiftDataCoachStore(modelContext: modelContext))
        loadWakeRecoveryStateFromDefaults()
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
    /// `duration: nil` → use the configured short/long break duration; non-nil → override with that many seconds (e.g. 300 for a 5 m reset).
    case takeBreak(duration: TimeInterval?)
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
    /// True only for deterministic UI evidence rendering paths.
    var isEvidenceMode: Bool = false

    // MARK: - Custom Duration
    var selectedMinutes: Int = 25

    var focusDuration: TimeInterval {
        TimeInterval(max(5, selectedMinutes) * 60)
    }

    // MARK: - Pause Tracking
    var pauseStartTime: Date? = nil
    var pauseElapsed: TimeInterval = 0
    private var pauseTimer: Timer? = nil

    /// Tracks when the system entered sleep (for auto-resume threshold check)
    var systemSleepStartTime: Date?
    /// Tracks what state we were in before sleep (to know whether to resume focus or break)
    private var stateBeforeSleep: TimerState?

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

    // MARK: - Guardian Session Spine
    /// Durable earned-block record. Outlives lastCompletedSession across break/defer cycles.
    /// Cleared ONLY on: newer focus block completes, day-close summary dismissed, day rollover.
    private(set) var completedBlockContext: CompletedBlockContext? = nil
    /// Tracks the current or most-recent break episode, linked to the earned block.
    private(set) var breakEpisodeContext: BreakEpisodeContext? = nil
    var suggestedEarnedBreakMinutes: Int = 5
    var suggestedEarnedBreakSeconds: TimeInterval { TimeInterval(suggestedEarnedBreakMinutes * 60) }
    /// Active suppression window when user has explicitly opted out of guardian prompts.
    ///
    /// Lifecycle semantics (intentional and non-ambiguous):
    /// - Entered only via explicit release actions (e.g. mark-off-duty, done-for-now).
    /// - Cleared when the user recommits by starting a new focus session.
    /// - `markOffDuty` additionally clears any pending guardian prompt/window UI.
    private(set) var suppressionWindow: InterventionSuppressionWindow? = nil

    // MARK: - Overtime
    var isOvertime: Bool = false
    var overtimeSeconds: Int = 0

    // MARK: - Wake Recovery (Issue #32)
    var showWakeRecoveryPrompt: Bool = false
    var wakeRecoverySleepStartTime: Date? = nil
    var wakeRecoveryWakeTime: Date? = nil
    var wakeRecoverySession: FocusSession? = nil
    var wakeRecoveryWasOvertime: Bool = false

    var isWakeRecoveryActive: Bool {
        showWakeRecoveryPrompt && wakeRecoverySession != nil
    }

    /// True when the completed session was a focus session (not a break).
    var isFocusOvertime: Bool { isOvertime && lastCompletedSession?.type == .focus }
    /// True when the completed session was a break (break ran past its duration).
    var isBreakOvertime: Bool { isOvertime && lastCompletedSession?.type != .focus }

    /// True when the user has paused a running break (countdown frozen).
    var isBreakPaused: Bool = false

    // MARK: - Today Stats
    var todayFocusTime: TimeInterval = 0
    var todaySessionCount: Int = 0

    // MARK: - Day Boundary
    private var currentDay: Date = Calendar.current.startOfDay(for: Date())
    private var midnightTimer: Timer?

    // MARK: - Window Lifecycle
    /// Set by FocusFlowApp to open the session-complete window from any context
    var openCompletionWindow: (() -> Void)? {
        didSet {
            if openCompletionWindow != nil && showWakeRecoveryPrompt && wakeRecoverySession != nil {
                log("openCompletionWindow did set and wake recovery is active — triggering window open")
                DispatchQueue.main.async { [weak self] in
                    self?.openCompletionWindow?()
                    self?.requestAppActivation?()
                }
            }
        }
    }
    /// Set by FocusFlowApp to request foreground activation based on policy.
    var requestAppActivation: (() -> Void)?

    /// Direct reference to the MenuBarExtra's hosting window.
    /// Set by PopoverWindowAccessor embedded in MenuBarPopoverView.
    /// Using a direct reference avoids the fragile responder-chain
    /// `NSApp.sendAction(NSPopover.performClose)` that silently fails
    /// when another window is key.
    weak var popoverWindow: NSWindow?
    /// Test hook for asserting commit-action popover closure without real AppKit window lifecycle.
    var onPopoverCloseRequested: (() -> Void)?

    /// Reliably closes the menu bar popover using direct window reference.
    func closePopover() {
        onPopoverCloseRequested?()
        popoverWindow?.close()
    }

    // MARK: - Private
    var timer: Timer?
    private var modelContext: ModelContext?
    private var currentSession: FocusSession?
    private(set) var settings: AppSettings?

    // MARK: - Focus Coach
    private(set) var coachEngine = FocusCoachEngine()
    private(set) var driftMemoryStore = DriftMemoryStore()
    private let coachPlanner = FocusCoachInterventionPlanner()
    private let guardianAdvisor = FocusCoachGuardianAdvisor()
    private let earnedBreakSuggestionEngine = EarnedBreakSuggestionEngine()
    private let screenShareGuard: ScreenShareGuard
    private var choseSuggestedBreakCurrentEpisode: Bool = false
    private var coachTickCounter: Int = 0
    private var pauseCountThisSession: Int = 0
    private var strongPromptsShownThisSession: Int = 0
    private var lastIdleInterventionAt: Date?
    /// Debug read-outs for Settings → Coach: window strength (p / best p today) and pacing pressure.
    private(set) var latestWorkIntentScore: Double = 0
    private(set) var latestDriftScore: Double = 0
    private(set) var latestWorkIntentActiveSignals: [String] = []
    private(set) var latestDriftActiveSignals: [String] = []
    private(set) var lastIdleStarterSuppressionReason: IdleStarterSuppressionReason?
    /// Overrides the calendar lookup for the idle path (tests). Nil uses `CalendarService`.
    var calendarAvailabilityProvider: ((Date) -> CalendarAvailability)?
    /// Decision behind the last coach check-in notification, shown if the user taps its body.
    private(set) var pendingCoachNotificationDecision: FocusCoachDecision?
    private var pendingCoachNotificationPlan: CoachStartTarget?

    // MARK: - Coach v2 (learning coach + on-screen panel)
    /// Content of the floating coach panel; nil when hidden. The panel view reads this.
    private(set) var coachPanel: CoachPanelPresentation?
    /// Shown in the panel when its primary action could not start a block (bug B5).
    private(set) var coachPanelError: String?
    /// The menu bar icon pulses while an unanswered prompt waits (panel auto-hid or badge arm).
    var coachMenuBarPulse: Bool = false
    /// AppKit host for the panel, set by FocusFlowApp. Nil in tests: state still updates.
    var coachPanelHost: (any CoachPanelHosting)?
    /// Opens the Settings scene (weekly priorities invite). Set by FocusFlowApp.
    var openSettingsScene: (() -> Void)?
    /// This week's 1–3 personal priorities (refreshed on launch, popover open and each prompt).
    private(set) var weeklyPriorities: [WeeklyPriority] = []
    /// Intent typed in the popover: "What will exist at the end of this block?"
    var pendingIntentText: String = ""
    /// Weekly priority the next block serves.
    var pendingPriorityID: UUID?
    private var lastPrefilledIntent: String?
    /// "Not now", "Planned, leave me" and "Done for today" keep idle prompts away until then.
    private(set) var coachQuietUntil: Date?
    /// The bandit prompt waiting for a session start (rewarded by id within 10 minutes).
    private(set) var pendingCoachAttemptID: UUID?
    private var coachPanelAutoHideTask: Task<Void, Never>?
    private var coachIdleTimer: Timer?
    private var pseudoContextRunStart: Date?
    private var pseudoLastAskedAt: Date?
    private(set) var availabilityModel: CoachAvailabilityModel = .empty
    private var availabilityComputedDay: Date?
    /// Test hook: fixes the availability model instead of learning it from the store.
    var availabilityModelOverride: CoachAvailabilityModel?
    private(set) var banditModel = CoachBanditModel()
    private let banditStore: CoachBanditStore
    private let coachGuardrails = CoachGuardrails()
    private let banditPolicy = CoachBanditPolicy()
    /// Test hook: forces the bandit's arm when the guardrails allow its surface.
    var coachArmOverride: CoachArm?
    var coachRandom = SplitMix64(seed: UInt64(Date().timeIntervalSince1970 * 1000))
    static let coachPanelAutoHideSeconds: Double = 20
    static let weeklyInviteDefaultsKey = "focusflow.coachWeeklyPrioritiesInviteWeek"
    private let defaults: UserDefaults

    // MARK: - Coach rescue loop (docs/plans/2026-10-17-coach-rescue-loop-design.md)
    /// Rolling drift detector, fed every tracking tick while no session runs.
    private(set) var driftMonitor = DriftMonitor()
    /// Latest drift assessment (refreshed every 15 s). Drives the menu bar counter.
    private(set) var currentDrift: DriftAssessment?
    private(set) var currentFocusWindow: CoachFocusWindow?
    private var lastRescueDecision: CoachRescueCadence.Decision?
    private var driftRuleKeys: (confirmed: Set<String>, allowed: Set<String>, loadedAt: Date)?
    /// Contexts the user called a side quest at least half the time (≥ 2 answers): their time is pseudo-work.
    private(set) var busyworkContexts: Set<String> = []
    /// The pause screen on screen; nil when hidden.
    private(set) var pauseScreen: CoachPauseScreenPresentation?
    /// AppKit host for the pause screen, set by FocusFlowApp. Nil in tests: state still updates.
    var pauseScreenHost: (any CoachPauseScreenHosting)?
    /// ⌃⌥Space registrar, set by FocusFlowApp. Nil in tests unless a fake is injected.
    var hotkeyRegistrar: (any CoachHotkeyRegistering)?
    /// True while a starter block (no project, no priority) runs.
    private(set) var isStarterBlock = false
    /// "What's the very next step?" typed during a starter block.
    var starterStepText: String = ""
    private var starterRestore: (project: Project?, customLabel: String, priorityID: UUID?)?
    /// Overrides `focusDuration` for the next start (starter blocks may be 2 minutes).
    private var nextStartDurationOverride: TimeInterval?
    /// The block a rescue started; it gets the momentum ramp once.
    private(set) var rescueStartedSessionID: UUID?
    private var momentumOfferedSessionID: UUID?
    private var coachIdleTickCount = 0
    private var pauseScreenShutoffLogged = false
    /// Test hook: seconds since the last keyboard/mouse input. Nil reads the system.
    var systemIdleSecondsProvider: (() -> TimeInterval)?
    /// Test hook: overrides the frontmost context the drift monitor samples.
    var driftFrontmostOverride: DriftFrontmost?
    #if DEBUG
    /// FOCUSFLOW_DEBUG_DRIFT_LEVEL: forces the ladder level of the debug coach panel.
    var debugForcedDriftLevel: DriftLevel?
    #endif

    /// What the drift monitor samples each tick.
    struct DriftFrontmost: Equatable {
        var bundleIdentifier: String?
        var appName: String?
        var browserHost: String?
        var displayName: String?
        var category: AppUsageEntry.AppCategory
        var switchesPerMinute: Double = 0
    }

    // MARK: - Work Intent Timestamps
    /// Time the app was launched.
    var appLaunchTime: Date = Date()
    /// Set when the user selects or changes a project in the picker.
    var lastProjectSelectedAt: Date?
    /// Set when the user is shown an idle-starter prompt but dismisses without starting.
    var lastAbandonedStartAt: Date?

    /// Whether the reason chip sheet should be shown (driven by coach engine anomaly detection)
    var showCoachReasonSheet: Bool = false
    var pendingReasonKind: FocusCoachInterruptionKind = .drift
    /// Distracting apps/domains detected during the last completed focus session (for post-session review).
    var lastSessionDistractingEntries: [AppUsageTracker.SessionDistractingEntry] = []
    /// Prevents break-overrun reason prompts from reopening repeatedly in the same break episode.
    private var hasPromptedBreakOverrunReasonInCurrentEpisode: Bool = false
    /// Non-blocking inline reason chips shown when resuming from an extended pause (≥2 min).
    var showPauseReasonChips: Bool = false
    /// True while the coach panel is on screen (kept under its v1 name for callers and tests).
    var showCoachInterventionWindow: Bool = false
    /// Set when a panel action succeeds, so a later dismiss does not record `.dismissed`.
    private var interventionActionTaken = false
    /// Decision behind the coach panel.
    var activeCoachInterventionDecision: FocusCoachDecision?
    var currentCoachQuickPromptDecision: FocusCoachDecision?
    var currentIdleStarterDecision: FocusCoachDecision?
    var idleStarterSummary: String?
    var idleStarterRecommendedMinutes: Int?

    var activeCoachPopoverDecision: FocusCoachDecision? {
        currentCoachQuickPromptDecision ?? currentIdleStarterDecision
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

    /// `defaults` backs the coach's persisted state (bandit cache, pseudo-work answer log,
    /// weekly priorities invite). Tests pass an isolated suite; production uses `.standard`.
    init(screenShareGuard: ScreenShareGuard = ScreenShareGuard(), defaults: UserDefaults = .standard) {
        self.screenShareGuard = screenShareGuard
        self.defaults = defaults
        self.banditStore = CoachBanditStore(defaults: defaults)
    }

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
        loadWakeRecoveryStateFromDefaults()
        purgeShortFocusSessions()
        IdleDistractionLegacyCleanup.runOnce(in: modelContext)
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
        NotificationCenter.default.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.checkDayRolloverIfNeeded() }
        }
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
        // Actionable coach notifications: Start / Snooze buttons and body taps route back here.
        NotificationService.shared.onCoachNotificationResponse = { [weak self] response in
            self?.handleCoachNotificationResponse(response)
        }
        NotificationService.shared.registerCoachNotificationHandling()
        #if DEBUG
        // Manual check of the actionable check-in: launch with FOCUSFLOW_DEBUG_COACH_CHECKIN=1.
        if ProcessInfo.processInfo.environment["FOCUSFLOW_DEBUG_COACH_CHECKIN"] == "1" {
            log("debug: sending coach check-in notification in 5s")
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(5))
                if let self {
                    let availability = self.currentCalendarAvailability(now: Date())
                    self.log("debug: calendar auth=\(CalendarService.shared.authStatus) busyNow=\(availability.isBusyNow) nextEventMin=\(availability.minutesUntilNextEvent.map(String.init) ?? "nil")")
                }
                NotificationService.shared.sendCoachCheckIn(
                    title: "Focus check-in",
                    body: "Debug check-in. Press Start focus to begin a block.",
                    sound: "Glass"
                )
            }
        }
        #endif
        #if DEBUG
        // Live check of the on-screen coach panel: launch with FOCUSFLOW_DEBUG_COACH_PANEL=1.
        if ProcessInfo.processInfo.environment["FOCUSFLOW_DEBUG_COACH_PANEL"] == "1" {
            log("debug: showing coach panel in 5s")
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(5))
                self?.presentDebugCoachPanel()
            }
        }
        #endif
        #if DEBUG
        // Rescue loop checks: FOCUSFLOW_DEBUG_PAUSE_SCREEN=1 shows the pause screen in 5 s;
        // FOCUSFLOW_DEBUG_DRIFT_LEVEL=<1|2|3> sets the ladder level of FOCUSFLOW_DEBUG_COACH_PANEL.
        if let raw = ProcessInfo.processInfo.environment["FOCUSFLOW_DEBUG_DRIFT_LEVEL"], let value = Int(raw),
           let level = DriftLevel(rawValue: value), level > .ok {
            debugForcedDriftLevel = level
        }
        // Coach v3: FOCUSFLOW_DEBUG_PLAN=card shows the plan card, =cue a planned-start cue, in 5 s
        // (nothing is saved). With FOCUSFLOW_DEBUG_CAPTURE_DIR the panel is also snapshotted.
        if let mode = ProcessInfo.processInfo.environment["FOCUSFLOW_DEBUG_PLAN"], mode == "card" || mode == "cue" {
            log("debug: showing plan \(mode) in 5s")
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(5))
                self?.presentDebugPlanPanel(cue: mode == "cue")
                if let dir = ProcessInfo.processInfo.environment["FOCUSFLOW_DEBUG_CAPTURE_DIR"], !dir.isEmpty {
                    try? await Task.sleep(for: .seconds(4))
                    DebugWindowCapture.snapshotCoachPanel(directory: dir, name: "panel_plan_\(mode).png")
                }
            }
        }
        if ProcessInfo.processInfo.environment["FOCUSFLOW_DEBUG_PAUSE_SCREEN"] == "1" {
            log("debug: showing pause screen in 5s")
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(5))
                self?.presentDebugPauseScreen()
            }
        }
        #endif
        // Coach v2: learned windows, bandit posteriors (rebuilt from logged rewards), priorities.
        driftMemoryStore.pruneOldEntries()
        refreshCoachModelsIfNeeded(now: Date(), force: true)
        reloadWeeklyPriorities()
        startCoachIdleTimer()
        syncGlobalHotkey()
        // Wire drift classification memory and latest observation updates
        coachEngine.configureDriftMemory(driftMemoryStore)
        AppUsageTracker.shared.onSuspiciousObservation = { [weak self] observation in
            self?.coachEngine.handleNewObservation(observation)
        }
        // Escalate guardian state when an avoidant observation has no project-scoped allowance
        coachEngine.onAvoidantObservationWithoutAllowance = { [weak self] _ in
            guard let self else { return }
            self.coachEngine.shouldShowReasonSheet = true
            self.coachEngine.pendingAnomalyKind = .drift
        }
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
            MainActor.assumeIsolated {
                self?.handleDayChange()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        midnightTimer = t
    }

    @MainActor
    func checkDayRolloverIfNeeded() {
        let today = Calendar.current.startOfDay(for: Date())
        if today != currentDay {
            log("Day rollover detected (\(currentDay) -> \(today)) — resetting today's stats")
            handleDayChange()
        }
    }

    @MainActor
    func handleDayChange() {
        currentDay = Calendar.current.startOfDay(for: Date())
        completedFocusSessions = 0
        todayFocusTime = 0
        todaySessionCount = 0
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
            AppUsageTracker.shared.syncCadence(isFocusing: false)
            pauseStartTime = Date()
            pauseElapsed = 0
            startPauseTimer()
        } else {
            state = .focusing
            AppUsageTracker.shared.syncCadence(isFocusing: true)
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
            // Completed starter blocks (2–10 min) are real wins and stay in history.
            if session.completed && CoachStarterBlock.isStarter(customLabel: session.customLabel, hasProject: session.project != nil) { continue }
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
        if startOfDay != currentDay {
            currentDay = startOfDay
            completedFocusSessions = 0
            todayFocusTime = 0
            todaySessionCount = 0
            scheduleMidnightRefresh()
        }

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
            // Use the effective end (startedAt + actualDuration) so paused time is excluded
            let sessionEnd = session.effectiveEnd
            return sessionEnd > startOfDay && session.startedAt < tomorrow
        }
        let newCount = focusSessions.filter(\.completed).count
        let newFocusTime = focusSessions.reduce(0) { sum, session in
            // actualDuration already excludes pause time; clamp to today's window
            let effectiveEnd = session.effectiveEnd
            let overlapStart = max(session.startedAt, startOfDay)
            let overlapEnd = min(effectiveEnd, tomorrow)
            return sum + max(0, overlapEnd.timeIntervalSince(overlapStart))
        }
        // Only update @Observable properties if values actually changed (avoids unnecessary re-renders)
        if todaySessionCount != newCount { todaySessionCount = newCount }
        // Reconcile with DB: if state is idle or drift > 60s, align todayFocusTime with DB calculation
        if state == .idle || abs(todayFocusTime - newFocusTime) > 60 { todayFocusTime = newFocusTime }
        if completedFocusSessions != newCount { completedFocusSessions = newCount }
    }

    // MARK: - Actions
    /// Starts a focus block. Returns false and sets `startError` when the start is refused,
    /// so callers can keep their surface open and show why (bug B5).
    @discardableResult
    func startFocus() -> Bool {
        startError = nil
        guard settings != nil, !isOvertime else {
            log("startFocus: settings nil or overtime, aborting")
            startError = settings == nil ? "Settings not loaded. Please restart the app." : "Complete the current session first."
            return false
        }
        guard state == .idle else {
            log("startFocus: not idle (state=\(state)), aborting")
            startError = "A session is already in progress."
            return false
        }
        startFocusInternal()
        return true
    }

    /// Core focus-starting logic, callable from any valid pre-focus state.
    /// Callers must validate preconditions (state, duration, settings) before invoking.
    private func startFocusInternal() {
        let duration = nextStartDurationOverride ?? focusDuration
        nextStartDurationOverride = nil
        log("startFocus: duration=\(duration), project=\(selectedProject?.name ?? "none")")
        totalSeconds = duration
        remainingSeconds = duration
        state = .focusing
        AppUsageTracker.shared.syncCadence(isFocusing: true)
        AppUsageTracker.shared.resetSessionDistractionTracking()

        let session = FocusSession(
            type: .focus,
            duration: duration,
            project: selectedProject,
            customLabel: customLabel.isEmpty ? nil : customLabel
        )
        // Intent capture (Coach v2 §9 step 2): optional, one line, never blocks the start.
        let intent = pendingIntentText.trimmingCharacters(in: .whitespacesAndNewlines)
        session.intentText = intent.isEmpty ? nil : intent
        session.priorityID = pendingPriorityID
        pendingIntentText = ""
        lastPrefilledIntent = nil
        modelContext?.insert(session)
        currentSession = session
        if let project = selectedProject {
            settings?.lastUsedProjectId = project.id.uuidString
        }
        saveContext() // Persist session immediately — crash safety
        creditCoachPromptForStart(sessionID: session.id)
        markPlannedBlockStarted(sessionID: session.id, at: session.startedAt)
        saveCrashRecoveryCheckpoint() // Write initial recovery state to UserDefaults
        startTimer()
        // Focus Coach: start session tracking
        pauseCountThisSession = 0
        strongPromptsShownThisSession = 0
        lastIdleInterventionAt = nil
        clearCoachPrompts()
        hasPromptedBreakOverrunReasonInCurrentEpisode = false
        idleStarterSummary = nil
        idleStarterRecommendedMinutes = nil
        pseudoContextRunStart = nil
        // Rescue loop: a block ends the drift; the menu bar counter clears.
        driftMonitor.reset()
        currentDrift = nil
        lastRescueDecision = nil
        if pauseScreen != nil {
            pauseScreen = nil
            pauseScreenHost?.hidePauseScreen()
        }
        // Starting a new focus block is an explicit recommit signal.
        // Clear any prior release window so guardian protections resume immediately.
        suppressionWindow = nil
        coachQuietUntil = nil
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

        // Commit any in-flight pause time to the OLD session before it's finalized.
        // This must happen before currentSession is reassigned below.
        if wasState == .paused, let oldSession = currentSession {
            let inFlightPause = pauseStartTime.map { Date().timeIntervalSince($0) } ?? pauseElapsed
            oldSession.totalPausedSeconds += max(0, inFlightPause)
            oldSession.pauseCount = pauseCountThisSession
        }

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
        AppUsageTracker.shared.syncCadence(isFocusing: true)

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
            // Pause time already committed to old session above; just clear the counter
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

    // MARK: - Wake Recovery Resolver (Issue #32)
    enum WakeRecoveryChoice {
        case saveToSleepStart
        case keepOvertime
        case discard
    }

    func resolveWakeRecovery(choice: WakeRecoveryChoice) {
        guard isWakeRecoveryActive, let session = wakeRecoverySession else { return }
        
        switch choice {
        case .saveToSleepStart:
            let sleepStart = wakeRecoverySleepStartTime ?? Date()
            session.endedAt = sleepStart
            
            if !wakeRecoveryWasOvertime {
                let elapsed = sleepStart.timeIntervalSince(session.startedAt)
                session.completed = elapsed >= session.duration
            } else {
                session.completed = true
            }
            saveContext()

            // Set up contexts so normal reflection displays correct session stats
            lastCompletedDuration = session.duration
            lastCompletedLabel = session.label
            lastCompletedSession = session
            lastCompletedFocusSession = session
            lastCompletionWasBreak = (session.type != .focus)
            if session.type == .focus {
                completedBlockContext = CompletedBlockContext(
                    sessionId: session.id,
                    projectName: session.project?.name ?? selectedProject?.name ?? "Focus",
                    projectId: session.project?.id ?? selectedProject?.id,
                    durationMinutes: Int(session.actualDuration / 60),
                    workMode: session.project?.workMode ?? selectedProject?.workMode ?? .deepWork,
                    earnedAt: Date()
                )
                refreshEarnedBreakSuggestion()
            }
            loadTodayStats()
            showWakeRecoveryPrompt = false
            clearWakeRecoveryState()

        case .keepOvertime:
            let wakeTime = wakeRecoveryWakeTime ?? Date()
            let sleepStart = wakeRecoverySleepStartTime ?? session.startedAt
            let sleepDuration = wakeTime.timeIntervalSince(sleepStart)
            session.totalPausedSeconds += max(0, sleepDuration)
            session.endedAt = wakeTime
            session.completed = true
            saveContext()

            lastCompletedDuration = session.duration
            lastCompletedLabel = session.label
            lastCompletedSession = session
            lastCompletedFocusSession = session
            lastCompletionWasBreak = (session.type != .focus)
            if session.type == .focus {
                completedBlockContext = CompletedBlockContext(
                    sessionId: session.id,
                    projectName: session.project?.name ?? selectedProject?.name ?? "Focus",
                    projectId: session.project?.id ?? selectedProject?.id,
                    durationMinutes: Int(session.actualDuration / 60),
                    workMode: session.project?.workMode ?? selectedProject?.workMode ?? .deepWork,
                    earnedAt: Date()
                )
                refreshEarnedBreakSuggestion()
            }
            loadTodayStats()
            showWakeRecoveryPrompt = false
            clearWakeRecoveryState()

        case .discard:
            modelContext?.delete(session)
            saveContext()
            
            showWakeRecoveryPrompt = false
            showSessionComplete = false
            clearWakeRecoveryState()
            loadTodayStats()
        }
    }

    func clearWakeRecoveryState() {
        showWakeRecoveryPrompt = false
        wakeRecoverySleepStartTime = nil
        wakeRecoveryWakeTime = nil
        wakeRecoverySession = nil
        wakeRecoveryWasOvertime = false
        clearWakeRecoveryStateDefaults()
    }

    private static let systemSleepStartTimeKey = "FocusFlow.systemSleepStartTime"
    private static let showWakeRecoveryPromptKey = "FocusFlow.showWakeRecoveryPrompt"
    private static let wakeRecoverySleepStartTimeKey = "FocusFlow.wakeRecoverySleepStartTime"
    private static let wakeRecoveryWakeTimeKey = "FocusFlow.wakeRecoveryWakeTime"
    private static let wakeRecoverySessionIdKey = "FocusFlow.wakeRecoverySessionId"
    private static let wakeRecoveryWasOvertimeKey = "FocusFlow.wakeRecoveryWasOvertime"
    private static let systemSleepActiveSessionIdKey = "FocusFlow.systemSleepActiveSessionId"

    func saveWakeRecoveryStateToDefaults() {
        let defaults = UserDefaults.standard
        defaults.set(showWakeRecoveryPrompt, forKey: Self.showWakeRecoveryPromptKey)
        defaults.set(wakeRecoverySleepStartTime, forKey: Self.wakeRecoverySleepStartTimeKey)
        defaults.set(wakeRecoveryWakeTime, forKey: Self.wakeRecoveryWakeTimeKey)
        defaults.set(wakeRecoverySession?.id.uuidString, forKey: Self.wakeRecoverySessionIdKey)
        defaults.set(wakeRecoveryWasOvertime, forKey: Self.wakeRecoveryWasOvertimeKey)
        defaults.set(systemSleepStartTime, forKey: Self.systemSleepStartTimeKey)
        defaults.set(currentSession?.id.uuidString, forKey: Self.systemSleepActiveSessionIdKey)
    }

    private func loadWakeRecoveryStateFromDefaults() {
        let defaults = UserDefaults.standard
        self.showWakeRecoveryPrompt = defaults.bool(forKey: Self.showWakeRecoveryPromptKey)
        self.wakeRecoverySleepStartTime = defaults.object(forKey: Self.wakeRecoverySleepStartTimeKey) as? Date
        self.wakeRecoveryWakeTime = defaults.object(forKey: Self.wakeRecoveryWakeTimeKey) as? Date
        self.wakeRecoveryWasOvertime = defaults.bool(forKey: Self.wakeRecoveryWasOvertimeKey)
        self.systemSleepStartTime = defaults.object(forKey: Self.systemSleepStartTimeKey) as? Date

        if let sessionIdString = defaults.string(forKey: Self.wakeRecoverySessionIdKey),
           let sessionId = UUID(uuidString: sessionIdString) {
            let descriptor = FetchDescriptor<FocusSession>(predicate: #Predicate<FocusSession> { $0.id == sessionId })
            self.wakeRecoverySession = try? modelContext?.fetch(descriptor).first
        }
        
        // If we were in the middle of sleep when the app restarted, restore currentSession
        if let sleepStart = self.systemSleepStartTime, !self.showWakeRecoveryPrompt {
            if let activeSessionIdString = defaults.string(forKey: Self.systemSleepActiveSessionIdKey),
               let activeSessionId = UUID(uuidString: activeSessionIdString) {
                let descriptor = FetchDescriptor<FocusSession>(predicate: #Predicate<FocusSession> { $0.id == activeSessionId })
                if let session = try? modelContext?.fetch(descriptor).first {
                    self.currentSession = session
                    self.state = .paused
                    if let saved = CrashRecoveryState.load() {
                        self.remainingSeconds = saved.remainingSeconds
                        self.totalSeconds = saved.totalSeconds
                    }
                    log("Restored pre-sleep session state for session: \(session.id)")
                    
                    // Check if sleep was already longer than threshold (meaning the system woke up, but we just launched)
                    let sleepDuration = Date().timeIntervalSince(sleepStart)
                    let autoStopThreshold = TimeInterval((settings?.autoStopOnSleepThresholdMinutes ?? 60) * 60)
                    if sleepDuration > autoStopThreshold {
                        log("Startup: long sleep duration detected (\(sleepDuration)s > \(autoStopThreshold)s) - triggering wake recovery immediately")
                        // Clear sleep start time before triggering wake recovery to prevent duplicate runs
                        self.systemSleepStartTime = nil
                        defaults.removeObject(forKey: Self.systemSleepStartTimeKey)
                        defaults.removeObject(forKey: Self.systemSleepActiveSessionIdKey)
                        
                        // Capture wake recovery state
                        self.wakeRecoverySession = session
                        self.wakeRecoverySleepStartTime = sleepStart
                        self.wakeRecoveryWakeTime = Date()
                        self.wakeRecoveryWasOvertime = (self.remainingSeconds <= 0)
                        
                        // Provisionally save the session endedAt to wake time
                        session.endedAt = Date()
                        saveContext()
                        
                        // Reset state machine to idle
                        self.state = .idle
                        self.isOvertime = false
                        self.overtimeSeconds = 0
                        self.remainingSeconds = 0
                        self.totalSeconds = 0
                        self.currentSession = nil
                        clearCrashRecoveryState()
                        
                        self.showWakeRecoveryPrompt = true
                        self.showSessionComplete = true
                        saveWakeRecoveryStateToDefaults()
                    }
                }
            }
        }
        
        if showWakeRecoveryPrompt && wakeRecoverySession != nil {
            log("Loaded unresolved wake recovery session: \(wakeRecoverySession?.id.uuidString ?? "")")
            // Try to trigger window opening if bridge is already wired up
            if openCompletionWindow != nil {
                DispatchQueue.main.async { [weak self] in
                    self?.openCompletionWindow?()
                    self?.requestAppActivation?()
                }
            }
        }
    }

    private func clearWakeRecoveryStateDefaults() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Self.showWakeRecoveryPromptKey)
        defaults.removeObject(forKey: Self.wakeRecoverySleepStartTimeKey)
        defaults.removeObject(forKey: Self.wakeRecoveryWakeTimeKey)
        defaults.removeObject(forKey: Self.wakeRecoverySessionIdKey)
        defaults.removeObject(forKey: Self.wakeRecoveryWasOvertimeKey)
        defaults.removeObject(forKey: Self.systemSleepStartTimeKey)
        defaults.removeObject(forKey: Self.systemSleepActiveSessionIdKey)
    }

    func startBreak(overrideDuration: TimeInterval? = nil) {
        guard let settings, !isOvertime else { return }
        // Guard against zero/negative sessionsBeforeLongBreak to prevent division-by-zero
        let sessionsPerCycle = max(1, settings.sessionsBeforeLongBreak)
        let isLongBreak = overrideDuration == nil
            && completedFocusSessions > 0
            && (completedFocusSessions % sessionsPerCycle) == 0
        let type: SessionType = isLongBreak ? .longBreak : .shortBreak
        let duration = overrideDuration ?? (isLongBreak ? settings.longBreakDuration : settings.shortBreakDuration)

        totalSeconds = duration
        remainingSeconds = duration
        state = .onBreak(type)
        AppUsageTracker.shared.syncCadence(isFocusing: false)
        hasPromptedBreakOverrunReasonInCurrentEpisode = false

        let session = FocusSession(type: type, duration: duration)
        modelContext?.insert(session)
        currentSession = session
        clearCrashRecoveryState() // Focus session ended, break doesn't need recovery

        // Track break episode linked to the earned focus block
        if let ctx = completedBlockContext {
            breakEpisodeContext = BreakEpisodeContext(
                earnedBlock: ctx,
                breakStarted: Date(),
                plannedDurationSeconds: Int(duration)
            )
        }

        startTimer()
        closePopover()
    }

    func pause() {
        guard state == .focusing, !isOvertime else { return }
        timer?.invalidate()
        timer = nil
        state = .paused
        AppUsageTracker.shared.syncCadence(isFocusing: false)
        pauseStartTime = Date()
        pauseElapsed = 0
        pauseCountThisSession += 1
        coachEngine.updatePauseCount(pauseCountThisSession)
        startPauseTimer()
        saveCrashRecoveryCheckpoint() // Persist paused state for crash recovery
    }

    /// Pauses the current session when the system goes to sleep (lid close, idle sleep, etc.)
    /// Handles both focus sessions (via pause()) and break sessions (via pauseBreak()).
    /// Idempotent: safe to call multiple times per sleep event.
    func pauseForSystemSleep() {
        // Guard against duplicate notifications — don't overwrite the original pre-sleep state
        guard systemSleepStartTime == nil else { return }
        
        // Record sleep start time for auto-resume threshold check on wake
        systemSleepStartTime = Date()
        stateBeforeSleep = state
        saveWakeRecoveryStateToDefaults()

        if isOvertime {
            // For overtime, invalidate the timer immediately to freeze ticking
            timer?.invalidate()
            timer = nil
            return
        }

        switch state {
        case .focusing:
            pause()
        case .onBreak:
            guard !isBreakPaused else {
                systemSleepStartTime = nil
                stateBeforeSleep = nil
                return
            }
            pauseBreak()
        case .idle, .paused:
            break
        }
    }

    /// Called when the system wakes from sleep. Auto-resumes if the sleep was within the configured threshold.
    func resumeAfterSystemWake() {
        checkDayRolloverIfNeeded()
        guard let sleepStart = systemSleepStartTime else { return }
        defer {
            systemSleepStartTime = nil
            stateBeforeSleep = nil
            saveWakeRecoveryStateToDefaults()
        }

        let sleepDuration = Date().timeIntervalSince(sleepStart)
        let autoStopThreshold = TimeInterval((settings?.autoStopOnSleepThresholdMinutes ?? 60) * 60)

        if sleepDuration > autoStopThreshold, currentSession != nil {
            log("resumeAfterSystemWake: long sleep detected (\(sleepDuration)s > \(autoStopThreshold)s) - triggering wake recovery")
            
            // Invalidate any active timers
            timer?.invalidate()
            timer = nil
            pauseTimer?.invalidate()
            pauseTimer = nil
            pauseStartTime = nil
            pauseElapsed = 0

            // Capture wake recovery state
            wakeRecoverySession = currentSession
            wakeRecoverySleepStartTime = sleepStart
            wakeRecoveryWakeTime = Date()
            wakeRecoveryWasOvertime = isOvertime

            // Provisionally save the session endedAt to wake time (can be overridden by user)
            if let session = currentSession {
                session.endedAt = Date()
                saveContext()
            }

            // Reset state machine to idle
            state = .idle
            isOvertime = false
            overtimeSeconds = 0
            remainingSeconds = 0
            totalSeconds = 0
            currentSession = nil
            clearCrashRecoveryState()

            // Trigger recovery window
            showWakeRecoveryPrompt = true
            showSessionComplete = true
            closePopover()

            DispatchQueue.main.async { [weak self] in
                self?.openCompletionWindow?()
                self?.requestAppActivation?()
            }
            return
        }

        // Check if auto-resume is enabled
        guard settings?.autoResumeOnWake == true else { return }

        let threshold = TimeInterval(settings?.autoResumeThresholdSeconds ?? 120)

        // Only auto-resume if sleep was within threshold
        guard sleepDuration <= threshold else { return }

        if isOvertime {
            // For overtime, recreate the ticking timer
            startTimer()
            return
        }

        // Resume based on what state we were in before sleep
        switch stateBeforeSleep {
        case .focusing:
            if state == .paused {
                resume()
            }
        case .onBreak:
            if case .onBreak = state, isBreakPaused {
                resumeBreak()
            }
        default:
            break
        }
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
        // Accumulate pause time into the session record before clearing the counter
        let completedPause = pauseStartTime.map { Date().timeIntervalSince($0) } ?? pauseElapsed
        currentSession?.totalPausedSeconds += max(0, completedPause)
        currentSession?.pauseCount = pauseCountThisSession
        pauseTimer?.invalidate()
        pauseTimer = nil
        pauseStartTime = nil
        pauseElapsed = 0
        state = .focusing
        AppUsageTracker.shared.syncCadence(isFocusing: true)
        startTimer()
        saveCrashRecoveryCheckpoint() // Persist resumed state for crash recovery

        if wasPauseExtended && settings?.coachReasonPromptsEnabled == true {
            showPauseReasonChips = true
            pendingReasonKind = .drift
        }

        closePopover()
    }

    func stop() {
        endStarterState()
        timer?.invalidate()
        timer = nil
        pauseTimer?.invalidate()
        pauseTimer = nil
        // If the session was paused when stop() is called, commit the in-flight pause duration
        if state == .paused, let session = currentSession {
            let inFlightPause = pauseStartTime.map { Date().timeIntervalSince($0) } ?? pauseElapsed
            session.totalPausedSeconds += max(0, inFlightPause)
            session.pauseCount = pauseCountThisSession
        }
        pauseStartTime = nil
        pauseElapsed = 0
        isOvertime = false
        overtimeSeconds = 0
        isManualStop = false
        isBreakPaused = false
        showSessionComplete = false
        showCoachReasonSheet = false
        showPauseReasonChips = false
        pendingReasonKind = .drift
        lastSessionDistractingEntries = []
        hasPromptedBreakOverrunReasonInCurrentEpisode = false
        clearCoachPrompts()
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
        AppUsageTracker.shared.syncCadence(isFocusing: false)
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
        // Commit any in-flight pause duration before finalising the session
        if state == .paused {
            let inFlightPause = pauseStartTime.map { Date().timeIntervalSince($0) } ?? pauseElapsed
            session.totalPausedSeconds += max(0, inFlightPause)
            session.pauseCount = pauseCountThisSession
        }
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
        completedBlockContext = CompletedBlockContext(
            sessionId: session.id,
            projectName: session.project?.name ?? selectedProject?.name ?? "Focus",
            projectId: session.project?.id ?? selectedProject?.id,
            durationMinutes: Int(session.actualDuration / 60),
            workMode: selectedProject?.workMode ?? .deepWork,
            earnedAt: Date()
        )
        refreshEarnedBreakSuggestion()
        currentSession = nil

        isManualStop = true
        isOvertime = false
        overtimeSeconds = 0
        state = .idle
        lastSessionDistractingEntries = AppUsageTracker.shared.sessionDistractingEntries
        AppUsageTracker.shared.syncCadence(isFocusing: false)
        remainingSeconds = 0
        totalSeconds = 0
        currentCoachQuickPromptDecision = nil
        hideCoachPanel()

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
        hasPromptedBreakOverrunReasonInCurrentEpisode = false
        currentCoachQuickPromptDecision = nil
        hideCoachPanel()
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
        hasPromptedBreakOverrunReasonInCurrentEpisode = false
        currentCoachQuickPromptDecision = nil
        hideCoachPanel()
        lastCompletedSession = nil
        lastCompletedFocusSession = nil
        lastCompletionWasBreak = false
        lastCompletedDuration = nil
        lastCompletedLabel = nil
        loadTodayStats()
    }

    func abandonSession() {
        endStarterState()
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
        hasPromptedBreakOverrunReasonInCurrentEpisode = false
        clearCoachPrompts()
        idleStarterSummary = nil
        idleStarterRecommendedMinutes = nil
        strongPromptsShownThisSession = 0
        lastIdleInterventionAt = nil
        coachEngine.endSession()
        clearCrashRecoveryState()
        suppressionWindow = nil
        if let session = currentSession {
            modelContext?.delete(session)
            saveContext()
        }
        loadTodayStats()
        deactivateBlocking()
        currentSession = nil
        state = .idle
        AppUsageTracker.shared.syncCadence(isFocusing: false)
        remainingSeconds = 0
        totalSeconds = 0
        closePopover()
    }

    /// Transitions onBreak → focusing without touching .idle.
    /// Preserves completedBlockContext across the break-skip so earned progress is retained.
    func deferBreakAndStartNextBlock() {
        guard case .onBreak = state else { return }
        timer?.invalidate()
        timer = nil
        isOvertime = false
        overtimeSeconds = 0
        showSessionComplete = false
        currentCoachQuickPromptDecision = nil
        hideCoachPanel()
        if currentSession?.type == .shortBreak || currentSession?.type == .longBreak {
            currentSession?.endedAt = Date()
            currentSession?.completed = false
        }
        saveContext()
        clearCrashRecoveryState()
        currentSession = nil
        breakEpisodeContext = nil  // Break episode is discarded on skip; completedBlockContext preserved
        hasPromptedBreakOverrunReasonInCurrentEpisode = false
        remainingSeconds = 0
        totalSeconds = 0
        AppUsageTracker.shared.syncCadence(isFocusing: false)
        loadTodayStats()
        // Transition onBreak → focusing directly; never touch .idle
        startFocusInternal()
    }

    func skipBreak() {
        deferBreakAndStartNextBlock()
    }

    /// Freezes the break countdown without ending the break session.
    func pauseBreak() {
        guard case .onBreak = state else { return }
        timer?.invalidate()
        timer = nil
        isBreakPaused = true
    }

    /// Resumes a paused break countdown from the frozen remaining-seconds value.
    func resumeBreak() {
        guard isBreakPaused, case .onBreak = state else { return }
        isBreakPaused = false
        startTimer()
    }

    // MARK: - Blocking
    var blockUntilGoalMet: Bool = false

    // MARK: - Guardian Release Window

    /// Enters an explicit opt-out suppression window so guardian interventions are paused.
    /// This is only for explicit release actions; it is cleared on next `startFocus()`.
    func enterRelease(reason: ExplicitOptOutReason) {
        suppressionWindow = InterventionSuppressionWindow(
            reason: reason,
            suppressedAt: Date()
        )
    }

    /// Whether an active suppression window is currently in effect.
    var isInReleaseWindow: Bool {
        suppressionWindow?.isActive ?? false
    }

    /// Records the user's self-reported break recovery quality.
    /// If `.doneForNow`, enters a release window. Never clears earned completedBlockContext.
    func classifyBreakRecovery(_ quality: BreakRecoveryQuality) {
        breakEpisodeContext?.recoveryQuality = quality
        if quality == .doneForNow {
            enterRelease(reason: .doneForNow)
        }
    }

    /// Clears completedBlockContext after the day-close summary is archived/dismissed.
    /// This is one of the three permitted clear sites.
    func clearCompletedBlockContextAfterDayClose() {
        completedBlockContext = nil
        breakEpisodeContext = nil
        suppressionWindow = nil
        hasPromptedBreakOverrunReasonInCurrentEpisode = false
    }

    private var breakLearningStore: BreakLearningStore? {
        guard let modelContext else { return nil }
        return BreakLearningStore(modelContext: modelContext)
    }

    private func refreshEarnedBreakSuggestion() {
        let effortSeconds: Int
        if let session = lastCompletedFocusSession {
            effortSeconds = max(0, Int(session.actualDuration))
        } else if let duration = lastCompletedDuration {
            effortSeconds = max(0, Int(duration))
        } else {
            effortSeconds = 0
        }

        let projectId = completedBlockContext?.projectId ?? selectedProject?.id
        let workMode = completedBlockContext?.workMode ?? selectedProject?.workMode ?? .deepWork
        let recent = breakLearningStore?.recentEvents(projectId: projectId, workMode: workMode, limit: 8) ?? []

        var adaptationScore = 0
        for event in recent {
            if event.returnedToFocus { adaptationScore += 1 }
            if event.endedEarly { adaptationScore -= 1 }
            if event.overrunSeconds > 120 { adaptationScore -= 1 }
        }
        let adaptationMinutes = min(3, max(-3, adaptationScore / 2))

        let suggestion = earnedBreakSuggestionEngine.suggest(
            EarnedBreakSuggestionInput(
                effectiveEffortSeconds: effortSeconds,
                overtimeSeconds: overtimeSeconds,
                runCreditSeconds: effortSeconds,
                adaptationMinutes: adaptationMinutes
            )
        )
        suggestedEarnedBreakMinutes = suggestion.suggestedMinutes
    }

    private func recordBreakLearningIfNeeded(returnedToFocus: Bool) {
        guard let store = breakLearningStore else { return }

        let breakSession: FocusSession?
        if let currentSession, currentSession.type != .focus {
            breakSession = currentSession
        } else if let lastCompletedSession, lastCompletedSession.type != .focus {
            breakSession = lastCompletedSession
        } else {
            breakSession = nil
        }
        guard let breakSession else { return }

        let actualSeconds: Int
        if breakSession.endedAt == nil {
            actualSeconds = max(0, Int(Date().timeIntervalSince(breakSession.startedAt)))
        } else {
            actualSeconds = max(0, Int(breakSession.actualDuration))
        }

        let plannedSeconds = breakEpisodeContext?.plannedDurationSeconds ?? max(0, Int(breakSession.duration))
        let overrunSeconds = max(0, actualSeconds - plannedSeconds)
        let endedEarly = actualSeconds < plannedSeconds

        let projectId = breakEpisodeContext?.earnedBlock.projectId ?? completedBlockContext?.projectId
        let workMode = breakEpisodeContext?.earnedBlock.workMode ?? completedBlockContext?.workMode ?? selectedProject?.workMode ?? .deepWork

        store.record(
            projectId: projectId,
            workMode: workMode,
            suggestedMinutes: suggestedEarnedBreakMinutes,
            choseSuggested: choseSuggestedBreakCurrentEpisode,
            actualBreakSeconds: actualSeconds,
            returnedToFocus: returnedToFocus,
            endedEarly: endedEarly,
            overrunSeconds: overrunSeconds
        )

        choseSuggestedBreakCurrentEpisode = false
    }

    private func activateBlocking() {
        log("activateBlocking called")
        if let project = selectedProject {
            let profiles = project.effectiveBlockProfiles
            if !profiles.isEmpty {
                let names = profiles.map(\.name).joined(separator: ", ")
                log("Using project-specific profiles: \(names)")
                BlockingService.shared.activate(profiles: profiles)
                return
            }
        }
        if let profile = selectedProject?.blockProfile {
            // Legacy fallback for stores that have not yet materialized blockProfiles.
            log("Using legacy project-specific profile: \(profile.name)")
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
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func startPauseTimer() {
        pauseTimer?.invalidate()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
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
            checkMomentumRamp()
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
        if isStarterBlock, let session = currentSession, session.type == .focus {
            completeStarterBlock(session)
            return
        }
        // Don't invalidate timer — continues for overtime
        currentSession?.endedAt = Date()
        currentSession?.completed = true
        currentSession?.pauseCount = pauseCountThisSession
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
            if let session = currentSession {
                creditCoachPromptForCompletion(sessionID: session.id)
            }
            // Build durable earned-block context (replaces prior context for this session)
            if let session = currentSession {
                completedBlockContext = CompletedBlockContext(
                    sessionId: session.id,
                    projectName: session.project?.name ?? selectedProject?.name ?? "Focus",
                    projectId: session.project?.id ?? selectedProject?.id,
                    durationMinutes: Int(session.actualDuration / 60),
                    workMode: selectedProject?.workMode ?? .deepWork,
                    earnedAt: Date()
                )
                refreshEarnedBreakSuggestion()
            }
        } else {
            // Break completed naturally — mark episode end
            breakEpisodeContext?.breakEnded = Date()
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
        lastSessionDistractingEntries = AppUsageTracker.shared.sessionDistractingEntries
        AppUsageTracker.shared.syncCadence(isFocusing: false)
        showSessionComplete = true
        closePopover()
        DispatchQueue.main.async { [weak self] in
            self?.openCompletionWindow?()
            self?.requestAppActivation?()
        }
        currentCoachQuickPromptDecision = nil
        hideCoachPanel()
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
        if case .continueOvertime = action {
            // keep existing flag while staying in the same episode
        } else {
            hasPromptedBreakOverrunReasonInCurrentEpisode = false
        }

        if case .continueOvertime = action {
            // Keep overtime state and timer running.
            return
        }

        if case .continueFocusing = action {
            recordBreakLearningIfNeeded(returnedToFocus: true)
        } else if case .endSession = action {
            recordBreakLearningIfNeeded(returnedToFocus: false)
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
                if session.endedAt == nil {
                    session.endedAt = Date()
                }
            }
            saveContext()
        }
        loadTodayStats()

        switch action {
        case .continueOvertime:
            break
        case .continueFocusing:
            startFocus()
        case .takeBreak(let duration):
            if let duration {
                choseSuggestedBreakCurrentEpisode = Int(duration) == Int(suggestedEarnedBreakSeconds) && suggestedEarnedBreakMinutes > 5
            } else {
                choseSuggestedBreakCurrentEpisode = false
            }
            startBreak(overrideDuration: duration)
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
              !showCoachReasonSheet,
              !hasPromptedBreakOverrunReasonInCurrentEpisode else { return }
        showCoachReasonSheet = true
        pendingReasonKind = .breakOverrun
        hasPromptedBreakOverrunReasonInCurrentEpisode = true
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
        if kind == .breakOverrun {
            hasPromptedBreakOverrunReasonInCurrentEpisode = true
        }
    }

    /// Records the user's classification of a detected distracting app from the post-session review.
    /// - isPlanned=true: records a project-scoped allowance in DriftMemory so coach won't flag it again.
    /// - isPlanned=false: inserts a manual IdleDistractionItem (minor severity) for future blocking/warnings.
    func classifySessionApp(entry: AppUsageTracker.SessionDistractingEntry, isPlanned: Bool) {
        if isPlanned {
            let target: IdleDistractionCatalog.Target = entry.isBrowserDomain
                ? .website(entry.domainOrBundleKey)
                : .app(entry.bundleIdentifier)
            coachEngine.driftMemoryStore?.recordPlanned(
                projectId: completedBlockContext?.projectId,
                workMode: completedBlockContext?.workMode,
                appOrDomain: target.normalizedKey
            )
        } else {
            guard let ctx = modelContext else { return }
            let item: IdleDistractionItem = entry.isBrowserDomain
                ? .manualWebsite(entry.domainOrBundleKey, severity: .minor)
                : .manualApp(entry.bundleIdentifier, severity: .minor)
            ctx.insert(item)
            saveContext()
        }
    }

    /// Reverts a classification made during session review (Undo action).
    /// Clears any DriftMemory planned allowance and removes manual IdleDistractionItems from SwiftData.
    func declassifySessionApp(entry: AppUsageTracker.SessionDistractingEntry) {
        // Must match the key classifySessionApp recorded (Target.normalizedKey, no prefix).
        let targetKey = (entry.isBrowserDomain
            ? IdleDistractionCatalog.Target.website(entry.domainOrBundleKey)
            : IdleDistractionCatalog.Target.app(entry.bundleIdentifier)).normalizedKey

        coachEngine.driftMemoryStore?.removePlanned(
            projectId: completedBlockContext?.projectId,
            workMode: completedBlockContext?.workMode,
            appOrDomain: targetKey
        )
        
        guard let ctx = modelContext else { return }
        let fetchDescriptor = FetchDescriptor<IdleDistractionItem>()
        if let items = try? ctx.fetch(fetchDescriptor) {
            let normalizedKeyToMatch = entry.domainOrBundleKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            for item in items {
                let matches = (item.key == normalizedKeyToMatch) &&
                              (item.targetKind == (entry.isBrowserDomain ? .website : .app))
                if matches && item.source == .manual {
                    ctx.delete(item)
                }
            }
            saveContext()
        }
    }

    /// Handles a coach quick action selection (popover card, notification, panel).
    /// Returns false when the action could not complete (a refused start); the caller should
    /// keep its surface open so `startError` stays visible (bug B5).
    @discardableResult
    func handleCoachAction(_ action: FocusCoachQuickAction, skipReason: FocusCoachSkipReason? = nil) -> Bool {
        let fromPanel = showCoachInterventionWindow
        let panelAttemptID = coachPanel?.attemptID
        switch action {
        case .returnNow:
            coachEngine.recordInterventionOutcome(.improved, attemptID: panelAttemptID)
            if state == .paused { resume() }
            clearCoachPrompts()
            closePopover()
        case .cleanRestart5m:
            // Never delete the running session (bug B1): save it as incomplete, then start a
            // 5-minute block without changing the user's chosen duration for later sessions.
            if state != .idle || isOvertime {
                stop()
            }
            let preferredMinutes = selectedMinutes
            selectedMinutes = 5
            let started = startFocus()
            selectedMinutes = preferredMinutes
            guard started else { return false }
            coachEngine.recordInterventionOutcome(.improved, attemptID: panelAttemptID)
            clearCoachPrompts()
            closePopover()
        case .snooze10m, .skipCheck:
            applyGuardianReleaseIfNeeded(for: action, reason: skipReason)
            let minutes = settings?.coachDefaultSnoozeMinutes ?? 10
            if let panelAttemptID {
                coachEngine.recordInterventionOutcome(.snoozed, attemptID: panelAttemptID)
            }
            coachEngine.snooze(minutes: minutes, skipReason: skipReason)
            snoozeIdleCoach(minutes: minutes)
            clearCoachPrompts()
            closePopover()
        case .startFocusNow:
            guard startCoachPlan(currentCoachPlan(), attemptID: panelAttemptID) else { return false }
            clearCoachPrompts()
            closePopover()
        case .blockForProject:
            coachEngine.recordInterventionOutcome(.improved, attemptID: panelAttemptID)
            applyProjectBlockRecommendation()
            clearCoachPrompts()
            closePopover()
        case .markOffDuty:
            if let panelAttemptID {
                coachEngine.recordInterventionOutcome(.snoozed, attemptID: panelAttemptID)
            }
            coachEngine.snooze(minutes: 90, skipReason: .doneForToday)
            // Off-duty is an explicit release intent: enter release + clear all pending prompt surfaces.
            enterDoneForToday()
            clearCoachPrompts()
            closePopover()
        case .isPlanned:
            if let panelAttemptID {
                coachEngine.recordInterventionOutcome(.snoozed, attemptID: panelAttemptID)
            }
            coachEngine.recordOutsideSessionClassification(.plannedResearch)
            let minutes = settings?.coachDefaultSnoozeMinutes ?? 10
            coachEngine.snooze(minutes: minutes, skipReason: nil)
            snoozeIdleCoach(minutes: minutes)
            clearCoachPrompts()
            closePopover()
        }
        if fromPanel {
            interventionActionTaken = true
        }
        return true
    }

    /// Routes an action taken on a coach check-in notification (bug B4).
    func handleCoachNotificationResponse(_ response: CoachNotificationResponse) {
        log("coach notification response: \(response), state=\(state)")
        switch response {
        case .startFocus:
            if !handleCoachAction(.startFocusNow) {
                NotificationService.shared.sendGenericNotification(
                    title: "Focus didn't start",
                    body: startError ?? "Open FocusFlow to start a block.",
                    sound: settings?.completionSound ?? "Glass"
                )
            }
        case .snooze:
            handleCoachAction(.snooze10m)
        case .open:
            // Opening the notification shows its prompt on screen; it is not a new delivery.
            guard state == .idle, let decision = pendingCoachNotificationDecision else { return }
            let message = decision.composed ?? CoachMessageComposer.neutralFallback(isInSession: false)
            presentCoachPanel(
                CoachPanelPresentation(
                    kind: .startNudge,
                    message: message,
                    plan: pendingCoachNotificationPlan,
                    attemptID: pendingCoachAttemptID
                ),
                decision: decision
            )
        }
        pendingCoachNotificationDecision = nil
    }

    /// Dismisses the popover prompt card (its X).
    func dismissCoachPrompt() {
        coachEngine.recordInterventionOutcome(.dismissed, attemptID: pendingCoachAttemptID)
        if currentIdleStarterDecision != nil {
            lastAbandonedStartAt = Date()
            coachEngine.recordOutsideSessionMissedStart()
        }
        currentCoachQuickPromptDecision = nil
        currentIdleStarterDecision = nil
        coachMenuBarPulse = false
    }

    /// Records that the user explicitly selected a project (user-initiated selection).
    func noteProjectSelected() {
        lastProjectSelectedAt = Date()
        prefillIntentForSelectedProject()
    }

    /// Closes the coach panel without an action (its X, or the v1 window API). Records
    /// `.dismissed` only when no action was taken, so an action's own outcome is kept (B12).
    func dismissCoachInterventionWindow() {
        // ✕ on the plan card or a planned cue means "later", not "ignored" (v3 §3.2).
        if isStickyCoachPanelShowing, !interventionActionTaken {
            performCoachPanelEscape()
            return
        }
        if (showCoachInterventionWindow || coachPanel != nil) && !interventionActionTaken
            && Self.panelKindLogsOutcome(coachPanel?.kind) {
            coachEngine.recordInterventionOutcome(.dismissed, attemptID: coachPanel?.attemptID)
        }
        interventionActionTaken = false
        hideCoachPanel()
        if let prompt = currentCoachQuickPromptDecision, prompt.kind == .quickPrompt {
            currentCoachQuickPromptDecision = nil
        }
    }

    /// Snooze the coach for a user-chosen duration (in minutes).
    func handleSnooze(minutes: Int) {
        coachEngine.snooze(minutes: minutes, skipReason: nil)
        snoozeIdleCoach(minutes: minutes)
        clearCoachPrompts()
        closePopover()
    }

    private func snoozeIdleCoach(minutes: Int, now: Date = Date()) {
        let until = now.addingTimeInterval(TimeInterval(max(1, minutes) * 60))
        coachQuietUntil = max(coachQuietUntil ?? until, until)
    }

    /// "Done for today": release window plus quiet until tomorrow.
    private func enterDoneForToday(now: Date = Date()) {
        enterRelease(reason: .offDuty)
        skipRemainingPlans(now: now)
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now))
        coachQuietUntil = tomorrow ?? now.addingTimeInterval(12 * 3600)
    }

    /// Clears every prompt surface: popover cards, the panel and the menu bar pulse.
    private func clearCoachPrompts() {
        currentCoachQuickPromptDecision = nil
        currentIdleStarterDecision = nil
        coachMenuBarPulse = false
        hideCoachPanel()
    }

    // MARK: - Coach panel

    /// Shows the on-screen panel. One panel at a time: a new one replaces the old.
    func presentCoachPanel(_ presentation: CoachPanelPresentation, decision: FocusCoachDecision? = nil) {
        coachPanel = presentation
        coachPanelError = nil
        activeCoachInterventionDecision = decision ?? FocusCoachDecision(
            kind: .strongPrompt,
            suggestedActions: [],
            message: nil,
            composed: presentation.message
        )
        showCoachInterventionWindow = true
        interventionActionTaken = false
        coachPanelHost?.showPanel(presentation)
        scheduleCoachPanelAutoHide(for: presentation.id, after: presentation.autoHideSeconds)
    }

    func hideCoachPanel() {
        coachPanelAutoHideTask?.cancel()
        coachPanelAutoHideTask = nil
        let wasVisible = coachPanel != nil
        coachPanel = nil
        coachPanelError = nil
        showCoachInterventionWindow = false
        activeCoachInterventionDecision = nil
        if wasVisible {
            coachPanelHost?.hidePanel()
        }
    }

    /// The panel's primary button. Returns false when a start was refused; the panel stays
    /// open and shows `coachPanelError`.
    @discardableResult
    func performCoachPanelPrimary() -> Bool {
        guard let panel = coachPanel else { return false }
        switch panel.kind {
        case .startNudge:
            guard startCoachPlan(panel.plan, attemptID: panel.attemptID) else { return false }
        case .pseudoProductivity:
            logPseudoAnswer(.isPriority, panel: panel)
            guard startCoachPlan(panel.plan, attemptID: panel.attemptID) else { return false }
        case .inSessionDrift:
            return handleCoachAction(.returnNow)
        case .weeklyPriorities:
            markWeeklyInviteHandled()
            coachEngine.recordInterventionOutcome(.improved, attemptID: panel.attemptID)
            hideCoachPanel()
            UserDefaults.standard.set("coach", forKey: "settingsRequestedTab")
            openSettingsScene?()
        case .rescue:
            guard let ask = panel.ask else { return false }
            switch ask.kind {
            case .starter:
                guard startStarterBlock(attemptID: panel.attemptID) else {
                    coachPanelError = startError
                    return false
                }
            case .normal:
                guard startCoachPlan(ask.target ?? panel.plan, attemptID: panel.attemptID) else { return false }
            }
            rescueStartedSessionID = currentSession?.id
        case .keepGoing:
            guard continueAfterStarter(step: panel.step) else {
                coachPanelError = startError
                return false
            }
        case .momentum:
            extendTimer(by: CoachMomentumRamp.extensionSeconds(totalSeconds: totalSeconds))
            hideCoachPanel()
        case .notice:
            hideCoachPanel()
        case .plannedStart:
            guard startCoachPlan(panel.plan, attemptID: panel.attemptID) else { return false }
        case .dailyPlan:
            guard let slot = panel.planSlots.first else { return false }
            commitDailyPlan(slot)
        }
        if panel.kind == .pseudoProductivity, panel.level != nil {
            rescueStartedSessionID = currentSession?.id
        }
        interventionActionTaken = true
        return true
    }

    /// Esc on a clicked panel: "Not now" (or the panel's own decline).
    func performCoachPanelEscape() {
        guard let panel = coachPanel else { return }
        if let action = panel.escapeAction {
            performCoachPanelSecondary(action)
        } else {
            hideCoachPanel()
        }
    }

    /// The panel's "Not now ▾" menu items.
    func performCoachPanelSecondary(_ action: CoachPanelSecondaryAction, now: Date = Date()) {
        guard let panel = coachPanel else { return }
        switch action {
        case .snooze15, .snooze60:
            let minutes = action == .snooze15 ? 15 : 60
            coachEngine.recordInterventionOutcome(.snoozed, attemptID: panel.attemptID)
            if panel.kind == .inSessionDrift {
                coachEngine.snooze(minutes: minutes)
            } else {
                snoozeIdleCoach(minutes: minutes, now: now)
                currentIdleStarterDecision = nil
            }
            interventionActionTaken = true
            hideCoachPanel()
        case .doneForToday:
            coachEngine.recordInterventionOutcome(.snoozed, attemptID: panel.attemptID)
            coachEngine.snooze(minutes: 90, skipReason: .doneForToday)
            enterDoneForToday(now: now)
            interventionActionTaken = true
            clearCoachPrompts()
        case .sideQuest:
            logPseudoAnswer(.sideQuest, panel: panel, now: now)
            if startCoachPlan(panel.plan, attemptID: panel.attemptID) {
                interventionActionTaken = true
            }
        case .planned:
            logPseudoAnswer(.planned, panel: panel, now: now)
            coachEngine.recordInterventionOutcome(.snoozed, attemptID: panel.attemptID)
            snoozeIdleCoach(minutes: CoachPseudoProductivityGuard.plannedQuietMinutes, now: now)
            interventionActionTaken = true
            hideCoachPanel()
        case .partOfWork:
            handleCoachAction(.isPlanned)
        case .endBlock:
            coachEngine.recordInterventionOutcome(.dismissed, attemptID: panel.attemptID)
            interventionActionTaken = true
            hideCoachPanel()
            stopForReflection()
        case .skipWeek:
            markWeeklyInviteHandled(now: now)
            coachEngine.recordInterventionOutcome(.dismissed, attemptID: panel.attemptID)
            interventionActionTaken = true
            hideCoachPanel()
        case .finishStarter, .keepShort:
            // The starter already counted as a completed block; the block keeps its length.
            interventionActionTaken = true
            hideCoachPanel()
        case .starterInstead:
            // Two-minute rule: the smallest real start still fulfils the plan.
            guard startStarterBlock(attemptID: panel.attemptID) else {
                coachPanelError = startError
                return
            }
            interventionActionTaken = true
        case .push15, .push60:
            coachEngine.recordInterventionOutcome(.snoozed, attemptID: panel.attemptID)
            if let id = panel.plannedBlockID {
                pushPlannedBlock(id: id, minutes: action == .push15 ? CoachPlannedCue.pushMinutes : 60, now: now)
            }
            interventionActionTaken = true
            hideCoachPanel()
        case .skipToday:
            coachEngine.recordInterventionOutcome(.snoozed, attemptID: panel.attemptID)
            interventionActionTaken = true
            if let id = panel.plannedBlockID { skipPlannedBlock(id: id, now: now) }
            hideCoachPanel()
        case .planLater:
            coachEngine.recordInterventionOutcome(.snoozed, attemptID: panel.attemptID)
            interventionActionTaken = true
            hideCoachPanel()
        case .notToday:
            coachEngine.recordInterventionOutcome(.snoozed, attemptID: panel.attemptID)
            let store = CoachDailyPlanInviteStore(defaults: defaults)
            var inviteLog = store.load(now: now)
            inviteLog.declined = true
            store.save(inviteLog)
            interventionActionTaken = true
            hideCoachPanel()
        }
    }

    /// Auto-hide after 20 s without interaction: counts as ignored and leaves a pulse on the
    /// menu bar icon (the popover keeps the prompt card until opened).
    func coachPanelTimedOut(id: UUID, now: Date = Date()) {
        guard let panel = coachPanel, panel.id == id else { return }
        guard Self.panelKindLogsOutcome(panel.kind) else {
            // Keep-going: no answer is a decline (the starter still counts). Momentum, notice: nothing to do.
            hideCoachPanel()
            return
        }
        // No input for the panel's whole life: the user was away, not ignoring it (v3 R3).
        let unseen = Self.panelWasUnseen(shownFor: now.timeIntervalSince(panel.createdAt), systemIdleSeconds: systemIdleSeconds())
        coachEngine.recordInterventionOutcome(unseen ? .unseen : .ignored, attemptID: panel.attemptID)
        hideCoachPanel()
        coachMenuBarPulse = true
    }

    /// True when the user had no keyboard or mouse input for (almost) the whole time the panel
    /// was up. A 5 s margin absorbs the tick between showing and the first idle reading; a panel
    /// up for under 10 s can't tell "away" from "busy", so it never counts as unseen.
    nonisolated static func panelWasUnseen(shownFor: TimeInterval, systemIdleSeconds: TimeInterval) -> Bool {
        shownFor >= 10 && systemIdleSeconds >= shownFor - 5
    }

    /// Keep-going, momentum and notice panels are not logged prompts: no outcome to record.
    private static func panelKindLogsOutcome(_ kind: CoachPanelPresentation.Kind?) -> Bool {
        switch kind {
        case .keepGoing, .momentum, .notice: false
        default: true
        }
    }

    /// Hovering pauses the auto-hide so the user can read; leaving restarts a shorter timer.
    func coachPanelHoverChanged(_ hovering: Bool) {
        guard let panel = coachPanel else { return }
        if hovering {
            coachPanelAutoHideTask?.cancel()
            coachPanelAutoHideTask = nil
        } else {
            // Sticky panels (planned cue, daily plan) stay; others get 20 s after the pointer leaves.
            scheduleCoachPanelAutoHide(for: panel.id, after: panel.autoHideSeconds.map { min($0, 20) })
        }
    }

    /// Opening the popover answers the pulse and refreshes this week's priorities.
    func noteCoachPopoverOpened() {
        coachMenuBarPulse = false
        reloadWeeklyPriorities()
        prefillIntentForSelectedProject()
    }

    private func scheduleCoachPanelAutoHide(for id: UUID, after seconds: Double?) {
        coachPanelAutoHideTask?.cancel()
        coachPanelAutoHideTask = nil
        guard !isEvidenceMode, let seconds else { return }
        coachPanelAutoHideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.coachPanelTimedOut(id: id)
        }
    }

    // MARK: - Coach start plans

    /// Starts `plan` (minutes, project, priority) without changing the user's chosen duration.
    /// On failure nothing changes, `startError` says why and the panel shows it.
    @discardableResult
    func startCoachPlan(_ plan: CoachStartTarget?, attemptID: UUID? = nil) -> Bool {
        let previousProject = selectedProject
        let previousPriority = pendingPriorityID
        let preferredMinutes = selectedMinutes
        if let projectID = plan?.projectID, let project = historyReader?.project(id: projectID) {
            selectedProject = project
        }
        if let priorityID = plan?.priorityID {
            pendingPriorityID = priorityID
        }
        if let minutes = plan?.minutes ?? idleStarterRecommendedMinutes {
            selectedMinutes = minutes
        }
        let started = startFocus()
        selectedMinutes = preferredMinutes
        guard started else {
            selectedProject = previousProject
            pendingPriorityID = previousPriority
            if let panel = coachPanel {
                coachPanelError = startError
                scheduleCoachPanelAutoHide(for: panel.id, after: panel.autoHideSeconds.map { _ in Self.coachPanelAutoHideSeconds })
            }
            return false
        }
        coachEngine.recordInterventionOutcome(.improved, attemptID: attemptID)
        return true
    }

    /// The plan behind whatever prompt is showing (panel first, then the popover card).
    private func currentCoachPlan() -> CoachStartTarget? {
        if let plan = coachPanel?.plan { return plan }
        if let minutes = idleStarterRecommendedMinutes {
            return CoachStartTarget(minutes: minutes, name: nil, projectID: nil, priorityID: nil)
        }
        return nil
    }

    // MARK: - Intent capture and outcome rating

    /// Prefills the popover intent with the user's last intent for the selected project,
    /// unless they already typed something of their own.
    func prefillIntentForSelectedProject() {
        guard state == .idle, let reader = historyReader else { return }
        let current = pendingIntentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard current.isEmpty || current == lastPrefilledIntent else { return }
        let last = reader.lastIntent(projectID: selectedProject?.id) ?? ""
        pendingIntentText = last
        lastPrefilledIntent = last.isEmpty ? nil : last
        if pendingPriorityID == nil, let projectID = selectedProject?.id {
            pendingPriorityID = weeklyPriorities.first { $0.projectID == projectID && !$0.isDone }?.id
        }
    }

    /// Saves Shipped / Moved it forward / Busywork on the last focus block and feeds the
    /// rating into the bandit reward of the prompt that led to it.
    func recordSessionOutcome(_ outcome: SessionOutcome) {
        guard let session = lastCompletedFocusSession ?? lastCompletedSession, session.type == .focus else { return }
        let previous = session.outcome
        guard previous != outcome else { return }
        session.outcome = outcome
        saveContext()
        if rewardLedger?.creditOutcome(sessionID: session.id, outcome: outcome, previous: previous) == true {
            rebuildBandit()
        }
    }

    // MARK: - Coach v2 learning

    private var historyReader: CoachHistoryReader? {
        modelContext.map { CoachHistoryReader(modelContext: $0) }
    }

    private var rewardLedger: CoachRewardLedger? {
        modelContext == nil ? nil : CoachRewardLedger(store: coachEngine.store)
    }

    func reloadWeeklyPriorities(now: Date = Date()) {
        weeklyPriorities = historyReader?.weeklyPriorities(now: now) ?? []
    }

    /// Recomputes the availability model once a day (and on launch), and the bandit on launch.
    func refreshCoachModelsIfNeeded(now: Date = Date(), force: Bool = false) {
        if let availabilityModelOverride {
            availabilityModel = availabilityModelOverride
        } else {
            let today = Calendar.current.startOfDay(for: now)
            if force || availabilityComputedDay != today, let reader = historyReader {
                let inputs = reader.availabilityInputs(now: now)
                availabilityModel = CoachAvailabilityModel(sessions: inputs.sessions, activeDays: inputs.activeDays)
                availabilityComputedDay = today
            }
        }
        if force {
            resolveExpiredCoachRewards(now: now, rebuild: false)
            rebuildBandit()
            refreshBusyworkContexts()
        }
    }

    /// Rebuilds the bandit posteriors from the logged rewards (the source of truth) and caches
    /// them as JSON in UserDefaults for readers such as Insights.
    private func rebuildBandit() {
        guard let ledger = rewardLedger else { return }
        banditModel = CoachBanditModel.rebuild(from: ledger.rewardRecords())
        if !isEvidenceMode { banditStore.save(banditModel) }
    }

    private func resolveExpiredCoachRewards(now: Date, rebuild: Bool = true) {
        guard let ledger = rewardLedger else { return }
        if ledger.resolveExpired(now: now) > 0 {
            if let id = pendingCoachAttemptID, ledger.attempt(id: id)?.reward != nil {
                pendingCoachAttemptID = nil
            }
            if rebuild { rebuildBandit() }
        }
    }

    private func creditCoachPromptForStart(sessionID: UUID, now: Date = Date()) {
        guard let attemptID = pendingCoachAttemptID else { return }
        pendingCoachAttemptID = nil
        if rewardLedger?.creditStart(attemptID: attemptID, sessionID: sessionID, at: now) == true {
            rebuildBandit()
        }
    }

    private func creditCoachPromptForCompletion(sessionID: UUID) {
        if rewardLedger?.creditCompletion(sessionID: sessionID) == true {
            rebuildBandit()
        }
    }

    // MARK: - Coach snapshot (facts from data)

    struct CoachSnapshot {
        let now: Date
        let inGoodWindow: Bool
        let tier: CoachAvailabilityModel.Tier
        let pacing: CoachGoalPacing
        let facts: CoachFacts
        let target: CoachStartTarget
        let topPriority: WeeklyPriority?
        let frontCategory: AppUsageEntry.AppCategory
    }

    func coachSnapshot(
        now: Date = Date(),
        idleSeconds: Int,
        frontmostCategory: AppUsageEntry.AppCategory,
        minutesUntilNextEvent: Int? = nil
    ) -> CoachSnapshot {
        refreshCoachModelsIfNeeded(now: now)
        let model = availabilityModel
        let reader = historyReader
        let calendar = Calendar.current
        let goalMinutes = Int((settings?.dailyFocusGoal ?? 7200) / 60)
        let doneMinutes = Int(todayFocusTime / 60)
        let pacing = CoachGoalPacing(
            goalMinutes: goalMinutes,
            doneMinutes: doneMinutes,
            windowMinutesLeft: model.goodWindowMinutesRemainingToday(from: now)
        )
        let topPriority = weeklyPriorities.first { !$0.isDone }

        // Block length: max(25, min(remaining, 50)), shortened to end 5 min before a meeting.
        var minutes = pacing.suggestedBlockMinutes
        if let nextEvent = minutesUntilNextEvent, nextEvent - 5 < minutes {
            minutes = max(15, ((nextEvent - 5) / 5) * 5)
        }
        let projectID = topPriority?.projectID ?? selectedProject?.id
        let target = CoachStartTarget(
            minutes: minutes,
            name: topPriority?.title ?? selectedProject?.name,
            projectID: projectID,
            priorityID: topPriority?.id
        )

        var facts = CoachFacts()
        facts.goalMinutes = goalMinutes
        facts.doneMinutesToday = doneMinutes
        facts.pacing = pacing
        if let reader {
            let streak = reader.streakDays(now: now)
            facts.streakDays = streak.streak
            facts.missedYesterday = streak.missedYesterday
            facts.hasHistory = streak.hasHistory
            facts.sessionsToday = reader.focusSessions(since: calendar.startOfDay(for: now)).count
            if let end = reader.lastFocusSessionEnd(before: now) {
                facts.minutesSinceLastSession = max(0, Int(now.timeIntervalSince(end) / 60))
            }
            facts.lastIntent = reader.lastIntent(projectID: projectID)
            facts.daysWithoutBlock = reader.daysWithoutBlock(now: now)
            facts.derailer = reader.derailerFact(
                bundleIdentifier: AppUsageTracker.shared.currentFrontmostBundleId,
                browserHost: AppUsageTracker.shared.currentFrontmostBrowserHost,
                displayName: AppUsageTracker.shared.currentFrontmostDisplayLabel,
                allowDomains: settings?.coachCollectRawDomains == true,
                catalog: loadIdleDistractionCatalog(),
                now: now
            )
        }
        let hour = calendar.component(.hour, from: now)
        if model.usualStartHour(on: now) == hour { facts.usualStartHourNow = hour }

        return CoachSnapshot(
            now: now,
            inGoodWindow: model.isGoodWindow(now),
            tier: model.tier(now),
            pacing: pacing,
            facts: facts,
            target: target,
            topPriority: topPriority,
            frontCategory: frontmostCategory
        )
    }

    /// `motivation`: the learner's pick. `.some(nil)` means it ran and found nothing it may show
    /// (everything shown in the last 3 days), so no quote is shown rather than a repeat.
    private func composeCoachMessage(
        trigger: CoachTrigger,
        style: CoachStyle,
        snapshot: CoachSnapshot,
        motivation: CoachMotivationItem?? = nil
    ) -> CoachComposedMessage {
        let day = Calendar.current.ordinality(of: .day, in: .era, for: snapshot.now) ?? 0
        let delivered = coachEngine.store.attempts(deliveredSince: Calendar.current.startOfDay(for: snapshot.now)).count
        var input = CoachComposerInput(
            style: style,
            trigger: trigger,
            facts: snapshot.facts,
            target: snapshot.target,
            whyLines: settings?.coachMyWhyLines ?? [],
            seed: day &+ delivered
        )
        input.starterMinutes = CoachStarterBlock.clampedMinutes(settings?.coachStarterBlockMinutes ?? CoachStarterBlock.defaultMinutes)
        if let motivation {
            input.pickedDetail = motivation?.detail(starterMinutes: input.starterMinutes)
            input.pickerExhausted = motivation == nil
        }
        return CoachMessageComposer.compose(input)
    }

    private func coachGuardrailInput(now: Date, calendarBusy: Bool, isIdlePrompt: Bool) -> CoachGuardrails.Input {
        let since = now.addingTimeInterval(-24 * 3600)
        return CoachGuardrails.Input(
            now: now,
            deliveries: coachEngine.guardrailDeliveries(since: since),
            maxPromptsPerDay: settings?.coachMaxPromptsPerDay ?? 3,
            quietStartMinute: settings?.coachQuietStartMinute ?? 30,
            quietEndMinute: settings?.coachQuietEndMinute ?? 420,
            calendarBusy: calendarBusy,
            screenShareActive: settings.map(shouldSuppressGuardianPopups(using:)) ?? false,
            releaseActive: isInReleaseWindow,
            snoozedUntil: isIdlePrompt ? coachQuietUntil : coachEngine.promptState.snoozedUntil,
            sessionActive: state != .idle || isOvertime,
            isIdlePrompt: isIdlePrompt
        )
    }

    /// Surfaces the bandit may pick for an idle prompt, before guardrails.
    private func candidateIdleSurfaces() -> [CoachSurface] {
        guard let settings else { return [.silent] }
        var surfaces: [CoachSurface] = [.silent, .badge]
        if settings.coachOnScreenPromptsEnabled { surfaces.append(.panel) }
        if settings.coachNotificationsEnabled && NotificationService.shared.authorizationState == .authorized {
            surfaces.append(.notification)
        }
        return surfaces
    }

    private func suppressIdlePrompt(_ reason: IdleStarterSuppressionReason) {
        lastIdleStarterSuppressionReason = reason
        currentIdleStarterDecision = nil
        if coachPanel?.kind == .startNudge || coachPanel?.kind == .weeklyPriorities {
            hideCoachPanel()
        }
    }

    // MARK: - Idle start nudge (decision policy)

    /// Decision point for "start a block" prompts. Order: hard guardrails, learned window,
    /// pacing, then the Thompson-sampling bandit picks surface × style (or silence).
    func evaluateIdleStarterIntervention(
        idleSeconds: Int,
        frontmostCategory: AppUsageEntry.AppCategory
    ) {
        guard state == .idle, !isOvertime, let settings else { return }
        let now = Date()
        resolveExpiredCoachRewards(now: now)
        if isInReleaseWindow {
            suppressIdlePrompt(.releaseWindowActive)
            return
        }
        if shouldSuppressGuardianPopups(using: settings) {
            suppressIdlePrompt(.screenShareSuppressed)
            return
        }
        guard settings.antiProcrastinationEnabled, settings.coachIdleStarterEnabled else {
            suppressIdlePrompt(settings.antiProcrastinationEnabled ? .idleStarterDisabled : .antiProcrastinationDisabled)
            return
        }
        if let last = lastIdleInterventionAt, now.timeIntervalSince(last) < 120 {
            lastIdleStarterSuppressionReason = .cooldownActive
            return
        }
        // A planned cue or the plan card is on screen: never replace it with a nudge.
        if isStickyCoachPanelShowing { return }
        // Drifting in a focus window: the rescue loop's ladder replaces the plain start nudge.
        if let drift = currentDrift, drift.isActive, drift.level > .ok {
            lastIdleStarterSuppressionReason = nil
            return
        }
        let calendarAvailability = currentCalendarAvailability(now: now)
        log("idle starter calendar: busyNow=\(calendarAvailability.isBusyNow) nextEventMin=\(calendarAvailability.minutesUntilNextEvent.map(String.init) ?? "nil")")
        let guardrailInput = coachGuardrailInput(now: now, calendarBusy: calendarAvailability.isBusyNow, isIdlePrompt: true)
        let baseVerdict = coachGuardrails.verdict(for: .badge, input: guardrailInput)
        if let reason = IdleStarterSuppressionReason(verdict: baseVerdict) {
            suppressIdlePrompt(reason)
            return
        }

        reloadWeeklyPriorities(now: now)
        let idleTarget = currentIdleDistractionTarget()
        let idleSeverity = idleTarget.flatMap { loadIdleDistractionCatalog().resolution(for: $0).severity }
        let effectiveCategory = AppUsageTracker.idleAdjustedCategory(
            frontmostCategory: frontmostCategory,
            idleSeverityOverride: idleSeverity
        )
        let snapshot = coachSnapshot(
            now: now,
            idleSeconds: idleSeconds,
            frontmostCategory: effectiveCategory,
            minutesUntilNextEvent: calendarAvailability.minutesUntilNextEvent
        )
        updateCoachDebugReadout(snapshot)

        guard snapshot.inGoodWindow else {
            suppressIdlePrompt(.outsideFocusWindow)
            return
        }
        guard snapshot.pacing.isBehindPace else {
            suppressIdlePrompt(.onTrack)
            return
        }

        let gated = coachGuardrails.allowedSurfaces(from: candidateIdleSurfaces(), input: guardrailInput)

        // First prompt of a week without priorities: invite the user to set 1–3 instead.
        if shouldInviteWeeklyPriorities(now: now) {
            if gated.surfaces.contains(.panel) {
                presentWeeklyPrioritiesInvite(snapshot: snapshot)
                lastIdleInterventionAt = now
                lastIdleStarterSuppressionReason = nil
                return
            }
        }

        let contextKey = CoachContextKey(
            availability: snapshot.tier,
            idle: .init(idleSeconds: idleSeconds),
            front: .init(category: effectiveCategory),
            hasSessionToday: snapshot.facts.sessionsToday > 0
        )
        let arm: CoachArm
        if let forced = coachArmOverride, gated.surfaces.contains(forced.surface) {
            arm = forced
        } else {
            arm = banditPolicy.choose(
                context: contextKey.rawValue,
                surfaces: gated.surfaces,
                preferredStyle: settings.coachStyle,
                model: banditModel,
                using: &coachRandom
            )
        }
        guard arm.surface != .silent, let style = arm.style else {
            // Prefer the guardrail that removed the panel as the explanation, if any.
            lastIdleStarterSuppressionReason = gated.firstBlock.flatMap(IdleStarterSuppressionReason.init(verdict:))
                ?? .banditChoseSilent
            currentIdleStarterDecision = nil
            return
        }

        deliverStartNudge(arm: arm, style: style, contextKey: contextKey, snapshot: snapshot, idleSeconds: idleSeconds)
        lastIdleInterventionAt = now
        lastIdleStarterSuppressionReason = nil
    }

    private func deliverStartNudge(
        arm: CoachArm,
        style: CoachStyle,
        contextKey: CoachContextKey,
        snapshot: CoachSnapshot,
        idleSeconds: Int
    ) {
        let situation = Self.startSituation(facts: snapshot.facts, now: snapshot.now)
        let motivation = pickMotivation(situation: situation, now: snapshot.now)
        let message = composeCoachMessage(trigger: .startNudge, style: style, snapshot: snapshot, motivation: motivation)
        let kind: FocusCoachInterventionKind = switch arm.surface {
        case .panel, .strongWindow: .strongPrompt
        case .notification: .softNudge
        case .badge, .silent: .quickPrompt
        }
        let attempt = coachEngine.recordDeliveredIntervention(
            kind: kind,
            riskScore: availabilityModel.p(snapshot.now),
            sessionId: nil,
            now: snapshot.now,
            surface: arm.surface,
            style: style,
            contextKey: contextKey.rawValue
        )
        pendingCoachAttemptID = attempt.id
        // Log the quote only when it is on screen (v3 R6: a fact used to displace it and the
        // quote was still logged, burning the 3-day no-repeat pool).
        if message.showsMotivation { noteMotivationShown(motivation, attemptID: attempt.id, at: snapshot.now) }

        let coachCtx = buildCoachContext(
            idleSeconds: idleSeconds,
            frontmostCategory: snapshot.frontCategory,
            frontmostDisplayLabel: AppUsageTracker.shared.currentFrontmostDisplayLabel
        )
        var actions: [FocusCoachQuickAction] = [.startFocusNow, .snooze10m, .markOffDuty]
        if coachCtx.hasBlockRecommendation { actions.append(.blockForProject) }
        let decision = FocusCoachDecision(
            kind: arm.surface == .panel ? .strongPrompt : .quickPrompt,
            suggestedActions: actions,
            message: nil,
            context: coachCtx,
            composed: message
        )
        currentIdleStarterDecision = decision
        // The card shows the composed detail; no second summary line.
        idleStarterSummary = nil
        idleStarterRecommendedMinutes = snapshot.target.minutes

        switch arm.surface {
        case .panel, .strongWindow:
            presentCoachPanel(
                CoachPanelPresentation(kind: .startNudge, message: message, plan: snapshot.target, attemptID: attempt.id),
                decision: decision
            )
        case .notification:
            NotificationService.shared.sendCoachCheckIn(
                title: message.hook,
                body: [message.detail?.text, message.primaryTitle].compactMap { $0 }.joined(separator: " · "),
                sound: settings?.completionSound ?? "Glass"
            )
            pendingCoachNotificationDecision = decision
            pendingCoachNotificationPlan = snapshot.target
            coachMenuBarPulse = true
        case .badge, .silent:
            coachMenuBarPulse = true
        }
    }

    private func updateCoachDebugReadout(_ snapshot: CoachSnapshot) {
        let p = availabilityModel.p(snapshot.now)
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: snapshot.now)
        let best = (0..<24).compactMap { calendar.date(byAdding: .hour, value: $0, to: dayStart) }
            .map(availabilityModel.p).max() ?? p
        latestWorkIntentScore = best > 0 ? min(1, p / best) : 0
        latestDriftScore = min(1, snapshot.pacing.pressure ?? 0)
        latestWorkIntentActiveSignals = [
            "window: \(snapshot.tier.rawValue)",
            snapshot.inGoodWindow ? "learned window open" : "outside learned windows",
        ]
        latestDriftActiveSignals = [
            "pacing: \(snapshot.pacing.tier.rawValue)",
            "\(snapshot.pacing.doneMinutes)m of \(snapshot.pacing.goalMinutes)m",
        ]
    }

    // MARK: - Weekly priorities invite

    func shouldInviteWeeklyPriorities(now: Date) -> Bool {
        guard let reader = historyReader, reader.hasEntity(named: "WeeklyPriority"), weeklyPriorities.isEmpty else {
            return false
        }
        let weekStart = WeeklyPriority.weekStart(for: now)
        return defaults.double(forKey: Self.weeklyInviteDefaultsKey) != weekStart.timeIntervalSince1970
    }

    private func markWeeklyInviteHandled(now: Date = Date()) {
        defaults.set(WeeklyPriority.weekStart(for: now).timeIntervalSince1970, forKey: Self.weeklyInviteDefaultsKey)
    }

    private func presentWeeklyPrioritiesInvite(snapshot: CoachSnapshot) {
        let style = settings?.coachStyle ?? .challenger
        let message = composeCoachMessage(trigger: .weeklyPriorities, style: style, snapshot: snapshot)
        let attempt = coachEngine.recordDeliveredIntervention(
            kind: .strongPrompt,
            riskScore: 0,
            sessionId: nil,
            now: snapshot.now,
            surface: .panel,
            style: style
        )
        markWeeklyInviteHandled(now: snapshot.now)
        presentCoachPanel(CoachPanelPresentation(kind: .weeklyPriorities, message: message, attemptID: attempt.id))
    }

    // MARK: - Pseudo-productivity guard (§9 step 4)

    private func startCoachIdleTimer() {
        guard !isEvidenceMode else { return }
        coachIdleTimer?.invalidate()
        let timer = Timer(timeInterval: Self.coachIdleTickSeconds, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.coachIdleTick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        coachIdleTimer = timer
    }

    static let coachIdleTickSeconds: TimeInterval = 15

    private func coachIdleTick(now: Date = Date()) {
        coachIdleTickCount += 1
        // R5: the midnight timer does not advance while the Mac sleeps, and dark wakes skip
        // didWake. Checking here keeps "today" right within 15 s of the first tick of the day.
        checkDayRolloverIfNeeded()
        syncGlobalHotkey()
        // v3: the user's own planned start comes first; it owns the screen until answered.
        if evaluatePlannedCue(now: now) { return }
        evaluateRescueLoop(now: now)
        // The rest runs once a minute.
        guard coachIdleTickCount % 4 == 0 else { return }
        resolveExpiredCoachRewards(now: now)
        if evaluateDailyPlanInvite(now: now) { return }
        // While the rescue loop owns a drift episode it asks the pseudo-work question itself.
        if let drift = currentDrift, drift.isActive, drift.level > .ok { return }
        evaluatePseudoProductivityGuard(
            now: now,
            frontmostCategory: AppUsageTracker.shared.currentFrontmostCategory,
            contextName: AppUsageTracker.shared.currentFrontmostDisplayLabel
        )
    }

    /// Runs every minute while idle. Returns true when the question was shown.
    @discardableResult
    func evaluatePseudoProductivityGuard(
        now: Date = Date(),
        frontmostCategory: AppUsageEntry.AppCategory,
        contextName: String?
    ) -> Bool {
        let sessionActive = state != .idle || isOvertime
        pseudoContextRunStart = CoachPseudoProductivityGuard.updatedRunStart(
            previous: pseudoContextRunStart,
            category: frontmostCategory,
            sessionActive: sessionActive,
            now: now
        )
        guard let settings, settings.coachIdleStarterEnabled, settings.coachOnScreenPromptsEnabled,
              coachPanel == nil, !sessionActive,
              let runStart = pseudoContextRunStart,
              now.timeIntervalSince(runStart) >= TimeInterval(CoachPseudoProductivityGuard.minimumContextMinutes * 60),
              pseudoLastAskedAt.map({ now.timeIntervalSince($0) >= CoachPseudoProductivityGuard.askCooldown }) ?? true
        else { return false }
        // Cheap checks first: the store is only read after 20 minutes in a work context.
        reloadWeeklyPriorities(now: now)
        let snapshot = coachSnapshot(now: now, idleSeconds: 0, frontmostCategory: frontmostCategory)
        let priority = snapshot.topPriority
        let shouldAsk = CoachPseudoProductivityGuard.shouldAsk(.init(
            now: now,
            inGoodWindow: snapshot.inGoodWindow,
            sessionActive: sessionActive,
            pacing: snapshot.pacing,
            contextRunStart: pseudoContextRunStart,
            lastAskedAt: pseudoLastAskedAt,
            hasPriority: priority != nil
        ))
        guard shouldAsk, let priority else { return false }

        let calendarBusy = currentCalendarAvailability(now: now).isBusyNow
        let input = coachGuardrailInput(now: now, calendarBusy: calendarBusy, isIdlePrompt: true)
        guard coachGuardrails.verdict(for: .panel, input: input) == .allowed else { return false }

        var facts = snapshot.facts
        facts.contextMinutes = pseudoContextRunStart.map { Int(now.timeIntervalSince($0) / 60) }
        facts.contextAppName = contextName
        let pseudoSnapshot = CoachSnapshot(
            now: now,
            inGoodWindow: snapshot.inGoodWindow,
            tier: snapshot.tier,
            pacing: snapshot.pacing,
            facts: facts,
            target: snapshot.target,
            topPriority: priority,
            frontCategory: frontmostCategory
        )
        let style = settings.coachStyle
        let motivation = pickMotivation(situation: CoachSituation.isLateNight(now) ? .lateNight : .drift, now: now)
        let message = composeCoachMessage(trigger: .pseudoProductivity(priority: priority.title), style: style, snapshot: pseudoSnapshot, motivation: motivation)
        let attempt = coachEngine.recordDeliveredIntervention(
            kind: .quickPrompt,
            riskScore: 0,
            sessionId: nil,
            now: now,
            surface: .panel,
            style: style
        )
        if message.showsMotivation { noteMotivationShown(motivation, attemptID: attempt.id, at: now) }
        pseudoLastAskedAt = now
        presentCoachPanel(CoachPanelPresentation(
            kind: .pseudoProductivity,
            message: message,
            plan: snapshot.target,
            attemptID: attempt.id,
            contextName: contextName,
            createdAt: now
        ))
        return true
    }

    private func logPseudoAnswer(_ answer: CoachPseudoAnswer, panel: CoachPanelPresentation, now: Date = Date()) {
        guard panel.kind == .pseudoProductivity else { return }
        CoachPseudoWorkLog(defaults: defaults).append(CoachPseudoWorkEntry(
            answeredAt: now,
            answer: answer,
            contextName: panel.contextName,
            hourOfDay: Calendar.current.component(.hour, from: panel.createdAt),
            priorityTitle: panel.plan?.name ?? ""
        ))
        refreshBusyworkContexts()
        if let attemptID = panel.attemptID, let attempt = coachEngine.store.attempt(id: attemptID) {
            attempt.skipReasonRaw = answer == .sideQuest ? FocusCoachSkipReason.lowPriorityWork.rawValue : nil
            coachEngine.store.saveChanges()
        }
    }

    #if DEBUG
    /// FOCUSFLOW_DEBUG_COACH_PANEL=1: a real composed start nudge, shown without logging an attempt.
    /// FOCUSFLOW_DEBUG_PLAN: the plan card or a planned-start cue, composed from real data, not saved.
    func presentDebugPlanPanel(cue: Bool, now: Date = Date()) {
        reloadWeeklyPriorities(now: now)
        let snapshot = coachSnapshot(now: now, idleSeconds: 0, frontmostCategory: AppUsageTracker.shared.currentFrontmostCategory)
        let style = settings?.coachStyle ?? .challenger
        let motivation = pickMotivation(situation: Self.startSituation(facts: snapshot.facts, now: now), now: now)
        if cue {
            let context = CoachPlannedCueContext(
                timeLabel: Self.clockLabel(now), minutes: snapshot.target.minutes, priorityName: snapshot.target.name,
                missedYesterday: snapshot.facts.missedYesterday,
                starterMinutes: CoachStarterBlock.clampedMinutes(settings?.coachStarterBlockMinutes ?? CoachStarterBlock.defaultMinutes)
            )
            let message = composeCoachMessage(trigger: .plannedStart(context), style: style, snapshot: snapshot, motivation: motivation)
            log("debug: plan cue '\(message.hook)' / '\(message.detail?.text ?? "")' / '\(message.motivation?.text ?? "")'")
            presentCoachPanel(CoachPanelPresentation(kind: .plannedStart, message: message, plan: snapshot.target, footerHint: hotkeyFooterHint))
        } else {
            let slots = dailyPlanSuggestions(now: now)
            let message = composeCoachMessage(
                trigger: .dailyPlan(goalMinutes: snapshot.pacing.goalMinutes, firstSuggestion: slots.first?.label()),
                style: style, snapshot: snapshot, motivation: motivation
            )
            log("debug: plan card '\(message.hook)' slots=\(slots.map { $0.label() }) motivation='\(message.motivation?.text ?? "")'")
            presentCoachPanel(CoachPanelPresentation(kind: .dailyPlan, message: message, planSlots: slots))
        }
    }

    func presentDebugCoachPanel() {
        if let level = debugForcedDriftLevel {
            presentDebugRescuePanel(level: level)
            return
        }
        reloadWeeklyPriorities()
        let snapshot = coachSnapshot(idleSeconds: 30 * 60, frontmostCategory: AppUsageTracker.shared.currentFrontmostCategory)
        let message = composeCoachMessage(trigger: .startNudge, style: settings?.coachStyle ?? .challenger, snapshot: snapshot)
        log("debug: coach panel '\(message.hook)' / '\(message.detail?.text ?? "")' / '\(message.primaryTitle)'")
        presentCoachPanel(CoachPanelPresentation(kind: .startNudge, message: message, plan: snapshot.target))
    }
    #endif

    // MARK: - In-session drift check

    private func routeCoachDecision(_ decision: FocusCoachDecision) {
        guard let settings else { return }
        if isInReleaseWindow || shouldSuppressGuardianPopups(using: settings) {
            currentCoachQuickPromptDecision = nil
            hideCoachPanel()
            return
        }
        let mode = settings.coachInterventionMode
        let engagementMode = selectedProject?.guardianSensitivity.engagementMode ?? .adaptive
        let route = coachPlanner.routeActiveDecision(
            decision,
            mode: mode,
            riskScore: coachEngine.riskScore,
            strongShownCount: strongPromptsShownThisSession,
            maxStrongPrompts: settings.coachMaxStrongPromptsPerSession,
            allowSkipAction: settings.coachAllowSkipAction,
            engagementMode: engagementMode
        )
        guard route.quickPromptDecision != nil || route.strongWindowDecision != nil else { return }

        let now = Date()
        let input = coachGuardrailInput(now: now, calendarBusy: false, isIdlePrompt: false)
        guard coachGuardrails.verdict(for: .badge, input: input) == .allowed else {
            currentCoachQuickPromptDecision = nil
            return
        }
        let panelAllowed = settings.coachOnScreenPromptsEnabled
            && coachGuardrails.verdict(for: .panel, input: input) == .allowed

        let coachCtx = buildCoachContext(
            idleSeconds: 0,
            frontmostCategory: AppUsageTracker.shared.currentFrontmostCategory,
            frontmostDisplayLabel: AppUsageTracker.shared.currentFrontmostDisplayLabel
        )
        let app = AppUsageTracker.shared.currentFrontmostDisplayLabel
        let appSeconds = AppUsageTracker.shared.sessionDistractingEntries.first { $0.displayLabel == app }?.seconds
        let style = settings.coachStyle
        let message = CoachMessageComposer.compose(CoachComposerInput(
            style: style,
            trigger: .inSessionDrift(projectName: selectedProject?.name, appName: app, minutesInApp: appSeconds.map { $0 / 60 }),
            facts: CoachFacts(),
            target: CoachStartTarget(minutes: selectedMinutes, name: selectedProject?.name),
            whyLines: settings.coachMyWhyLines
        ))
        // Never offer the 5-minute restart inside a session (B1): back to it, or snooze.
        let base = (route.strongWindowDecision ?? route.quickPromptDecision)?.suggestedActions ?? [.returnNow, .snooze10m]
        let actions = appendBlockActionIfRecommended(
            actions: base.filter { $0 != .cleanRestart5m },
            context: coachCtx
        )

        if route.strongWindowDecision != nil, panelAllowed {
            let strong = FocusCoachDecision(kind: .strongPrompt, suggestedActions: actions, message: nil, context: coachCtx, composed: message)
            let attempt = coachEngine.recordDeliveredIntervention(
                kind: .strongPrompt,
                riskScore: coachEngine.riskScore,
                now: now,
                surface: .panel,
                style: style
            )
            if route.didConsumeStrongBudget {
                strongPromptsShownThisSession += 1
            }
            currentCoachQuickPromptDecision = nil
            presentCoachPanel(
                CoachPanelPresentation(kind: .inSessionDrift, message: message, attemptID: attempt.id),
                decision: strong
            )
        } else {
            currentCoachQuickPromptDecision = FocusCoachDecision(
                kind: .quickPrompt,
                suggestedActions: actions,
                message: nil,
                context: coachCtx,
                composed: message
            )
            coachEngine.recordDeliveredIntervention(
                kind: .quickPrompt,
                riskScore: coachEngine.riskScore,
                now: now,
                surface: .badge,
                style: style
            )
        }
    }

    // MARK: - Rescue loop: drift sampling

    /// Called by `AppUsageTracker` every tracking tick with the seconds since the last one.
    func recordDriftTick(elapsedSeconds: Int, now: Date = Date()) {
        guard state == .idle, !isOvertime, settings != nil else { return }
        let tracker = AppUsageTracker.shared
        let frontmost = driftFrontmostOverride ?? DriftFrontmost(
            bundleIdentifier: tracker.currentFrontmostBundleId,
            appName: tracker.currentFrontmostAppName,
            browserHost: tracker.currentFrontmostBrowserHost,
            displayName: tracker.currentFrontmostDisplayLabel,
            category: tracker.currentFrontmostCategory,
            switchesPerMinute: FocusCoachEngine.computeAppSwitchRate(switchTimestamps: tracker.recentAppSwitchTimestamps, windowSeconds: 60)
        )
        recordDriftSample(frontmost, seconds: elapsedSeconds, now: now)
    }

    /// Classifies one tick of `frontmost` and feeds it to the drift monitor.
    func recordDriftSample(_ frontmost: DriftFrontmost, seconds: Int, now: Date = Date()) {
        guard state == .idle, !isOvertime else { return }
        refreshCoachModelsIfNeeded(now: now)
        let keys = currentDriftRuleKeys(now: now)
        let kind = DriftMonitor.classify(
            bundleIdentifier: frontmost.bundleIdentifier,
            appName: frontmost.appName,
            browserHost: settings?.coachCollectRawDomains == true ? frontmost.browserHost : nil,
            displayName: frontmost.displayName,
            category: frontmost.category,
            confirmedKeys: keys.confirmed,
            allowedKeys: keys.allowed,
            pacingPressure: currentPacing(now: now).pressure,
            busyworkContexts: busyworkContexts,
            userAway: systemIdleSeconds() >= 5 * 60
        )
        driftMonitor.record(at: now, seconds: seconds, kind: kind, switchesPerMinute: frontmost.switchesPerMinute)
    }

    private func currentPacing(now: Date) -> CoachGoalPacing {
        CoachGoalPacing(
            goalMinutes: Int((settings?.dailyFocusGoal ?? 7200) / 60),
            doneMinutes: Int(todayFocusTime / 60),
            windowMinutesLeft: availabilityModel.goodWindowMinutesRemainingToday(from: now)
        )
    }

    private func currentDriftRuleKeys(now: Date) -> (confirmed: Set<String>, allowed: Set<String>) {
        if let cached = driftRuleKeys, now.timeIntervalSince(cached.loadedAt) < 300, cached.loadedAt <= now {
            return (cached.confirmed, cached.allowed)
        }
        var items: [IdleDistractionItem] = []
        if let modelContext {
            items = (try? modelContext.fetch(FetchDescriptor<IdleDistractionItem>())) ?? []
        }
        let keys = DerailerRuleKeys.from(items)
        driftRuleKeys = (keys.confirmed, keys.allowed, now)
        return keys
    }

    private func refreshBusyworkContexts() {
        let entries = CoachPseudoWorkLog(defaults: defaults).entries
        var byContext: [String: (sideQuests: Int, total: Int)] = [:]
        for entry in entries {
            guard let name = entry.contextName?.lowercased(), !name.isEmpty else { continue }
            byContext[name, default: (0, 0)].total += 1
            if entry.answer == .sideQuest { byContext[name, default: (0, 0)].sideQuests += 1 }
        }
        busyworkContexts = Set(byContext.filter { $0.value.total >= 2 && Double($0.value.sideQuests) / Double($0.value.total) >= 0.5 }.keys)
    }

    private func systemIdleSeconds() -> TimeInterval {
        if let systemIdleSecondsProvider { return systemIdleSecondsProvider() }
        guard let anyEvent = CGEventType(rawValue: ~0) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyEvent)
    }

    // MARK: - Rescue loop: decisions

    /// Rescues logged in the last 14 days, read back from their context keys.
    func rescueRecords(now: Date = Date()) -> [CoachRescueRecord] {
        coachEngine.store.attempts(deliveredSince: now.addingTimeInterval(-CoachPauseScreenPolicy.escapeLookback))
            .compactMap(CoachRescueRecord.init(attempt:))
    }

    /// The ambient menu bar counter: "YouTube 23m" / "Drift 23m" while drifting in a focus window.
    var driftMenuBarText: String? {
        guard settings?.coachShowDriftInMenuBar == true, state == .idle, !isOvertime,
              let drift = currentDrift else { return nil }
        return CoachDriftCounter.text(for: drift)
    }

    /// Runs every 15 s. Updates the drift level (menu bar counter) and, when the cadence allows,
    /// lets the bandit pick the rescue surface the level allows. Returns true when something was shown.
    @discardableResult
    func evaluateRescueLoop(now: Date = Date()) -> Bool {
        guard let settings else { return false }
        let sessionActive = state != .idle || isOvertime
        refreshCoachModelsIfNeeded(now: now)
        let window = CoachFocusWindow.current(now: now, model: availabilityModel)
        let pacing = currentPacing(now: now)
        let records = rescueRecords(now: now)
        let ignored = records.filter { $0.deliveredAt >= window.start && $0.surface != .ambient && $0.wasIgnored }.count
        let lastEnd = historyReader?.lastFocusSessionEnd(before: now)
        let assessment = driftMonitor.assess(.init(
            now: now,
            sessionActive: sessionActive,
            inLearnedWindow: availabilityModel.isGoodWindow(now),
            pacingPressure: pacing.pressure,
            windowStart: window.start,
            lastSessionEnd: lastEnd,
            ignoredRescues: ignored
        ))
        if currentDrift != assessment { currentDrift = assessment }
        currentFocusWindow = window

        guard settings.coachIdleStarterEnabled, assessment.isActive, assessment.level > .ok,
              coachPanel == nil, pauseScreen == nil,
              CoachRescueCadence.shouldDecide(level: assessment.level, baseLevel: assessment.baseLevel, windowStart: window.start, last: lastRescueDecision, now: now)
        else { return false }

        let calendarBusy = currentCalendarAvailability(now: now).isBusyNow
        var input = coachGuardrailInput(now: now, calendarBusy: calendarBusy, isIdlePrompt: true)
        input.ignorePanelSpacing = true
        if let reason = IdleStarterSuppressionReason(verdict: coachGuardrails.verdict(for: .badge, input: input)) {
            lastIdleStarterSuppressionReason = reason
            return false
        }

        let pauseVerdict = CoachPauseScreenPolicy.verdict(.init(
            enabled: settings.coachPauseScreenEnabled,
            level: assessment.level,
            windowStart: window.start,
            now: now,
            records: records,
            guardrails: input
        ))
        if pauseVerdict == .escapeRateTooHigh, !pauseScreenShutoffLogged {
            pauseScreenShutoffLogged = true
            let rate = CoachPauseScreenPolicy.escapeRate(records: records, now: now) ?? 0
            log("coach: pause screen switched off automatically, escape rate \(Int(rate * 100))% over 14 days (> 80%)")
        }
        let candidates = CoachRescueCadence.candidateSurfaces(
            level: assessment.level,
            panelEnabled: settings.coachOnScreenPromptsEnabled,
            pauseScreenAllowed: pauseVerdict == .allowed
        )
        let gated = coachGuardrails.allowedSurfaces(from: candidates, input: input)

        reloadWeeklyPriorities(now: now)
        let category = driftFrontmostOverride?.category ?? AppUsageTracker.shared.currentFrontmostCategory
        let snapshot = coachSnapshot(now: now, idleSeconds: assessment.ambientMinutes * 60, frontmostCategory: category)
        let baseKey = CoachContextKey(
            availability: snapshot.tier,
            idle: .init(idleSeconds: assessment.ambientMinutes * 60),
            front: .init(category: category),
            hasSessionToday: snapshot.facts.sessionsToday > 0
        )
        let level = assessment.level
        let arm: CoachArm
        if let forced = coachArmOverride, gated.surfaces.contains(forced.surface) {
            arm = forced
        } else {
            arm = banditPolicy.choose(
                contextFor: { baseKey.rescue(level: level, surface: CoachRescueSurface(coachSurface: $0.surface)).rawValue },
                surfaces: gated.surfaces,
                preferredStyle: settings.coachStyle,
                model: banditModel,
                using: &coachRandom
            )
        }
        lastRescueDecision = .init(level: level, at: now, windowStart: window.start, baseLevel: assessment.baseLevel)
        let spanLabel: String
        if let lastEnd, lastEnd > window.start {
            spanLabel = "since your last block"
        } else if let hour = window.hourLabel() {
            spanLabel = "in your \(hour) window"
        } else {
            spanLabel = "today"
        }
        return deliverRescue(arm: arm, assessment: assessment, snapshot: snapshot, baseKey: baseKey, spanLabel: spanLabel, now: now)
    }

    private func rescueContext(level: DriftLevel, signal: DriftSignal?, snapshot: CoachSnapshot, spanLabel: String, now: Date) -> CoachRescueContext? {
        let starterMinutes = CoachStarterBlock.clampedMinutes(settings?.coachStarterBlockMinutes ?? CoachStarterBlock.defaultMinutes)
        guard let ask = CoachRescueLadder.ask(level: level, target: snapshot.target, starterMinutes: starterMinutes) else { return nil }
        return CoachRescueContext(
            level: level,
            signal: signal,
            spanLabel: spanLabel,
            ask: ask,
            priorityName: snapshot.topPriority?.title ?? snapshot.target.name,
            lateNight: CoachSituation.isLateNight(now),
            starterMinutes: starterMinutes
        )
    }

    private func rescueSituation(level: DriftLevel, facts: CoachFacts, now: Date) -> CoachSituation {
        if CoachSituation.isLateNight(now) { return .lateNight }
        if level == .spiral { return .spiral }
        if (facts.daysWithoutBlock ?? 0) >= 2 { return .comeback }
        return .drift
    }

    @discardableResult
    private func deliverRescue(
        arm: CoachArm,
        assessment: DriftAssessment,
        snapshot: CoachSnapshot,
        baseKey: CoachContextKey,
        spanLabel: String,
        now: Date
    ) -> Bool {
        let level = assessment.level
        guard let rescue = rescueContext(level: level, signal: assessment.dominantSignal, snapshot: snapshot, spanLabel: spanLabel, now: now) else { return false }
        let surface = CoachRescueSurface(coachSurface: arm.surface)
        let contextKey = baseKey.rescue(level: level, surface: surface).rawValue

        switch surface {
        case .ambient:
            // Menu bar only: logged once per decision (for "Rescues by level"), never toward the cap.
            let attempt = coachEngine.recordDeliveredIntervention(
                kind: .quickPrompt, riskScore: Double(level.rawValue) / 3, sessionId: nil, now: now,
                surface: .silent, style: nil, contextKey: contextKey
            )
            if pendingCoachAttemptID == nil { pendingCoachAttemptID = attempt.id }
            lastIdleStarterSuppressionReason = .banditChoseSilent
            return false

        case .panel:
            guard let style = arm.style else { return false }
            let motivation = pickMotivation(situation: rescueSituation(level: level, facts: snapshot.facts, now: now), now: now)
            let usePseudoPanel: Bool = {
                guard level <= .lost, snapshot.topPriority != nil, case .pseudo = assessment.dominantSignal else { return false }
                return true
            }()
            let trigger: CoachTrigger = usePseudoPanel
                ? .pseudoProductivity(priority: snapshot.topPriority?.title ?? "")
                : .rescue(rescue)
            var facts = snapshot.facts
            if usePseudoPanel, let pseudo = assessment.topPseudo {
                facts.contextMinutes = assessment.pseudoMinutes
                facts.contextAppName = pseudo.name
            }
            let factsSnapshot = CoachSnapshot(
                now: now, inGoodWindow: snapshot.inGoodWindow, tier: snapshot.tier, pacing: snapshot.pacing,
                facts: facts, target: snapshot.target, topPriority: snapshot.topPriority, frontCategory: snapshot.frontCategory
            )
            let message = composeCoachMessage(trigger: trigger, style: style, snapshot: factsSnapshot, motivation: motivation)
            let attempt = coachEngine.recordDeliveredIntervention(
                kind: .strongPrompt, riskScore: Double(level.rawValue) / 3, sessionId: nil, now: now,
                surface: .panel, style: style, contextKey: contextKey
            )
            pendingCoachAttemptID = attempt.id
            if message.showsMotivation { noteMotivationShown(motivation, attemptID: attempt.id, at: now) }
            if usePseudoPanel { pseudoLastAskedAt = now }
            presentCoachPanel(CoachPanelPresentation(
                kind: usePseudoPanel ? .pseudoProductivity : .rescue,
                message: message,
                plan: rescue.ask.target ?? snapshot.target,
                attemptID: attempt.id,
                contextName: assessment.topPseudo?.name,
                createdAt: now,
                level: level,
                ask: rescue.ask,
                footerHint: hotkeyFooterHint
            ))
            lastIdleStarterSuppressionReason = nil
            return true

        case .pauseScreen:
            guard let style = arm.style else { return false }
            let motivation = pickMotivation(situation: CoachSituation.isLateNight(now) ? .lateNight : .spiral, now: now)
            let attempt = coachEngine.recordDeliveredIntervention(
                kind: .strongPrompt, riskScore: 1, sessionId: nil, now: now,
                surface: .strongWindow, style: style, contextKey: contextKey
            )
            pendingCoachAttemptID = attempt.id
            noteMotivationShown(motivation ?? nil, attemptID: attempt.id, at: now)
            presentPauseScreen(CoachPauseScreenPresentation(
                style: style,
                headline: motivation ?? nil,
                fact: rescue.longFact,
                starterMinutes: rescue.starterMinutes,
                attemptID: attempt.id,
                level: level,
                lateNight: rescue.lateNight,
                createdAt: now
            ))
            lastIdleStarterSuppressionReason = nil
            return true
        }
    }

    /// "⌃⌥Space starts 5 min anytime" while the shortcut is on.
    private var hotkeyFooterHint: String? {
        guard let settings, settings.coachGlobalHotkeyEnabled else { return nil }
        return CoachStarterBlock.hotkeyHint(minutes: CoachStarterBlock.clampedMinutes(settings.coachStarterBlockMinutes))
    }

    // MARK: - Rescue loop: quotes

    static func startSituation(facts: CoachFacts, now: Date) -> CoachSituation {
        if CoachSituation.isLateNight(now) { return .lateNight }
        if facts.missedYesterday && facts.sessionsToday == 0 { return .comeback }
        if facts.streakDays >= 3 { return .streak }
        return .start
    }

    /// The learner's quote or why line for `situation`. `.some(nil)`: everything was shown in the last 3 days.
    private func pickMotivation(situation: CoachSituation, now: Date) -> CoachMotivationItem?? {
        let log = CoachQuoteShowLog(defaults: defaults).entries
        var rewards: [UUID: Double] = [:]
        let ids = Set(log.compactMap(\.attemptID))
        if !ids.isEmpty {
            for attempt in coachEngine.store.attempts(deliveredSince: now.addingTimeInterval(-60 * 24 * 3600)) where ids.contains(attempt.id) {
                if let reward = attempt.reward { rewards[attempt.id] = reward }
            }
        }
        return .some(CoachQuotePicker.pick(
            situation: situation,
            style: settings?.coachStyle ?? .challenger,
            whyLines: settings?.coachMyWhyLines ?? [],
            log: log,
            rewards: rewards,
            now: now,
            using: &coachRandom
        ))
    }

    private func noteMotivationShown(_ motivation: CoachMotivationItem??, attemptID: UUID?, at now: Date) {
        guard let item = motivation ?? nil else { return }
        CoachQuoteShowLog(defaults: defaults).append(CoachQuoteShow(itemID: item.id, shownAt: now, attemptID: attemptID))
    }

    // MARK: - Coach v3: daily plan and planned-start cue

    /// Whether this store knows `PlannedBlock` (older test containers do not).
    private var plannedBlocksSupported: Bool?

    private func canUsePlannedBlocks() -> Bool {
        guard let modelContext else { return false }
        if let plannedBlocksSupported { return plannedBlocksSupported }
        let supported = modelContext.container.schema.entities.contains { $0.name == "PlannedBlock" }
        plannedBlocksSupported = supported
        return supported
    }

    /// Plans whose start is between `start` and `end`, earliest first.
    func plannedBlocks(from start: Date, to end: Date) -> [PlannedBlock] {
        guard canUsePlannedBlocks(), let modelContext else { return [] }
        let descriptor = FetchDescriptor<PlannedBlock>(
            predicate: #Predicate { $0.startAt >= start && $0.startAt <= end },
            sortBy: [SortDescriptor(\.startAt)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Today already has a decision: any plan for today, or one still ahead in the next 12 h.
    func hasPlanForToday(now: Date = Date()) -> Bool {
        let dayStart = Calendar.current.startOfDay(for: now)
        return plannedBlocks(from: dayStart, to: now.addingTimeInterval(12 * 3600)).contains { block in
            Calendar.current.isDate(block.day, inSameDayAs: now) || (block.status == .planned && block.startAt > now)
        }
    }

    /// The next plan still waiting (for the popover and companion).
    func nextPlannedBlock(now: Date = Date()) -> PlannedBlock? {
        plannedBlocks(from: now.addingTimeInterval(-CoachPlannedCue.lateStart), to: now.addingTimeInterval(24 * 3600))
            .first { $0.status == .planned }
    }

    /// Suggested start times for today's block (learned windows that are free in the calendar).
    func dailyPlanSuggestions(now: Date = Date()) -> [CoachPlanSlot] {
        refreshCoachModelsIfNeeded(now: now)
        let availability = currentCalendarAvailability(now: now)
        return CoachDailyPlanner.suggestions(
            now: now,
            model: availabilityModel,
            busy: availability.busyIntervals,
            quietStartMinute: settings?.coachQuietStartMinute ?? 30,
            quietEndMinute: settings?.coachQuietEndMinute ?? 420
        )
    }

    private var isStickyCoachPanelShowing: Bool {
        coachPanel?.kind == .plannedStart || coachPanel?.kind == .dailyPlan
    }

    /// Runs every coach tick (15 s). Shows the cue when a planned start time has come; marks
    /// plans missed once their start window passes. Returns true while a cue is on screen.
    @discardableResult
    func evaluatePlannedCue(now: Date = Date()) -> Bool {
        guard let settings, canUsePlannedBlocks(), state == .idle, !isOvertime, pauseScreen == nil else { return false }
        let due = plannedBlocks(from: now.addingTimeInterval(-24 * 3600), to: now).filter { $0.status == .planned }
        var changed = false
        defer { if changed { saveContext() } }
        for block in due {
            if coachPanel?.plannedBlockID == block.id { return true }
            let busy = currentCalendarAvailability(now: now).isBusyNow
            switch CoachPlannedCue.step(startAt: block.startAt, now: now, calendarBusy: busy) {
            case .notYet:
                continue
            case .expire:
                block.status = .missed
                changed = true
                log("coach plan: \(Self.clockLabel(block.startAt)) missed")
            case .waitForCalendar:
                return false
            case .cue:
                if shouldSuppressGuardianPopups(using: settings) { return false }
                presentPlannedCue(block, now: now)
                changed = true
                return true
            }
        }
        return false
    }

    private func presentPlannedCue(_ block: PlannedBlock, now: Date) {
        let snapshot = coachSnapshot(now: now, idleSeconds: 0, frontmostCategory: AppUsageTracker.shared.currentFrontmostCategory)
        let style = settings?.coachStyle ?? .challenger
        let starter = CoachStarterBlock.clampedMinutes(settings?.coachStarterBlockMinutes ?? CoachStarterBlock.defaultMinutes)
        var target = snapshot.target
        target.minutes = block.minutes
        if let title = block.title { target.name = title }
        if let priorityID = block.priorityID { target.priorityID = priorityID }
        if let projectID = block.projectID { target.projectID = projectID }
        let cue = CoachPlannedCueContext(
            timeLabel: Self.clockLabel(block.startAt),
            minutes: block.minutes,
            priorityName: target.name,
            pushes: block.pushes,
            missedYesterday: snapshot.facts.missedYesterday,
            starterMinutes: starter
        )
        let motivation = pickMotivation(situation: Self.startSituation(facts: snapshot.facts, now: now), now: now)
        let message = composeCoachMessage(trigger: .plannedStart(cue), style: style, snapshot: snapshot, motivation: motivation)
        let attempt = coachEngine.recordDeliveredIntervention(
            kind: .strongPrompt, riskScore: 0, sessionId: nil, now: now,
            surface: .panel, style: style, contextKey: CoachPlannedCue.contextKey(blockID: block.id)
        )
        pendingCoachAttemptID = attempt.id
        if message.showsMotivation { noteMotivationShown(motivation, attemptID: attempt.id, at: now) }
        block.cuedAt = now
        log("coach plan: cue \(cue.timeLabel) (pushes=\(block.pushes))")
        presentCoachPanel(CoachPanelPresentation(
            kind: .plannedStart,
            message: message,
            plan: target,
            attemptID: attempt.id,
            createdAt: now,
            footerHint: hotkeyFooterHint,
            plannedBlockID: block.id
        ))
    }

    /// Runs once a minute. Once a day, at a breakpoint, asks when today's block will be.
    @discardableResult
    func evaluateDailyPlanInvite(now: Date = Date()) -> Bool {
        guard let settings, canUsePlannedBlocks(), settings.coachOnScreenPromptsEnabled,
              settings.coachIdleStarterEnabled else { return false }
        let store = CoachDailyPlanInviteStore(defaults: defaults)
        var inviteLog = store.load(now: now)
        let availability = currentCalendarAvailability(now: now)
        let pacing = currentPacing(now: now)
        let input = CoachDailyPlanInvite.Input(
            now: now,
            hasPlanToday: hasPlanForToday(now: now),
            goalMet: pacing.tier == .goalMet,
            sessionActive: state != .idle || isOvertime,
            quietHours: CoachGuardrails.isQuietHours(now, start: settings.coachQuietStartMinute, end: settings.coachQuietEndMinute),
            calendarBusy: availability.isBusyNow,
            screenShare: shouldSuppressGuardianPopups(using: settings),
            released: isInReleaseWindow || (coachQuietUntil.map { $0 > now } ?? false),
            userIdleSeconds: systemIdleSeconds(),
            panelShowing: coachPanel != nil || pauseScreen != nil,
            log: inviteLog,
            hasSuggestions: true
        )
        guard CoachDailyPlanInvite.shouldInvite(input) else { return false }
        let slots = dailyPlanSuggestions(now: now)
        guard !slots.isEmpty else { return false }

        let snapshot = coachSnapshot(now: now, idleSeconds: 0, frontmostCategory: AppUsageTracker.shared.currentFrontmostCategory)
        let style = settings.coachStyle
        let motivation = pickMotivation(situation: Self.startSituation(facts: snapshot.facts, now: now), now: now)
        let message = composeCoachMessage(
            trigger: .dailyPlan(goalMinutes: pacing.goalMinutes, firstSuggestion: slots.first?.label()),
            style: style, snapshot: snapshot, motivation: motivation
        )
        let attempt = coachEngine.recordDeliveredIntervention(
            kind: .strongPrompt, riskScore: 0, sessionId: nil, now: now,
            surface: .panel, style: style, contextKey: CoachPlannedCue.inviteContextKey
        )
        if message.showsMotivation { noteMotivationShown(motivation, attemptID: attempt.id, at: now) }
        inviteLog.shown += 1
        inviteLog.lastShownAt = now
        store.save(inviteLog)
        log("coach plan: invite shown (\(slots.map { $0.label() }.joined(separator: ", ")))")
        presentCoachPanel(CoachPanelPresentation(
            kind: .dailyPlan,
            message: message,
            attemptID: attempt.id,
            createdAt: now,
            planSlots: slots
        ))
        return true
    }

    /// Commits a start time: creates the plan and confirms on screen. Used by the plan card,
    /// the popover chips and the companion.
    @discardableResult
    func commitDailyPlan(_ slot: CoachPlanSlot, now: Date = Date()) -> PlannedBlock? {
        guard canUsePlannedBlocks(), let modelContext else { return nil }
        reloadWeeklyPriorities(now: now)
        let top = weeklyPriorities.first { !$0.isDone }
        let block = PlannedBlock(
            startAt: slot.start,
            minutes: CoachDailyPlanner.blockMinutes(pacing: currentPacing(now: now)),
            title: top?.title,
            priorityID: top?.id,
            projectID: top?.projectID ?? selectedProject?.id
        )
        modelContext.insert(block)
        saveContext()
        if let panel = coachPanel, panel.kind == .dailyPlan {
            coachEngine.recordInterventionOutcome(.improved, attemptID: panel.attemptID)
            interventionActionTaken = true
        }
        log("coach plan: committed \(slot.label()) · \(block.minutes)m")
        presentCoachPanel(CoachPanelPresentation(
            kind: .notice,
            message: CoachComposedMessage(
                style: settings?.coachStyle ?? .challenger,
                trigger: .dailyPlan(goalMinutes: 0, firstSuggestion: nil),
                hook: "Planned: \(slot.label()) · \(block.minutes)m.",
                detail: .line("I'll be on screen at \(slot.label()). Be ready."),
                primaryTitle: "",
                hookIsFact: false
            ),
            createdAt: now
        ))
        return block
    }

    /// Moves a plan `minutes` later, or marks it missed past the push limit.
    func pushPlannedBlock(id: UUID, minutes: Int, now: Date = Date()) {
        guard let block = plannedBlocks(from: now.addingTimeInterval(-24 * 3600), to: now.addingTimeInterval(24 * 3600)).first(where: { $0.id == id }) else { return }
        if CoachPlannedCue.canPush(pushes: block.pushes) {
            block.startAt = CoachPlannedCue.pushed(startAt: block.startAt, now: now, minutes: minutes)
            block.pushes += 1
        } else {
            block.status = .missed
        }
        saveContext()
    }

    /// Skips or removes a plan (respected; never counted as ignored).
    func skipPlannedBlock(id: UUID, now: Date = Date()) {
        guard let block = plannedBlocks(from: now.addingTimeInterval(-24 * 3600), to: now.addingTimeInterval(24 * 3600)).first(where: { $0.id == id }) else { return }
        block.status = .skipped
        saveContext()
        if coachPanel?.plannedBlockID == id { hideCoachPanel() }
    }

    /// Starts a plan right now (popover "Start now").
    @discardableResult
    func startPlannedBlockNow(id: UUID, now: Date = Date()) -> Bool {
        guard let block = plannedBlocks(from: now.addingTimeInterval(-24 * 3600), to: now.addingTimeInterval(24 * 3600)).first(where: { $0.id == id }) else { return false }
        let target = CoachStartTarget(minutes: block.minutes, name: block.title, projectID: block.projectID, priorityID: block.priorityID)
        // Starting early still fulfils the plan: move it to now first.
        if !CoachPlannedCue.fulfills(startAt: block.startAt, sessionStart: now) { block.startAt = now }
        return startCoachPlan(target)
    }

    /// A focus block started: the closest plan in its start window is fulfilled.
    private func markPlannedBlockStarted(sessionID: UUID, at start: Date) {
        let candidates = plannedBlocks(
            from: start.addingTimeInterval(-CoachPlannedCue.lateStart),
            to: start.addingTimeInterval(CoachPlannedCue.earlyStart)
        ).filter { $0.status == .planned && CoachPlannedCue.fulfills(startAt: $0.startAt, sessionStart: start) }
        guard let block = candidates.min(by: { abs($0.startAt.timeIntervalSince(start)) < abs($1.startAt.timeIntervalSince(start)) }) else { return }
        block.status = .started
        block.sessionID = sessionID
        saveContext()
        log("coach plan: \(Self.clockLabel(block.startAt)) started")
    }

    /// "Done for today" also releases today's remaining plans.
    private func skipRemainingPlans(now: Date) {
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)) ?? now
        let remaining = plannedBlocks(from: now.addingTimeInterval(-CoachPlannedCue.lateStart), to: dayEnd).filter { $0.status == .planned }
        guard !remaining.isEmpty else { return }
        remaining.forEach { $0.status = .skipped }
        saveContext()
    }

    nonisolated static func clockLabel(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    // MARK: - Rescue loop: pause screen

    private func presentPauseScreen(_ presentation: CoachPauseScreenPresentation) {
        if coachPanel != nil { hideCoachPanel() }
        pauseScreen = presentation
        pauseScreenHost?.showPauseScreen(presentation)
    }

    /// Leaves the pause screen. Esc and ✕ are dismissals; "Real break · 15m" and "Done for today"
    /// are respected choices (snoozed). "Start N minutes" starts a starter block.
    @discardableResult
    func performPauseScreenExit(_ exit: CoachPauseScreenExit, now: Date = Date()) -> Bool {
        guard let screen = pauseScreen else { return false }
        pauseScreen = nil
        pauseScreenHost?.hidePauseScreen()
        switch exit {
        case .startStarter:
            return startStarterBlock(attemptID: screen.attemptID)
        case .escape, .close:
            if let id = screen.attemptID { coachEngine.recordInterventionOutcome(.dismissed, attemptID: id) }
        case .realBreak:
            if let id = screen.attemptID { coachEngine.recordInterventionOutcome(.snoozed, attemptID: id) }
            snoozeIdleCoach(minutes: CoachPauseScreenPresentation.realBreakMinutes, now: now)
        case .doneForToday:
            if let id = screen.attemptID { coachEngine.recordInterventionOutcome(.snoozed, attemptID: id) }
            enterDoneForToday(now: now)
            clearCoachPrompts()
        }
        return true
    }

    // MARK: - Rescue loop: starter block

    /// Starts a starter block: no project or priority, `coachStarterBlockMinutes` long (2–10),
    /// labelled "Starter". Returns false (with `startError`) when a session is already running.
    @discardableResult
    func startStarterBlock(attemptID: UUID? = nil) -> Bool {
        guard let settings else {
            startError = "Settings not loaded. Please restart the app."
            return false
        }
        guard state == .idle, !isOvertime else {
            startError = isOvertime ? "Complete the current session first." : "A session is already in progress."
            return false
        }
        let minutes = CoachStarterBlock.clampedMinutes(settings.coachStarterBlockMinutes)
        starterRestore = (selectedProject, customLabel, pendingPriorityID)
        selectedProject = nil
        customLabel = CoachStarterBlock.label
        pendingIntentText = ""
        pendingPriorityID = nil
        starterStepText = ""
        nextStartDurationOverride = TimeInterval(minutes * 60)
        isStarterBlock = true
        guard startFocus() else {
            nextStartDurationOverride = nil
            endStarterState()
            return false
        }
        if let attemptID { coachEngine.recordInterventionOutcome(.improved, attemptID: attemptID) }
        return true
    }

    /// ⌃⌥Space: starts a starter block from anywhere. Does nothing while a session runs.
    @discardableResult
    func startStarterFromHotkey() -> Bool {
        guard state == .idle, !isOvertime, settings != nil else { return false }
        let attemptID = pauseScreen?.attemptID ?? coachPanel?.attemptID
        if pauseScreen != nil {
            pauseScreen = nil
            pauseScreenHost?.hidePauseScreen()
        }
        guard startStarterBlock(attemptID: attemptID) else { return false }
        let minutes = Int(totalSeconds / 60)
        presentCoachPanel(CoachPanelPresentation(
            kind: .notice,
            message: CoachMessageComposer.compose(CoachComposerInput(
                style: settings?.coachStyle ?? .challenger,
                trigger: .starterStarted(minutes: minutes),
                facts: CoachFacts(),
                target: CoachStartTarget(minutes: minutes, name: nil)
            ))
        ))
        return true
    }

    /// Registers or unregisters ⌃⌥Space to match `coachGlobalHotkeyEnabled`.
    func syncGlobalHotkey() {
        guard let registrar = hotkeyRegistrar else { return }
        let wanted = settings?.coachGlobalHotkeyEnabled == true
        if wanted {
            registrar.onPress = { [weak self] in self?.startStarterFromHotkey() }
            if !registrar.isRegistered {
                let ok = registrar.register()
                log("coach: global shortcut ⌃⌥Space \(ok ? "registered" : "failed to register")")
            }
        } else if registrar.isRegistered {
            registrar.unregister()
            log("coach: global shortcut ⌃⌥Space unregistered")
        }
    }

    /// Restores the selection the starter block replaced.
    private func endStarterState() {
        guard isStarterBlock || starterRestore != nil else { return }
        isStarterBlock = false
        if let restore = starterRestore {
            selectedProject = restore.project
            customLabel = restore.customLabel == CoachStarterBlock.label ? "" : restore.customLabel
            pendingPriorityID = restore.priorityID
        } else if customLabel == CoachStarterBlock.label {
            customLabel = ""
        }
        starterRestore = nil
    }

    /// A starter block finished: it counts as a completed block, then the panel offers
    /// "Keep going: 20m on {step}?" (no session-complete window).
    private func completeStarterBlock(_ session: FocusSession, now: Date = Date()) {
        timer?.invalidate()
        timer = nil
        let step = starterStepText.trimmingCharacters(in: .whitespacesAndNewlines)
        session.endedAt = now
        session.completed = true
        session.pauseCount = pauseCountThisSession
        session.intentText = step.isEmpty ? nil : step
        saveContext()
        clearCrashRecoveryState()
        creditCoachPromptForCompletion(sessionID: session.id)
        lastCompletedSession = session
        lastCompletedFocusSession = session
        lastCompletionWasBreak = false
        lastCompletedDuration = session.duration
        lastCompletedLabel = session.label
        coachEngine.endSession()
        currentSession = nil
        state = .idle
        isOvertime = false
        overtimeSeconds = 0
        remainingSeconds = 0
        totalSeconds = 0
        AppUsageTracker.shared.syncCadence(isFocusing: false)
        deactivateBlocking()
        endStarterState()
        starterStepText = ""
        loadTodayStats()
        if !isEvidenceMode { NSSound(named: NSSound.Name(settings?.completionSound ?? "Glass"))?.play() }
        presentCoachPanel(CoachPanelPresentation(
            kind: .keepGoing,
            message: keepGoingMessage(step: step.isEmpty ? nil : step, now: now),
            createdAt: now,
            step: step.isEmpty ? nil : step
        ))
    }

    private func keepGoingMessage(step: String?, now: Date) -> CoachComposedMessage {
        let motivation = pickMotivation(situation: .keepGoing, now: now)
        noteMotivationShown(motivation, attemptID: nil, at: now)
        var input = CoachComposerInput(
            style: settings?.coachStyle ?? .challenger,
            trigger: .keepGoing(step: step),
            facts: CoachFacts(),
            target: CoachStartTarget(minutes: CoachStarterBlock.keepGoingMinutes, name: step)
        )
        input.starterMinutes = CoachStarterBlock.clampedMinutes(settings?.coachStarterBlockMinutes ?? CoachStarterBlock.defaultMinutes)
        input.pickedDetail = (motivation ?? nil)?.detail(starterMinutes: input.starterMinutes)
        input.pickerExhausted = (motivation ?? nil) == nil
        return CoachMessageComposer.compose(input)
    }

    /// "Keep going": a normal 20-minute block whose intent is the step typed in the starter.
    @discardableResult
    func continueAfterStarter(step: String?) -> Bool {
        let trimmed = step?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        pendingIntentText = trimmed
        let preferred = selectedMinutes
        selectedMinutes = CoachStarterBlock.keepGoingMinutes
        let started = startFocus()
        selectedMinutes = preferred
        if !started { pendingIntentText = "" }
        return started
    }

    // MARK: - Rescue loop: momentum ramp

    /// Five minutes into a rescue-started block shorter than 25 minutes: "You're in. Make it 25?" once.
    @discardableResult
    func checkMomentumRamp() -> Bool {
        guard let sessionID = currentSession?.id, sessionID == rescueStartedSessionID,
              coachPanel == nil,
              CoachMomentumRamp.shouldOffer(
                isRescueStart: true,
                isStarter: isStarterBlock,
                elapsedSeconds: totalSeconds - remainingSeconds,
                totalSeconds: totalSeconds,
                alreadyOffered: momentumOfferedSessionID == sessionID
              ) else { return false }
        momentumOfferedSessionID = sessionID
        if let settings, shouldSuppressGuardianPopups(using: settings) { return false }
        presentCoachPanel(CoachPanelPresentation(
            kind: .momentum,
            message: CoachMessageComposer.compose(CoachComposerInput(
                style: settings?.coachStyle ?? .challenger,
                trigger: .momentum,
                facts: CoachFacts(),
                target: CoachStartTarget(minutes: CoachMomentumRamp.targetMinutes, name: nil)
            ))
        ))
        return true
    }

    #if DEBUG
    /// FOCUSFLOW_DEBUG_PAUSE_SCREEN=1: the real composed pause screen, without logging an attempt.
    func presentDebugPauseScreen() {
        let now = Date()
        let drift = currentDrift
        var signal = drift?.dominantSignal
        if signal == nil {
            signal = .derailer(name: AppUsageTracker.shared.currentFrontmostDisplayLabel ?? "YouTube", minutes: drift?.derailerWindowMinutes ?? 0)
        }
        let snapshot = coachSnapshot(now: now, idleSeconds: 0, frontmostCategory: AppUsageTracker.shared.currentFrontmostCategory)
        let window = CoachFocusWindow.current(now: now, model: availabilityModel)
        let span = window.hourLabel().map { "in your \($0) window" } ?? "today"
        guard let rescue = rescueContext(level: .spiral, signal: signal, snapshot: snapshot, spanLabel: span, now: now) else { return }
        let motivation = pickMotivation(situation: rescue.lateNight ? .lateNight : .spiral, now: now)
        let presentation = CoachPauseScreenPresentation(
            style: settings?.coachStyle ?? .challenger,
            headline: motivation ?? nil,
            fact: rescue.longFact,
            starterMinutes: rescue.starterMinutes,
            attemptID: nil,
            lateNight: rescue.lateNight,
            createdAt: now
        )
        log("debug: pause screen '\(presentation.accessibilityText)'")
        presentPauseScreen(presentation)
    }

    /// FOCUSFLOW_DEBUG_COACH_PANEL=1 with FOCUSFLOW_DEBUG_DRIFT_LEVEL=<1|2|3>: the rescue panel at that level.
    func presentDebugRescuePanel(level: DriftLevel) {
        let now = Date()
        reloadWeeklyPriorities()
        let snapshot = coachSnapshot(now: now, idleSeconds: 30 * 60, frontmostCategory: AppUsageTracker.shared.currentFrontmostCategory)
        let window = CoachFocusWindow.current(now: now, model: availabilityModel)
        let span = window.hourLabel().map { "in your \($0) window" } ?? "today"
        let signal = currentDrift?.dominantSignal ?? .derailer(
            name: AppUsageTracker.shared.currentFrontmostDisplayLabel ?? "YouTube",
            minutes: [DriftLevel.drifting: 12, .lost: 24, .spiral: 47][level] ?? 12
        )
        guard let rescue = rescueContext(level: level, signal: signal, snapshot: snapshot, spanLabel: span, now: now) else { return }
        let motivation = pickMotivation(situation: rescueSituation(level: level, facts: snapshot.facts, now: now), now: now)
        let message = composeCoachMessage(trigger: .rescue(rescue), style: settings?.coachStyle ?? .challenger, snapshot: snapshot, motivation: motivation)
        log("debug: rescue panel L\(level.rawValue) '\(message.hook)' / '\(message.detail?.text ?? "")' / '\(message.primaryTitle)'")
        presentCoachPanel(CoachPanelPresentation(
            kind: .rescue, message: message, plan: rescue.ask.target ?? snapshot.target, createdAt: now,
            level: level, ask: rescue.ask, footerHint: hotkeyFooterHint
        ))
    }

    /// Evidence renders: a running starter block with a typed step, without timers.
    func seedEvidenceStarterState(step: String, minutes: Int = 5, remaining: TimeInterval = 3 * 60 + 12) {
        selectedProject = nil
        customLabel = CoachStarterBlock.label
        isStarterBlock = true
        starterStepText = step
        totalSeconds = TimeInterval(minutes * 60)
        remainingSeconds = remaining
        state = .focusing
    }

    /// Evidence renders and tests: sets the drift assessment directly.
    func seedDriftAssessment(_ assessment: DriftAssessment?) {
        currentDrift = assessment
    }
    #endif

    // MARK: - Coach helpers

    private func currentIdleDistractionTarget() -> IdleDistractionCatalog.Target? {
        if let browserHost = AppUsageTracker.shared.currentFrontmostBrowserHost {
            return .website(browserHost)
        }
        if let bundleIdentifier = AppUsageTracker.shared.currentFrontmostBundleId {
            return .app(bundleIdentifier)
        }
        return nil
    }

    private func loadIdleDistractionCatalog() -> IdleDistractionCatalog {
        guard let modelContext else {
            return IdleDistractionCatalog(items: [])
        }
        let descriptor = FetchDescriptor<IdleDistractionItem>()
        let items = (try? modelContext.fetch(descriptor)) ?? []
        return IdleDistractionCatalog(items: items)
    }

    private func appendBlockActionIfRecommended(
        actions: [FocusCoachQuickAction],
        context: FocusCoachContext
    ) -> [FocusCoachQuickAction] {
        guard context.hasBlockRecommendation else { return actions }
        if actions.contains(.blockForProject) { return actions }
        return actions + [.blockForProject]
    }

    private func applyGuardianReleaseIfNeeded(for action: FocusCoachQuickAction, reason: FocusCoachSkipReason?) {
        guard action == .snooze10m || action == .skipCheck else { return }
        guard let mappedReason = explicitOptOutReason(for: reason) else { return }
        enterRelease(reason: mappedReason)
    }

    private func explicitOptOutReason(for reason: FocusCoachSkipReason?) -> ExplicitOptOutReason? {
        guard let reason else { return nil }
        switch reason {
        case .doneForToday:
            return .offDuty
        case .notWell, .justTired:
            return .tooTired
        case .takingBreak:
            return .realBreak
        case .urgentTask, .inMeeting:
            return .meeting
        case .lowPriorityWork, .procrastinating, .cantFocus:
            return .doneForNow
        }
    }

    private func shouldSuppressGuardianPopups(using settings: AppSettings) -> Bool {
        screenShareGuard.shouldSuppressGuardianPopups(
            enabled: settings.coachSuppressPopupsDuringScreenShare
        )
    }

    private func applyProjectBlockRecommendation() {
        guard let target = activeCoachInterventionDecision?.context?.suggestedBlockTarget
            ?? currentCoachQuickPromptDecision?.context?.suggestedBlockTarget
            ?? currentIdleStarterDecision?.context?.suggestedBlockTarget else { return }
        guard let project = selectedProject else { return }
        let isAppTarget = target.lowercased().hasPrefix("app:")
        let appBundleTarget = isAppTarget
            ? AppUsageEntry.appBundleID(fromRecommendationTarget: target)
            : nil

        if project.effectiveBlockProfiles.isEmpty {
            let profile = BlockProfile(
                name: "\(project.name) Guard",
                websites: isAppTarget ? [] : [target],
                apps: appBundleTarget.map { [$0] } ?? []
            )
            modelContext?.insert(profile)
            project.blockProfile = profile
            project.blockProfiles = [profile]
            saveContext()
            if state == .focusing || state == .paused {
                deactivateBlocking()
                activateBlocking()
            }
            return
        }

        let profile: BlockProfile
        if let existing = project.effectiveBlockProfiles.first {
            profile = existing
            if project.blockProfile == nil {
                project.blockProfile = existing
            }
        } else {
            return
        }

        if isAppTarget, let appTarget = appBundleTarget {
            var apps = profile.blockedApps
            if apps.contains(appTarget) { return }
            apps.append(appTarget)
            profile.blockedApps = apps
        } else {
            var websites = profile.blockedWebsites
            if websites.contains(target) { return }
            websites.append(target)
            profile.blockedWebsites = websites
        }
        saveContext()
        if state == .focusing || state == .paused {
            deactivateBlocking()
            activateBlocking()
        }
    }

    private func currentCalendarAvailability(now: Date) -> CalendarAvailability {
        if let calendarAvailabilityProvider {
            return calendarAvailabilityProvider(now)
        }
        return CalendarService.shared.availability(
            at: now,
            excludingCalendarId: settings?.selectedCalendarId,
            excludingCalendarName: settings?.calendarName
        )
    }

    /// Seconds since the most recent focus session ended, from the store; nil when none.
    private func secondsSinceLastFocusSessionEnd(now: Date = Date()) -> Int? {
        guard let modelContext else { return nil }
        var descriptor = FetchDescriptor<FocusSession>(
            predicate: #Predicate { $0.endedAt != nil },
            sortBy: [SortDescriptor(\.endedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 20
        guard let sessions = try? modelContext.fetch(descriptor),
              let lastEnd = sessions.first(where: { $0.type == .focus })?.endedAt else { return nil }
        return max(0, Int(now.timeIntervalSince(lastEnd)))
    }

    // MARK: - Coach Context Builder

    /// Builds a personalised `FocusCoachContext` snapshot from current state.
    /// Called whenever an intervention decision is routed to the window.
    private func buildCoachContext(
        idleSeconds: Int,
        frontmostCategory: AppUsageEntry.AppCategory,
        frontmostDisplayLabel: String?
    ) -> FocusCoachContext {
        let hour = Calendar.current.component(.hour, from: Date())
        let shouldUseDomainEntriesForCoachContext = settings?.coachCollectRawDomains == true

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
                entriesToday = shouldUseDomainEntriesForCoachContext
                    ? entries
                    : entries.filter { !$0.bundleIdentifier.lowercased().hasPrefix("domain:") }
                let topDistracting = entriesToday
                    .filter {
                        let host = CompanionAnalyticsBuilder.validPersistedDomainHost(for: $0.bundleIdentifier)
                        return AppUsageEntry.classify(
                            bundleIdentifier: $0.bundleIdentifier,
                            appName: $0.appName,
                            browserHost: host
                        ) == .distracting
                    }
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
            frontmostAppName: frontmostDisplayLabel,
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
            frontmostAppName: frontmostDisplayLabel,
            frontmostBundleIdentifier: AppUsageTracker.shared.currentFrontmostBundleId,
            frontmostDisplayLabel: frontmostDisplayLabel,
            frontmostDomainLabel: AppUsageTracker.shared.currentFrontmostDomainLabel,
            frontmostAppCategory: appCategory,
            isInActiveSession: isInActiveSession,
            todayFocusSeconds: todayFocusTime,
            dailyGoalSeconds: settings?.dailyFocusGoal ?? 7200,
            todaySessionCount: todaySessionCount,
            selectedProjectName: selectedProject?.name,
            selectedWorkMode: selectedProject?.workMode,
            hourOfDay: hour,
            topDistractingAppName: topDistractingName,
            topDistractingAppMinutes: topDistractingMinutes,
            recentLowPriorityWorkCount: coachEngine.recentLowPrioritySkipCount(),
            suggestedBlockTarget: recommendation?.target,
            blockRecommendationReason: recommendation?.reason,
            inReleaseWindow: isInReleaseWindow,
            secondsSinceLastFocusSession: secondsSinceLastFocusSessionEnd()
        )
    }
}
