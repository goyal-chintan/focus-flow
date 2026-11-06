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
    /// Coach v4 §3.2: no keyboard or mouse input in the last 90 s.
    case userAway
    /// Coach audit 2026-10-30: outside the own-work windows the user declared.
    case outsideOwnWorkWindow

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
        case .userAway: return "Nobody at the desk (no input in 90 s)"
        case .outsideOwnWorkWindow: return "Outside your own-work windows"
        }
    }

    /// The coach journal's reason code.
    var journalCode: CoachJournal.Code {
        switch self {
        case .releaseWindowActive: .released
        case .screenShareSuppressed: .screenShare
        case .antiProcrastinationDisabled, .idleStarterDisabled: .disabled
        case .cooldownActive: .cooldown
        case .snoozed: .snoozed
        case .quietHours: .quietHours
        case .outsideFocusWindow: .outsideWindow
        case .onTrack: .onTrack
        case .banditChoseSilent: .control
        case .calendarBusy: .calendarBusy
        case .dailyPromptCapReached: .dailyCap
        case .strongPromptSpacing: .panelSpacing
        case .userAway: .away
        case .outsideOwnWorkWindow: .outsideOwnWindow
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
    /// Both overtime kinds share `state == .idle` + `isOvertime`; only these two tell them apart,
    /// so a break that runs over is never shown or counted as a block's overtime.
    var isFocusOvertime: Bool { isOvertime && !lastCompletionWasBreak }
    /// True when the completed session was a break (break ran past its duration).
    var isBreakOvertime: Bool { isOvertime && lastCompletionWasBreak }

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
                    self?.showCompletionWindow()
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
    /// Weekly priorities stay in the store for history but no longer drive the coach or the UI.
    static let weeklyPrioritiesRetired = true
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
    /// A memo for `goalProgressSeconds`, which views call while drawing. Not observed: writing an
    /// observed property from a view's body re-invalidates it inside layout, and AppKit kills the app
    /// ("needs another Update Constraints pass"; crash 2026-10-28, macOS 26.2).
    @ObservationIgnored private var goalProgressCache: (at: Date, focusTime: TimeInterval, seconds: TimeInterval)?
    /// Test hook: seconds since the last keyboard/mouse input. Nil reads the system.
    var systemIdleSecondsProvider: (() -> TimeInterval)?
    /// Coach v5: Thompson-sample the block size at a real ask. Tests switch it off for determinism.
    var coachExploreSizes = true
    /// Coach v4 §3.1: every coach decision in plain words (release builds too). FocusFlowApp
    /// points it at Application Support; tests keep it in memory.
    var coachJournal = CoachJournal(fileURL: nil)
    /// Coach v4 §3.2: notices the user coming back to the desk (a breakpoint).
    private var arrivalDetector = CoachPresence.ArrivalDetector()
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

    /// Distracting apps/domains detected during the last completed focus session (for post-session review).
    var lastSessionDistractingEntries: [AppUsageTracker.SessionDistractingEntry] = []
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
        migrateCheckboxKeyResults()
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
        scheduleReminderSync() // a new day: today's reminders become today's tasks
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
                session.endedAt = session.startedAt.addingTimeInterval(elapsed)
                noteBlockEnded(session)
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
        // The banner can outlive its moment: a block started from a coach prompt or the
        // notification while it was up. Resuming then would swap out the running session and
        // force `.paused` while that block's timer keeps ticking — the popover sticks on Paused.
        guard state == .idle, !isOvertime, currentSession == nil else {
            log("resumeFromRecovery: a session is already running (state=\(state)), dropping stale recovery")
            supersedePendingRecovery()
            return
        }
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

    /// A new block replaced the session the recovery banner offered: close that session the way
    /// orphan cleanup would and hide the banner. The UserDefaults checkpoint is left alone — it
    /// now belongs to the running block.
    private func supersedePendingRecovery() {
        guard let recovery = recoveryState else { return }
        recoveryState = nil
        recoveryProject = nil
        let sessionId = recovery.sessionId
        let descriptor = FetchDescriptor<FocusSession>(predicate: #Predicate { $0.id == sessionId })
        guard let session = try? modelContext?.fetch(descriptor).first,
              session !== currentSession, session.endedAt == nil else { return }
        let elapsed = max(0, recovery.totalSeconds - recovery.remainingSeconds)
        if session.type == .focus && elapsed < Self.minimumRetainedFocusSeconds {
            session.endedAt = session.startedAt.addingTimeInterval(elapsed + session.totalPausedSeconds)
            noteBlockEnded(session)
            modelContext?.delete(session)
        } else {
            session.endedAt = session.startedAt.addingTimeInterval(elapsed + session.totalPausedSeconds)
            session.completed = false
        }
        saveContext()
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
            noteBlockEnded(session)
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
        // Starting fresh answers a pending crash-recovery banner; it must not resurface later.
        supersedePendingRecovery()
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
        // A task picked for another project never rides along (review 2026-10-30).
        dropPendingTaskOutsideProject()
        // Intent capture (Coach v2 §9 step 2): optional, one line, never blocks the start.
        let intent = pendingIntentText.trimmingCharacters(in: .whitespacesAndNewlines)
        session.intentText = intent.isEmpty ? nil : intent
        session.priorityID = pendingPriorityID
        session.taskID = pendingTaskID
        pendingTaskID = nil
        pendingIntentText = ""
        lastPrefilledIntent = nil
        modelContext?.insert(session)
        currentSession = session
        if let project = selectedProject {
            settings?.lastUsedProjectId = project.id.uuidString
        }
        saveContext() // Persist session immediately — crash safety
        let promptAttemptID = creditCoachPromptForStart(sessionID: session.id, minutes: Int(duration / 60))
        recordBlockStart(session, promptAttemptID: promptAttemptID)
        markPlannedBlockStarted(sessionID: session.id, at: session.startedAt)
        saveCrashRecoveryCheckpoint() // Write initial recovery state to UserDefaults
        startTimer()
        // Focus Coach: start session tracking
        pauseCountThisSession = 0
        strongPromptsShownThisSession = 0
        lastIdleInterventionAt = nil
        clearCoachPrompts()
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
    func switchProject(to newProject: Project?) {
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
            noteWakeRecoveredCompletion(session)
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

            noteWakeRecoveredCompletion(session)
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

    /// The session a wake recovery resolved becomes the last completion. A break is never the
    /// last focus block (the block-end window, earned break and "Last earned block" read that),
    /// and its episode ends where the recovery ended it, not at the live clock.
    private func noteWakeRecoveredCompletion(_ session: FocusSession) {
        lastCompletedSession = session
        lastCompletionWasBreak = (session.type != .focus)
        if session.type == .focus {
            lastCompletedDuration = session.duration
            lastCompletedLabel = session.label
            lastCompletedFocusSession = session
        } else {
            breakEpisodeContext?.breakEnded = session.endedAt
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
                    self?.showCompletionWindow()
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
        // Every break is started with its length (earned, or 5 minutes); the old short/long break
        // settings are no longer shown and only back this fallback.
        let sessionsPerCycle = max(1, settings.sessionsBeforeLongBreak)
        let isLongBreak = overrideDuration == nil
            && completedFocusSessions > 0
            && (completedFocusSessions % sessionsPerCycle) == 0
        let type: SessionType = isLongBreak ? .longBreak : .shortBreak
        let duration = overrideDuration ?? (isLongBreak ? settings.longBreakDuration : settings.shortBreakDuration)

        totalSeconds = duration
        remainingSeconds = duration
        isBreakPaused = false
        state = .onBreak(type)
        AppUsageTracker.shared.syncCadence(isFocusing: false)

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
            // A break paused for sleep is over now; left set, the next break would start "paused".
            isBreakPaused = false

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
                self?.showCompletionWindow()
            }
            return
        }

        // A break that ran over kept running over while the Mac slept (you were away either way).
        // Its counter restarts whatever the auto-resume setting, which is about focus blocks.
        if isBreakOvertime {
            overtimeSeconds += max(0, Int(sleepDuration))
            startTimer()
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

    /// Sets the running block to `minutes` (time already worked is kept) and, from 15 up, makes it
    /// your regular length for the blocks after it (Settings ▸ Focus ▸ Your usual block). A 5- or 15-minute
    /// warm-up can grow into a 25 in place; the next "Start" then offers 25, not the warm-up again.
    /// 5 is the coach's warm-up size: shrinking to it is this block only, so it never repeats.
    @discardableResult
    func setBlockLength(minutes: Int) -> Bool {
        guard canSetBlockLength(minutes) else { return false }
        let delta = TimeInterval(minutes * 60) - totalSeconds
        remainingSeconds += delta
        totalSeconds += delta
        currentSession?.duration += delta
        if minutes >= Self.smallestRegularMinutes, minutes != regularMinutes {
            // Said out loud, with Undo: this changes Settings ▸ Your usual block.
            let note = UsualLengthChange(minutes: minutes, previous: regularMinutes)
            usualLengthChange = note
            selectedMinutes = minutes
            settings?.focusDuration = TimeInterval(minutes * 60)
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(6))
                if self?.usualLengthChange == note { self?.usualLengthChange = nil }
            }
        }
        saveContext()
        saveCrashRecoveryCheckpoint()
        return true
    }

    /// A running (or paused) normal block can take `minutes` when at least a minute would be left.
    /// Starter blocks keep their own short shape.
    func canSetBlockLength(_ minutes: Int) -> Bool {
        guard state == .focusing || state == .paused, !isOvertime, !isStarterBlock else { return false }
        let target = TimeInterval(minutes * 60)
        guard target <= Self.maxSessionSeconds, target != totalSeconds else { return false }
        return target - (totalSeconds - remainingSeconds) >= 60
    }

    static let smallestRegularMinutes = 15

    struct UsualLengthChange: Equatable {
        let id = UUID()
        let minutes: Int
        let previous: Int
    }

    /// "25 min is now your usual block · Undo", for a few seconds after the Length row changed it.
    private(set) var usualLengthChange: UsualLengthChange?

    /// Puts the usual length back (the running block keeps the length you chose).
    func undoUsualLengthChange() {
        guard let change = usualLengthChange else { return }
        usualLengthChange = nil
        selectedMinutes = change.previous
        settings?.focusDuration = TimeInterval(change.previous * 60)
        saveContext()
    }

    /// The running block's planned length in whole minutes.
    var blockLengthMinutes: Int { Int((totalSeconds / 60).rounded()) }

    func resume() {
        guard state == .paused else { return }
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
        lastSessionDistractingEntries = []
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
            noteBlockEnded(session)
            // Keep only meaningful focus sessions in history (the start record stays).
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
    /// can record the achievement and splits before the session is finalised.
    /// Only used when the session is long enough to be worth reflecting on (≥60s).
    func stopForReflection() {
        log("stopForReflection called, currentSession=\(currentSession != nil)")
        guard let session = currentSession else {
            stop()   // nothing to save
            return
        }
        // A break is not a block to log: finishing one just ends it (never a "block done" window).
        guard session.type == .focus else {
            stop()
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

        showSessionComplete = true
        closePopover()
        DispatchQueue.main.async { [weak self] in
            self?.showCompletionWindow()
        }
        log("stopForReflection: showSessionComplete=\(showSessionComplete), openCompletionWindow called")
    }

    /// Called from SessionCompleteWindow "Discard" button after a manual stop.
    /// Deletes the session that was provisionally saved by stopForReflection().
    func discardManualStop() {
        if let session = lastCompletedSession {
            noteBlockEnded(session)
            modelContext?.delete(session)
            saveContext()
        }
        isManualStop = false
        showSessionComplete = false
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
        clearCoachPrompts()
        idleStarterSummary = nil
        idleStarterRecommendedMinutes = nil
        strongPromptsShownThisSession = 0
        lastIdleInterventionAt = nil
        coachEngine.endSession()
        clearCrashRecoveryState()
        suppressionWindow = nil
        if let session = currentSession {
            session.endedAt = Date()
            noteBlockEnded(session)
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

    /// Clears completedBlockContext after the day-close summary is archived/dismissed.
    /// This is one of the three permitted clear sites.
    func clearCompletedBlockContextAfterDayClose() {
        completedBlockContext = nil
        breakEpisodeContext = nil
        suppressionWindow = nil
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

        let adaptationMinutes = BreakAdaptation.minutes(recent.map {
            BreakAdaptation.Event(returnedToFocus: $0.returnedToFocus, endedEarly: $0.endedEarly, overrunSeconds: $0.overrunSeconds, reason: $0.overrunReason)
        })

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
            overrunSeconds: overrunSeconds,
            overrunReason: overrunSeconds >= BreakOverrunReason.askAfterSeconds ? breakOverrunReason : nil
        )

        choseSuggestedBreakCurrentEpisode = false
        breakOverrunReason = nil
    }

    /// The answer to "What happened?" in the break-over window (coach v6 §3.4), stored on the
    /// break when it ends.
    var breakOverrunReason: BreakOverrunReason?

    func answerBreakOverrun(_ reason: BreakOverrunReason, now: Date = Date()) {
        breakOverrunReason = reason
        coachJournal.record(.logged, "Break ran over: \(reason.title.lowercased()).", code: .question, at: now)
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
            let goal = dailyGoal().seconds
            let done = goalProgressSeconds()
            if done < goal {
                log("Block-until-goal: \(Int(done))s < \(Int(goal))s goal — keeping blocks active")
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
            // Coach v7: land the block (stretch nudge, laps) or walk the return ladder.
            if isFocusOvertime { handleFocusOvertimeStep() } else { handleBreakOvertimeStep() }
            // Live focus time grows with a block's overtime only: a break that ran over is break time.
            if isFocusOvertime {
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
            }
        }

        // Coach v7 §3.1: two minutes before the planned end, the landing cue asks for the next step.
        if state == .focusing, Int(remainingSeconds) == CoachLanding.cueSeconds {
            presentLandingCue()
        }
        // Coach v7 §3.2: one minute before a break ends, the next step. (Replaces the alerts at 2
        // and 5 minutes *into* a break, which fired while the break was still on plan.)
        if case .onBreak = state, !isBreakPaused, Int(remainingSeconds) == CoachReturnLadder.preEndSeconds {
            let next = latestNextStep()
            NotificationService.shared.sendCoachLine(
                id: "break-ending", title: "1 min left on your break",
                body: next.map { "Next: \($0)" } ?? "Next: back to the block."
            )
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
                dailyGoalMinutes: Int(dailyGoal().seconds / 60),
                completedMinutes: Int(goalProgressSeconds() / 60),
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
            self?.showCompletionWindow()
        }
        currentCoachQuickPromptDecision = nil
        hideCoachPanel()
        overtimeLapEndsAt = nil
        if wasType != nil, wasType != .focus {
            beginReturnLadder(now: Date())
        }
    }

    // MARK: - Reflection

    @MainActor
    func saveReflection(
        achievement: String?,
        splits: [TimeSplitView.SplitEntry]? = nil
    ) async {
        guard let session = lastCompletedSession else { return }
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

    /// True while a finished block waits for the user to choose what comes next: overtime after a
    /// natural completion, a manual stop awaiting reflection, or a wake-recovery prompt.
    var hasPendingCompletion: Bool {
        state == .idle && (isOvertime || isManualStop || showSessionComplete)
    }

    /// Resolves a pending completion. Does nothing when no completion is pending: the completion
    /// window and the popover can both offer these actions, so a second tap (or a double click)
    /// arrives after the first already started the next block. Running it then would stop the new
    /// block's timer and leave the state stuck in `.focusing` or `.onBreak`.
    func continueAfterCompletion(action: PostCompletionAction) {
        guard hasPendingCompletion else {
            log("continueAfterCompletion(\(action)): no pending completion (state=\(state)), ignoring")
            return
        }
        showSessionComplete = false
        isManualStop = false
        overtimeLapEndsAt = nil
        if coachPanel?.kind == .returnFromBreak || coachPanel?.kind == .landing { hideCoachPanel() }

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
            offerBackAt(now: Date())
        }
    }

    // MARK: - Focus Coach Actions

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
            // The notification is the prompt: its start answers this engine's last delivery.
            let attemptID = pendingCoachAttemptID
            if handleCoachAction(.startFocusNow) {
                coachEngine.recordInterventionOutcome(.improved, attemptID: attemptID)
            } else {
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
            guard state == .idle, !isOvertime, let decision = pendingCoachNotificationDecision else { return }
            let message = decision.composed ?? CoachMessageComposer.neutralFallback(isInSession: false, target: pendingCoachNotificationPlan)
            // Same 5·15·25 choice as an on-screen start nudge (v4 §3.3), not a single pacing size.
            let ladder = startLadderRecommendation()
            var plan = pendingCoachNotificationPlan
            plan?.minutes = ladder.minutes
            presentCoachPanel(
                CoachPanelPresentation(
                    kind: .startNudge,
                    message: message,
                    plan: plan,
                    attemptID: pendingCoachAttemptID,
                    sizeOptions: plan?.findNextStep == true ? [] : CoachBlockSizeLadder.sizes,
                    recommendedMinutes: ladder.minutes,
                    sizeCaption: ladder.caption
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
        // While the screen is shared nothing pops up; the prompt is simply not shown (SharePrivacy).
        guard !isPrivate else { return }
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
            // v4: the card's primary is "start now"; time chips plan for later.
            guard startCoachPlan(panel.plan, attemptID: panel.attemptID) else { return false }
        case .planTomorrow, .question, .landing:
            // No primary: each time chip plans a block; each answer is its own button; the
            // landing field saves itself.
            hideCoachPanel()
        case .returnFromBreak:
            return startFromReturnPanel(minutes: panel.plan?.minutes ?? regularMinutes)
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
        case .doneForToday where panel.kind == .returnFromBreak:
            coachJournal.record(.declined, "Back from break: done for today.", code: .returnLadder, at: now)
            interventionActionTaken = true
            hideCoachPanel()
            suppressBackAtOffer = true
            continueAfterCompletion(action: .endSession)
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
        case .reasonBusy, .reasonTired, .reasonTooBig, .reasonUnclear:
            if let reason = action.declineReason { performCoachPanelDecline(reason, now: now) }
        case .notToday where panel.kind == .question:
            if let id = panel.questionID {
                CoachQuestionStore(defaults: defaults).snooze(id, until: now.addingTimeInterval(CoachQuestionPolicy.notNowCooldown))
            }
            coachJournal.record(.declined, "Quick question: not now.", code: .question, at: now)
            interventionActionTaken = true
            hideCoachPanel()
        case .notToday where panel.kind == .planTomorrow:
            // Asked once tonight; "Not tonight" just closes it.
            coachEngine.recordInterventionOutcome(.snoozed, attemptID: panel.attemptID)
            coachJournal.record(.declined, "No plan for tomorrow tonight.", code: .planTomorrow, attemptID: panel.attemptID, at: now)
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
        coachJournal.record(
            unseen ? .unseen : .declined,
            unseen ? "The \(panel.kind.rawValue) panel hid while nobody was at the desk. Not counted against it."
                : "The \(panel.kind.rawValue) panel hid with no answer.",
            at: now
        )
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
        case .keepGoing, .momentum, .notice, .question: false
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
            dropPendingTaskOutsideProject()
        }
        if let priorityID = plan?.priorityID {
            pendingPriorityID = priorityID
        }
        if let minutes = plan?.minutes ?? idleStarterRecommendedMinutes {
            selectedMinutes = minutes
        }
        let intentIsFree = pendingIntentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || pendingIntentText == lastPrefilledIntent
        if plan?.findNextStep == true {
            pendingIntentText = "Find the next step"
        } else if intentIsFree, pendingTaskID == nil,
                  let task = DailyTaskPlanner.nextTask(todayTasks(), on: Date(), for: plan?.projectID ?? selectedProject?.id) {
            // Your own plan first: the next open task for this project becomes the block's goal.
            pendingIntentText = task.title
            pendingTaskID = task.id
        } else if intentIsFree, let lever = currentLever(projectID: plan?.projectID) {
            // The block's intent is today's lever: a specific output, not "work on it".
            pendingIntentText = lever.action
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
        // Without an id the engine falls back to the newest prompt; a popover start must not
        // mark an unrelated prompt as answered (credit goes through the reward ledger instead).
        if let attemptID { coachEngine.recordInterventionOutcome(.improved, attemptID: attemptID) }
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
        refreshWindowFit(now: now, force: force)
        refreshCalendarDayLabels(now: now)
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

    /// Credits the start to the prompt that asked for it: the prompt's own button first, else the
    /// most recent prompt the user saw in the last 20 minutes (Coach v4 §3.1, F1).
    /// Returns the prompt the user saw that gets the credit (nil: a start on your own).
    @discardableResult
    private func creditCoachPromptForStart(sessionID: UUID, minutes: Int, now: Date = Date()) -> UUID? {
        let pending = pendingCoachAttemptID
        pendingCoachAttemptID = nil
        guard let ledger = rewardLedger else { return nil }
        var credited: UUID?
        if let pending, ledger.creditStart(attemptID: pending, sessionID: sessionID, at: now) {
            credited = pending
        } else {
            credited = ledger.creditLatestSeen(sessionID: sessionID, at: now)
        }
        if let credited, let attempt = ledger.attempt(id: credited) {
            let label = CoachPromptAttribution.label(
                contextKey: attempt.contextKey,
                surface: attempt.surfaceRawValue.flatMap(CoachSurface.init(rawValue:))
            )
            let after = max(0, Int(now.timeIntervalSince(attempt.deliveredAt) / 60))
            rebuildBandit()
            if attempt.surfaceRawValue == CoachSurface.silent.rawValue {
                // The quiet arm: its outcome teaches the coach, but the coach showed you nothing.
                coachJournal.record(.started, "Started \(minutes)m on your own (the coach had stayed quiet; it learns from that too).", code: .quietArm, attemptID: credited, at: now)
                return nil
            }
            coachJournal.record(.started, "Started \(minutes)m, \(after)m after the \(label). It counts as a win for that prompt.", code: .afterPrompt, attemptID: credited, at: now)
            return credited
        }
        coachJournal.record(.started, "Started \(minutes)m on your own.", code: .onYourOwn, at: now)
        return nil
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
        let goalMinutes = Int(dailyGoal(now: now).seconds / 60)
        let doneMinutes = Int(goalProgressSeconds(now: now) / 60)
        let pacing = CoachGoalPacing(
            goalMinutes: goalMinutes,
            doneMinutes: doneMinutes,
            windowMinutesLeft: model.goodWindowMinutesRemainingToday(from: now)
        )
        // Screen audit (2026-10-28): weekly priorities are retired as a planning layer; ranked
        // projects, goals and daily tasks plan the week. The coach aims at the boss-fight goal's
        // project, then the #1 project; the next task or today's lever names the concrete action.
        let topPriority: WeeklyPriority? = nil
        let goals = reader?.activeGoals() ?? []
        let levers = DailyTaskPlanner.reconcile(GoalDataBuilder.levers(goals, now: now), with: todayTasks(now: now), on: now)
        let ranked = reader?.rankedProjects() ?? []
        let bossProjectID = goals.first { $0.isBossFight }?.projectID
        let focusProject: Project? = topPriority == nil
            ? (ranked.first { $0.id == bossProjectID } ?? ranked.first)
            : nil
        // The focus project's lever only: another project's lever never names this block.
        let lever = focusProject == nil
            ? levers.first
            : levers.first { $0.projectID == nil || $0.projectID == focusProject?.id }

        // Block length: max(25, min(remaining, 50)), shortened to end 5 min before a meeting.
        var minutes = pacing.suggestedBlockMinutes
        if let nextEvent = minutesUntilNextEvent, nextEvent - 5 < minutes {
            minutes = max(15, ((nextEvent - 5) / 5) * 5)
        }
        let projectID = topPriority?.projectID ?? focusProject?.id ?? selectedProject?.id
        var target = CoachStartTarget(
            minutes: minutes,
            name: topPriority?.title ?? focusProject?.name ?? selectedProject?.name,
            projectID: projectID,
            priorityID: topPriority?.id
        )
        target.rank = focusProject?.priorityRank
        // What the block will actually be about: your next task for this project, else the lever.
        if let task = DailyTaskPlanner.nextTask(todayTasks(now: now), on: now, for: projectID) {
            target.taskTitle = task.title
        } else {
            target.taskTitle = lever?.action
            target.goalTitle = lever?.goalTitle
        }

        var facts = CoachFacts()
        facts.lever = lever?.action
        facts.goal = GoalDataBuilder.goalFact(goals, now: now)
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
            facts.nextStep = latestNextStep(now: now)
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
            inGoodWindow: isInOwnWorkWindow(now),
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

    /// `guaranteed`: a declared window's one owed prompt. It may use the slot held back for it
    /// and is not held to the 2-hour panel spacing; every other limit applies.
    private func coachGuardrailInput(now: Date, calendarBusy: Bool, isIdlePrompt: Bool, guaranteed: Bool = false) -> CoachGuardrails.Input {
        let since = now.addingTimeInterval(-24 * 3600)
        var input = CoachGuardrails.Input(
            now: now,
            deliveries: coachEngine.guardrailDeliveries(since: since),
            // Never more than 3 interrupting prompts a day, and a slot kept for each window to come.
            maxPromptsPerDay: CoachOwnWorkWindows.cap(
                setting: settings?.coachMaxPromptsPerDay ?? CoachOwnWorkWindows.dailyCap,
                windows: settings?.coachOwnWorkWindows ?? [],
                now: now,
                guaranteed: guaranteed
            ),
            quietStartMinute: settings?.coachQuietStartMinute ?? 30,
            quietEndMinute: settings?.coachQuietEndMinute ?? 420,
            calendarBusy: calendarBusy,
            screenShareActive: settings.map(shouldSuppressGuardianPopups(using:)) ?? false,
            releaseActive: isInReleaseWindow,
            snoozedUntil: isIdlePrompt ? coachQuietUntil : coachEngine.promptState.snoozedUntil,
            sessionActive: state != .idle || isOvertime,
            isIdlePrompt: isIdlePrompt
        )
        input.ignorePanelSpacing = guaranteed
        return input
    }

    // MARK: Own-work windows (coach audit 2026-10-30)

    /// The own-work window around `now` (nil outside, or with none declared). Coach v6 §3.1:
    /// the declared windows plus the hours you actually start, until you answer the window question.
    func currentOwnWorkWindow(now: Date = Date()) -> DateInterval? {
        CoachOwnWorkWindows.current(effectiveOwnWorkWindows(now: now), now: now)
    }

    var hasDeclaredOwnWorkWindows: Bool { !(settings?.coachOwnWorkWindows ?? []).isEmpty }

    /// Declared windows plus observed ones (`CoachWindowFit.effective`).
    func effectiveOwnWorkWindows(now: Date = Date()) -> [CoachOwnWorkWindow] {
        let declared = settings?.coachOwnWorkWindows ?? []
        guard !declared.isEmpty else { return declared }
        return CoachWindowFit.effective(declared: declared, fit: windowFit, keepMine: keepsDeclaredWindows(now: now))
    }

    /// How well the declared windows match when own-work blocks start (refreshed once a day and
    /// after a block ends). Nil until computed or with no history.
    @ObservationIgnored private(set) var windowFit: CoachWindowFit?
    @ObservationIgnored private var windowFitComputedAt: Date?

    static let keepDeclaredWindowsUntilKey = "coachKeepDeclaredWindowsUntil"

    /// "Keep mine" was answered in the last 14 days: observed windows stay off.
    func keepsDeclaredWindows(now: Date = Date()) -> Bool {
        guard let until = defaults.object(forKey: Self.keepDeclaredWindowsUntilKey) as? Date else { return false }
        return until > now
    }

    func refreshWindowFit(now: Date = Date(), force: Bool = false) {
        if !force, let at = windowFitComputedAt, now.timeIntervalSince(at) < 3600 { return }
        guard let reader = historyReader else { return }
        let since = now.addingTimeInterval(-TimeInterval(CoachWindowFit.lookbackDays) * 86_400)
        let starts = reader.ownWorkSessions(since: since).map(\.startedAt)
        windowFit = CoachWindowFit.compute(startDates: starts, declared: settings?.coachOwnWorkWindows ?? [])
        windowFitComputedAt = now
    }

    /// Inside a declared own-work window; with none declared, inside a learned good window.
    func isInOwnWorkWindow(_ now: Date) -> Bool {
        hasDeclaredOwnWorkWindows ? currentOwnWorkWindow(now: now) != nil : availabilityModel.isGoodWindow(now)
    }

    /// The window around `now` owes its one interrupting prompt (`CoachOwnWorkWindows.owesPrompt`).
    func owesOwnWorkWindowPrompt(now: Date = Date()) -> Bool {
        guard let window = currentOwnWorkWindow(now: now), CoachOwnWorkWindows.isLastCall(window, now: now) else { return false }
        let started = blockStarts(since: window.start).contains { $0.startedAt < window.end }
            || (historyReader?.focusSessions(since: window.start).isEmpty == false)
        let prompts = coachEngine.guardrailDeliveries(since: window.start).filter {
            $0.wasSeen && $0.surface != .silent && $0.surface != .badge && $0.deliveredAt < window.end
        }.count
        return CoachOwnWorkWindows.owesPrompt(
            window: window, now: now, startedInWindow: started, promptsInWindow: prompts,
            goalMet: currentPacing(now: now).tier == .goalMet
        )
    }

    /// Runs once a minute: a declared window in its last half hour that has had no block and no
    /// prompt gets its prompt now, whatever the 70/30 draw said earlier. Returns true when one went out.
    @discardableResult
    func evaluateOwnWorkWindowPrompt(now: Date = Date()) -> Bool {
        guard state == .idle, !isOvertime, coachPanel == nil, pauseScreen == nil, owesOwnWorkWindowPrompt(now: now) else { return false }
        let sinceLast = historyReader?.lastFocusSessionEnd(before: now).map { Int(now.timeIntervalSince($0)) } ?? 24 * 3600
        evaluateIdleStarterIntervention(idleSeconds: sinceLast, frontmostCategory: AppUsageTracker.shared.currentFrontmostCategory, now: now)
        return lastIdleInterventionAt == now
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

    private func suppressIdlePrompt(_ reason: IdleStarterSuppressionReason, now: Date = Date()) {
        lastIdleStarterSuppressionReason = reason
        coachJournal.record(.quiet, "Quiet: \(reason.debugLabel).", code: reason.journalCode, at: now)
        currentIdleStarterDecision = nil
        if coachPanel?.kind == .startNudge || coachPanel?.kind == .weeklyPriorities {
            hideCoachPanel()
        }
    }

    // MARK: - Coach v4: start first (docs/plans/2026-10-28-coach-v4-start-first-design.md)

    /// The block size to ask for (v5 Learner B). The v4 rule is the prior; your own responses decide.
    /// `explore` samples (Thompson) at a real ask; displays use the posterior mean so they don't flicker.
    func startLadderRecommendation(now: Date = Date(), explore: Bool = false) -> CoachBlockSizeLadder.Recommendation {
        let rule = startRuleRecommendation(now: now)
        if rule.findsNextStep { return rule }
        let context = sizeContext(rule: rule, now: now)
        let observations = sizeLearningObservations(now: now)
        let models = CoachSizePolicy.models(from: observations)
        let minutes = explore
            ? CoachSizePolicy.choose(context: context, models: models, using: &coachRandom)
            : CoachSizePolicy.best(context: context, models: models)
        if minutes == rule.minutes && (observations.isEmpty || rule.why != .starting) { return rule }
        return .init(minutes: minutes, why: .learned(asks: observations.count))
    }

    /// Your regular block length (Settings ▸ Focus ▸ Your usual block, also set from the running block's
    /// length row). Every "Start" offers it first, so neither a warm-up nor a long break repeats a
    /// 5 or 15; the coach's smaller ask sits beside it. A pure read: views call it from `body`.
    var regularMinutes: Int {
        Self.regularMinutes(defaultBlockSeconds: settings?.focusDuration, selectedMinutes: selectedMinutes)
    }

    static func regularMinutes(defaultBlockSeconds: TimeInterval?, selectedMinutes: Int) -> Int {
        if let seconds = defaultBlockSeconds, seconds >= 5 * 60 { return Int((seconds / 60).rounded()) }
        return max(5, selectedMinutes)
    }

    /// The v4 rule: a fold over the last 21 days of prompts and blocks (§3.3 of the v4 design).
    func startRuleRecommendation(now: Date = Date()) -> CoachBlockSizeLadder.Recommendation {
        let since = now.addingTimeInterval(-Double(CoachBlockSizeLadder.lookbackDays) * 24 * 3600)
        var events: [CoachBlockSizeLadder.Event] = []
        var promptStartedSessions = Set<UUID>()
        for attempt in coachEngine.store.attempts(deliveredSince: since) {
            guard let key = attempt.contextKey, attempt.outcome != .unseen else { continue }
            let surface = attempt.surfaceRawValue.flatMap(CoachSurface.init(rawValue:))
            guard surface != .badge, surface != .silent else { continue }
            if (attempt.reward ?? 0) >= CoachRewardLedger.startReward, let sessionID = attempt.sessionId {
                promptStartedSessions.insert(sessionID)
                continue
            }
            // A plan the user made and then pushed says nothing about the size of the ask.
            if CoachPlannedCue.isRequestedCueKey(key) { continue }
            switch attempt.outcome {
            case .ignored?, .dismissed?:
                events.append(.init(at: attempt.resolvedAt ?? attempt.deliveredAt, kind: .declined(reason: attempt.skipReason)))
            // A plain snooze is "later", not "too big": only a stated reason ("It feels too big")
            // reaches the ladder.
            case .snoozed? where attempt.skipReason != nil:
                events.append(.init(at: attempt.resolvedAt ?? attempt.deliveredAt, kind: .declined(reason: attempt.skipReason)))
            default:
                break
            }
        }
        for session in historyReader?.ownWorkSessions(since: since) ?? [] {
            let minutes = Int((session.duration / 60).rounded())
            if promptStartedSessions.contains(session.id) {
                events.append(.init(at: session.startedAt, kind: .startedFromPrompt(minutes: minutes)))
            }
            if session.endedAt != nil, session.id != currentSession?.id {
                events.append(.init(at: session.effectiveEnd, kind: .blockEnded(minutes: minutes, completed: session.completed)))
            }
        }
        return CoachBlockSizeLadder.recommend(events: events)
    }

    /// The snapshot with the ladder's block size (never longer than the time before a meeting).
    private func withStartSize(_ snapshot: CoachSnapshot, ladder: CoachBlockSizeLadder.Recommendation) -> CoachSnapshot {
        var target = snapshot.target
        target.minutes = min(ladder.minutes, target.minutes)
        target.findNextStep = ladder.findsNextStep
        return CoachSnapshot(
            now: snapshot.now, inGoodWindow: snapshot.inGoodWindow, tier: snapshot.tier, pacing: snapshot.pacing,
            facts: snapshot.facts, target: target, topPriority: snapshot.topPriority, frontCategory: snapshot.frontCategory
        )
    }

    /// Today's top lever for the block's project. Nil without a project: a lever must never label
    /// an unrelated block.
    /// The project whose tasks and lever a surface shows now: the running block's, else the block
    /// just earned (break, overtime), else the picked one. Read-only, so views may call it in `body`.
    var taskScopeProjectID: UUID? {
        currentSession?.project?.id ?? breakEpisodeContext?.earnedBlock.projectId
            ?? completedBlockContext?.projectId ?? selectedProject?.id
    }

    /// Drops a picked task that belongs to another project than the picked one, with the title it
    /// prefilled, so a start from the coach, notch or a plan never links it (review 2026-10-30).
    func dropPendingTaskOutsideProject() {
        guard let id = pendingTaskID, let projectID = selectedProject?.id,
              let task = todayTasks().first(where: { $0.id == id }),
              let taskProjectID = task.projectID, taskProjectID != projectID else { return }
        pendingTaskID = nil
        if pendingIntentText == task.title { pendingIntentText = "" }
    }

    func currentLever(projectID: UUID?, now: Date = Date()) -> DailyLever? {
        guard let projectID else { return nil }
        return todayLevers(now: now).first { $0.projectID == projectID }
    }

    /// Today's levers, reconciled with today's tasks: a task for a key result is the commitment.
    func todayLevers(now: Date = Date()) -> [DailyLever] {
        DailyTaskPlanner.reconcile(GoalDataBuilder.levers(historyReader?.activeGoals() ?? [], now: now), with: todayTasks(now: now), on: now)
    }

    // MARK: Coach v5: learning engine (docs/plans/2026-10-28-coach-v5-learning-engine-design.md)

    static let learningLookbackDays = 60

    /// Focus blocks for reward resolution: every recorded start, short blocks included.
    /// Own work only: the goal is own-work time, so an Office block is not a coach success.
    private func learningBlocks(since: Date, now: Date = Date()) -> [CoachDecisionReward.Block] {
        historyReader?.learningBlocks(since: since, now: now) ?? []
    }

    // MARK: Block starts (coach audit 2026-10-30)

    private func canRecordBlockStarts() -> Bool {
        guard let modelContext else { return false }
        if let blockStartsSupported { return blockStartsSupported }
        let supported = modelContext.container.schema.entities.contains { $0.name == "BlockStartEvent" }
        blockStartsSupported = supported
        return supported
    }

    /// Records a block start, independent of the sessions table (which drops blocks under 5 min).
    private func recordBlockStart(_ session: FocusSession, promptAttemptID: UUID?) {
        guard canRecordBlockStarts(), let modelContext else { return }
        modelContext.insert(BlockStartEvent(
            sessionID: session.id,
            startedAt: session.startedAt,
            plannedMinutes: Int((session.duration / 60).rounded()),
            projectID: session.project?.id,
            ownWorkAtStart: historyReader?.countsAsOwnWork(session.project) ?? true,
            promptAttemptID: promptAttemptID
        ))
        saveContext()
    }

    /// Writes a block's focused seconds onto its start record. Call before deleting a focus session.
    private func noteBlockEnded(_ session: FocusSession) {
        guard session.type == .focus, canRecordBlockStarts(), let modelContext else { return }
        let id = session.id
        let descriptor = FetchDescriptor<BlockStartEvent>(predicate: #Predicate { $0.sessionID == id })
        guard let start = try? modelContext.fetch(descriptor).first else { return }
        start.focusedSeconds = session.actualDuration
    }

    /// Recorded block starts since `since` (all areas), for the coach log.
    func blockStarts(since: Date) -> [BlockStartEvent] {
        historyReader?.blockStarts(since: since) ?? []
    }

    /// The coach log's last days, newest first (Insights). Read-only, so safe in `body`.
    /// `goalSamples`: the blocks the daily goal counts (own work once a project is marked Work).
    func coachLogDays(now: Date = Date(), goalSamples: [FocusSample], days: Int = CoachLogSummary.defaultDays) -> [CoachLogDay] {
        let calendar = Calendar.current
        let since = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: now)) ?? now
        let starts = blockStarts(since: since).map { CoachLogSummary.Start(at: $0.startedAt, afterPrompt: $0.promptAttemptID != nil) }
        return CoachLogSummary.days(
            entries: coachJournal.entries(lastDays: days, now: now, calendar: calendar),
            starts: starts,
            ownWorkMinutes: { day in
                let end = calendar.date(byAdding: .day, value: 1, to: day) ?? day
                let seconds = GoalDataBuilder.seconds(samples: goalSamples, in: DateInterval(start: day, end: end)).values.reduce(0, +)
                return Int(seconds / 60)
            },
            goalMinutes: Int((settings?.dailyFocusGoal ?? 7200) / 60),
            now: now,
            count: days,
            calendar: calendar
        )
    }

    /// The context of a decision point as Learner A's features.
    func promptFeatures(snapshot: CoachSnapshot, frontmostCategory: AppUsageEntry.AppCategory, arrival: Bool, now: Date) -> CoachPromptFeatures {
        let recent = coachEngine.store.attempts(deliveredSince: now.addingTimeInterval(-24 * 3600))
        let seen = recent.filter {
            $0.treated == true || ($0.decisionRaw == nil && $0.kind == .strongPrompt)
        }.filter { $0.outcome != .unseen }.count
        let tired = recent.contains { $0.skipReason == .justTired && now.timeIntervalSince($0.deliveredAt) <= 12 * 3600 }
        let front: CoachPromptFeatures.Front = switch frontmostCategory {
        case .productive: .work
        case .neutral: .neutral
        case .distracting: .derailer
        }
        return CoachPromptFeatures(
            availabilityLift: availabilityModel.meanRate > 0 ? availabilityModel.p(now) / availabilityModel.meanRate : 1,
            arrival: arrival,
            hoursSinceLastBlock: snapshot.facts.minutesSinceLastSession.map { Double($0) / 60 },
            hasBlockToday: snapshot.facts.sessionsToday > 0,
            promptsSeen24h: seen,
            lateNight: CoachSituation.isLateNight(now),
            front: front,
            tiredRecently: tired,
            missedYesterday: snapshot.facts.missedYesterday,
            weekend: DayType.isWeekend(now)
        )
    }

    /// Learner A's evidence: every resolved decision point (prompted or quiet) with its reward.
    func promptLearningObservations(now: Date = Date()) -> [CoachPromptPolicy.Observation] {
        let since = now.addingTimeInterval(-Double(Self.learningLookbackDays) * 24 * 3600)
        let blocks = learningBlocks(since: since, now: now)
        return coachEngine.store.attempts(deliveredSince: since).compactMap { attempt in
            guard attempt.decisionRaw == CoachPromptPolicy.decisionKey,
                  attempt.outcome != .unseen,
                  let x = CoachPromptFeatures.decode(attempt.featuresRaw),
                  let propensity = attempt.propensity, let treated = attempt.treated,
                  let reward = CoachDecisionReward.reward(decidedAt: attempt.deliveredAt, now: now, blocks: blocks) else { return nil }
            return .init(x: x, treated: treated, propensity: propensity, reward: reward)
        }
    }

    private func sizeContext(rule: CoachBlockSizeLadder.Recommendation, now: Date) -> CoachSizePolicy.Context {
        let today = historyReader?.focusSessions(since: Calendar.current.startOfDay(for: now)).isEmpty == false
        return .init(ruleMinutes: rule.minutes, lateNight: CoachSituation.isLateNight(now), hasBlockToday: today)
    }

    /// Records the size an attempt asked for, with Learner B's context.
    private func noteSizeAsked(_ attempt: InterventionAttempt, minutes: Int, now: Date) {
        attempt.askedMinutes = minutes
        attempt.sizeFeaturesRaw = CoachSizePolicy.encode(sizeContext(rule: startRuleRecommendation(now: now), now: now).vector)
        coachEngine.store.saveChanges()
    }

    /// Learner B's evidence: each resolved ask, credited to the size started (or the size asked).
    func sizeLearningObservations(now: Date = Date()) -> [CoachSizePolicy.Observation] {
        let since = now.addingTimeInterval(-Double(Self.learningLookbackDays) * 24 * 3600)
        let blocks = learningBlocks(since: since, now: now)
        return coachEngine.store.attempts(deliveredSince: since).compactMap { attempt in
            guard let asked = attempt.askedMinutes, attempt.outcome != .unseen,
                  let x = CoachSizePolicy.decode(attempt.sizeFeaturesRaw),
                  now.timeIntervalSince(attempt.deliveredAt) >= CoachDecisionReward.momentumWindow else { return nil }
            let outcome = CoachDecisionReward.outcome(decidedAt: attempt.deliveredAt, blocks: blocks)
            let arm = outcome.startedBlock.map { CoachBlockSizeLadder.nearestSize($0.plannedMinutes) } ?? asked
            return .init(x: x, arm: arm, reward: outcome.reward)
        }
    }

    /// What the coach has learned, for Insights (§3.5).
    struct CoachLearningSummary {
        let lift: CoachLiftEstimate.Result?
        let decisions: Int
        let quietDecisions: Int
        let effects: [(name: String, weight: Double)]
        let sizes: [(minutes: Int, value: Double, asks: Int)]
    }

    func coachLearningSummary(now: Date = Date()) -> CoachLearningSummary {
        let observations = promptLearningObservations(now: now)
        let decisions = observations.map {
            CoachLiftEstimate.Decision(treated: $0.treated, propensity: $0.propensity, started: $0.reward >= 1)
        }
        let model = CoachPromptPolicy.model(from: observations)
        let rule = startRuleRecommendation(now: now)
        let x = sizeContext(rule: rule, now: now).vector
        let sizeObservations = sizeLearningObservations(now: now)
        let models = CoachSizePolicy.models(from: sizeObservations)
        let sizes = CoachSizePolicy.arms.map { arm in
            (minutes: arm, value: models[arm]?.predict(x).mean ?? 0, asks: sizeObservations.filter { $0.arm == arm }.count)
        }
        return CoachLearningSummary(
            lift: CoachLiftEstimate.estimate(decisions),
            decisions: observations.count,
            quietDecisions: observations.filter { !$0.treated }.count,
            effects: CoachPromptPolicy.strongestEffects(model),
            sizes: sizes
        )
    }

    /// The user is back at the desk after 10+ minutes (§3.2). A breakpoint: offer the start card,
    /// else a start nudge. Returns true when something was shown.
    @discardableResult
    func handleArrival(now: Date = Date()) -> Bool {
        coachJournal.record(.arrival, "You came back to the desk.", at: now)
        guard state == .idle, !isOvertime else {
            coachJournal.record(.quiet, "Quiet on arrival: a block is running.", code: .busyNow, at: now)
            return false
        }
        guard coachPanel == nil, pauseScreen == nil else {
            coachJournal.record(.quiet, "Quiet on arrival: something is already on screen.", code: .stickyPanel, at: now)
            return false
        }
        if evaluateDailyPlanInvite(now: now) { return true }
        let sinceLast = historyReader?.lastFocusSessionEnd(before: now).map { Int(now.timeIntervalSince($0)) } ?? 24 * 3600
        evaluateIdleStarterIntervention(
            idleSeconds: sinceLast,
            frontmostCategory: AppUsageTracker.shared.currentFrontmostCategory,
            arrival: true,
            now: now
        )
        return coachPanel != nil
    }

    /// Popover "Start small, now" (§3.3): the next block at `minutes` on the top priority
    /// (or on `projectID`, e.g. a lever's project from the notch).
    /// A start here still credits a prompt seen in the last 10 minutes.
    @discardableResult
    func startNextBlock(minutes: Int, projectID: UUID? = nil, now: Date = Date()) -> Bool {
        let snapshot = coachSnapshot(now: now, idleSeconds: 0, frontmostCategory: AppUsageTracker.shared.currentFrontmostCategory)
        var target = snapshot.target
        target.minutes = minutes
        if let projectID, projectID != target.projectID {
            target = CoachStartTarget(minutes: minutes, name: historyReader?.project(id: projectID)?.name, projectID: projectID, priorityID: nil)
        }
        return startCoachPlan(target)
    }

    /// The running block's intent ("3 LeetCode questions"), for the notch.
    var currentIntentText: String? { currentSession?.intentText }

    /// Active goals from the store (empty before configure or without the goal entities).
    func historyReaderActiveGoals() -> [ProjectGoal] { historyReader?.activeGoals() ?? [] }

    /// Logs progress on a key result, linked to the running block when there is one.
    func logGoalProgress(resultID: UUID, amount: Double, now: Date = Date()) {
        guard let modelContext,
              let result = try? modelContext.fetch(FetchDescriptor<GoalKeyResult>(predicate: #Predicate { $0.id == resultID })).first
        else { return }
        let entry = GoalProgressEntry(amount: amount, at: now, sessionID: currentSession?.id)
        modelContext.insert(entry)
        result.entries.append(entry)
        saveContext()
        coachJournal.record(.logged, "Logged +\(Int(amount)) \(result.title).", at: now)
    }

    /// Opens the companion window on a tab (set by FocusFlowApp).
    var openCompanionWindow: ((CompanionTab) -> Void)?

    /// Opens the welcome tour (set by FocusFlowApp; Settings → General → Getting started).
    var openOnboarding: (() -> Void)?

    // MARK: Daily reminder (clarity design: docs/plans/2026-10-28-clarity-fixes.md)

    /// Your own lines (My why, anti-vision, vision); empty until you write some.
    var ownReminderLines: [DailyReminderLine] {
        guard let settings else { return [] }
        return DailyReminder.ownLines(why: settings.coachMyWhyLines, antiVision: settings.lifeAntiVision, vision: settings.lifeVision)
    }

    /// Saves "My why" (up to five lines), the first source of the reminder line.
    func setReminderLines(_ text: String) {
        guard let settings else { return }
        settings.coachMyWhyText = CoachSettingsTab.limitedWhyText(text)
        saveContext()
    }

    /// Today's reminder line; `offset` steps to another one. A pure read: safe while drawing.
    func dailyReminder(now: Date = Date(), offset: Int = 0) -> DailyReminderLine? {
        DailyReminder.line(own: ownReminderLines, style: settings?.coachStyle ?? .challenger, on: now, offset: offset)
    }

    // MARK: Daily tasks (daily tasks design: docs/plans/2026-10-28-daily-tasks-design.md)

    /// The task picked for the next block (popover); saved on the session at start.
    var pendingTaskID: UUID?
    /// The running block's task, if it was started for one.
    var currentBlockTaskID: UUID? { currentSession?.taskID }
    /// Bumped on every task change so views that read tasks through the VM (notch, popover) redraw.
    private(set) var dailyTaskRevision = 0

    /// Tasks from the last `days` days (enough for today, carry-over and the week strip).
    func recentDailyTasks(days: Int = 8, now: Date = Date()) -> [DailyTask] {
        _ = dailyTaskRevision
        guard let modelContext,
              let since = Calendar.current.date(byAdding: .day, value: -days, to: Calendar.current.startOfDay(for: now))
        else { return [] }
        return (try? modelContext.fetch(FetchDescriptor<DailyTask>(predicate: #Predicate { $0.day >= since }))) ?? []
    }

    func todayTasks(now: Date = Date()) -> [DailyTask] {
        DailyTaskPlanner.tasks(recentDailyTasks(days: 1, now: now), on: now)
    }

    func dailyTaskStats(now: Date = Date()) -> DailyTaskStats {
        DailyTaskPlanner.stats(recentDailyTasks(days: 1, now: now), on: now)
    }

    @discardableResult
    func addDailyTask(title: String, projectID: UUID? = nil, keyResultID: UUID? = nil, amount: Double? = nil,
                      carriedFromID: UUID? = nil, reminderID: String? = nil, pushToReminders: Bool = true,
                      day: Date? = nil, now: Date = Date()) -> DailyTask? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let modelContext, !trimmed.isEmpty else { return nil }
        let start = Calendar.current.startOfDay(for: day ?? now)
        let order = (DailyTaskPlanner.tasks(recentDailyTasks(days: 1, now: start), on: start).map(\.order).max() ?? -1) + 1
        let task = DailyTask(title: trimmed, day: start, order: order, projectID: projectID, keyResultID: keyResultID, amount: amount)
        task.carriedFromID = carriedFromID
        task.reminderID = reminderID
        modelContext.insert(task)
        saveContext()
        dailyTaskRevision += 1
        if pushToReminders, reminderID == nil, let listID = reminderListID(forProject: projectID) {
            // A new task on a synced project also goes to its Reminders list (due that day).
            let title = task.title, day = task.day
            // The task is held until the write runs: callers often drop it (`_ = addDailyTask…`),
            // and a weak capture lost every reminder (bug 2026-10-30).
            writeToReminders { [weak self] bridge in
                // Deleted before the write ran: create nothing.
                guard !task.isDeleted, task.modelContext != nil,
                      let id = bridge.createReminder(title: title, dueDay: day, listId: listID) else { return }
                task.reminderID = id
                self?.saveContext()
            }
        }
        return task
    }

    /// Adds today's lever ("3 LeetCode questions") as a task linked to its key result.
    @discardableResult
    func addLeverTask(_ lever: DailyLever, now: Date = Date()) -> DailyTask? {
        // A goal count ("3 LeetCode questions") stays in FocusFlow: it never adds a reminder.
        addDailyTask(title: lever.taskTitle, projectID: lever.projectID, keyResultID: lever.id, amount: lever.amount,
                     pushToReminders: false, now: now)
    }

    /// Ticks or unticks a task. A linked task logs what is left of its amount on tick and removes
    /// all of its entries on untick, so goal pace stays true. Shows a receipt with Undo.
    /// `inBlock: false` (a tick that came from Reminders) never credits the running block.
    func setDailyTask(_ task: DailyTask, done: Bool, sessionID: UUID? = nil, inBlock: Bool = true, now: Date = Date(), receipt: Bool = true) {
        guard let modelContext, task.isDone != done else { return }
        adoptLegacyProgressEntry(of: task)
        let result = keyResult(for: task)
        let before = task.loggedCount
        if done {
            task.isDone = true
            task.doneAt = now
            task.sessionID = inBlock ? (sessionID ?? currentSession?.id) : sessionID
            let remaining = task.progressAmount - before
            if let result, remaining > 0 {
                let entry = GoalProgressEntry(amount: remaining, at: now, note: task.title, sessionID: task.sessionID)
                entry.taskID = task.id
                modelContext.insert(entry)
                result.entries.append(entry)
            }
            if result != nil { task.loggedAmount = task.progressAmount }
            coachJournal.record(.logged, "Done: \(task.title).", at: now)
        } else {
            removeProgressEntries(of: task)
            task.isDone = false
            task.doneAt = nil
            task.sessionID = nil
            if result != nil { task.loggedAmount = 0 }
        }
        saveContext()
        dailyTaskRevision += 1
        pushReminderCompletion(of: task)
        guard receipt else { return }
        showDailyTaskReceipt(DailyTaskReceipt(
            taskID: task.id,
            text: DailyTaskReceipt.text(
                change: done ? .done : .reopened, taskTitle: task.title, resultTitle: result?.title,
                amount: done ? task.progressAmount - before : before, logged: task.loggedCount, of: task.progressAmount,
                goalDone: result?.done, goalTarget: result?.target
            ),
            undo: done ? .reopen : .markDone,
            at: now
        ))
    }

    /// +1 or −1 on a counted task ("Problems solved 1 of 3"). Each +1 is its own goal entry; −1
    /// takes back the latest. The task is done when the count reaches its amount.
    @discardableResult
    func stepDailyTask(_ task: DailyTask, by delta: Int, sessionID: UUID? = nil, now: Date = Date(), receipt: Bool = true) -> Bool {
        guard let modelContext, delta != 0, let result = keyResult(for: task) else { return false }
        adoptLegacyProgressEntry(of: task)
        var logged = task.loggedCount
        if delta > 0 {
            for _ in 0..<delta {
                let entry = GoalProgressEntry(amount: 1, at: now, note: task.title, sessionID: sessionID ?? currentSession?.id)
                entry.taskID = task.id
                modelContext.insert(entry)
                result.entries.append(entry)
            }
            logged += Double(delta)
        } else {
            let taskID = task.id
            var descriptor = FetchDescriptor<GoalProgressEntry>(predicate: #Predicate { $0.taskID == taskID }, sortBy: [SortDescriptor(\.at, order: .reverse)])
            descriptor.fetchLimit = 50
            var toRemove = Double(-delta)
            for entry in (try? modelContext.fetch(descriptor)) ?? [] where toRemove > 0 {
                let take = min(entry.amount, toRemove)
                if entry.amount > take { entry.amount -= take } else { modelContext.delete(entry) }
                toRemove -= take
                logged -= take
            }
            guard toRemove < Double(-delta) else { return false }
        }
        task.loggedAmount = max(0, logged)
        let nowDone = task.loggedCount >= task.progressAmount
        if nowDone, !task.isDone {
            task.isDone = true
            task.doneAt = now
            task.sessionID = sessionID ?? currentSession?.id
            coachJournal.record(.logged, "Done: \(task.title).", at: now)
        } else if !nowDone, task.isDone {
            task.isDone = false
            task.doneAt = nil
            task.sessionID = nil
        }
        saveContext()
        dailyTaskRevision += 1
        pushReminderCompletion(of: task)
        if receipt {
            showDailyTaskReceipt(DailyTaskReceipt(
                taskID: task.id,
                text: DailyTaskReceipt.text(
                    change: delta > 0 ? .added : .removed, taskTitle: task.title, resultTitle: result.title,
                    amount: Double(abs(delta)), logged: task.loggedCount, of: task.progressAmount,
                    goalDone: result.done, goalTarget: result.target
                ),
                undo: delta > 0 ? .stepDown : .stepUp,
                at: now
            ))
        }
        return true
    }

    /// The tap on a task's control: +1 on an open counted task, otherwise tick or untick.
    func advanceDailyTask(_ task: DailyTask, sessionID: UUID? = nil, now: Date = Date()) {
        if task.isCounted, !task.isDone {
            stepDailyTask(task, by: 1, sessionID: sessionID, now: now)
        } else {
            setDailyTask(task, done: !task.isDone, sessionID: sessionID, now: now)
        }
    }

    /// What the last tick or +1 logged, with Undo; clears itself after a few seconds.
    private(set) var dailyTaskReceipt: DailyTaskReceipt?

    private func showDailyTaskReceipt(_ receipt: DailyTaskReceipt) {
        dailyTaskReceipt = receipt
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(DailyTaskReceipt.visibleSeconds))
            if self?.dailyTaskReceipt?.id == receipt.id { self?.dailyTaskReceipt = nil }
        }
    }

    /// Reverses the receipt's change without a new receipt.
    func undoDailyTaskReceipt(now: Date = Date()) {
        guard let receipt = dailyTaskReceipt else { return }
        dailyTaskReceipt = nil
        guard let task = recentDailyTasks(days: 1, now: now).first(where: { $0.id == receipt.taskID })
            ?? recentDailyTasks(days: 8, now: now).first(where: { $0.id == receipt.taskID }) else { return }
        switch receipt.undo {
        case .reopen: setDailyTask(task, done: false, now: now, receipt: false)
        case .markDone: setDailyTask(task, done: true, now: now, receipt: false)
        case .stepDown: stepDailyTask(task, by: -1, now: now, receipt: false)
        case .stepUp: stepDailyTask(task, by: 1, now: now, receipt: false)
        }
    }

    /// Goals count; one-off steps are tasks (tasks and goals review 2026-10-30). Each open "done or
    /// not" key result becomes a task for today on the goal's project (a synced project also gets
    /// the reminder), unless today already has a task with that title; then the key result goes.
    /// Done ones are history and simply go. Runs at launch; does nothing once none are left.
    func migrateCheckboxKeyResults(now: Date = Date()) {
        guard let modelContext else { return }
        let checkbox = GoalKeyResultKind.checkbox.rawValue
        let legacy = (try? modelContext.fetch(FetchDescriptor<GoalKeyResult>(predicate: #Predicate { $0.kindRaw == checkbox }))) ?? []
        guard !legacy.isEmpty else { return }
        let existing = Set(todayTasks(now: now).map { $0.title.lowercased() })
        var converted = 0
        for result in legacy {
            let title = result.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if result.done < result.target, !title.isEmpty, !existing.contains(title.lowercased()) {
                addDailyTask(title: title, projectID: result.goal?.projectID, now: now)
                converted += 1
            }
            result.goal?.keyResults.removeAll { $0.id == result.id }
            modelContext.delete(result)
        }
        saveContext()
        dailyTaskRevision += 1
        log("goals: \(legacy.count) done-or-not key results removed, \(converted) became tasks")
    }

    /// "Link to goal": the task now counts toward `resultID` (nil unlinks). A done task moves what it
    /// logged to the new key result, so goal progress stays true either way.
    func linkDailyTask(_ task: DailyTask, toResult resultID: UUID?, now: Date = Date()) {
        guard let modelContext, task.keyResultID != resultID else { return }
        removeProgressEntries(of: task)
        task.keyResultID = resultID
        if resultID == nil {
            task.amount = nil
            task.loggedAmount = nil
        } else if task.isDone, let result = keyResult(for: task) {
            let entry = GoalProgressEntry(amount: task.progressAmount, at: now, note: task.title, sessionID: task.sessionID)
            entry.taskID = task.id
            modelContext.insert(entry)
            result.entries.append(entry)
            task.loggedAmount = task.progressAmount
        } else {
            task.loggedAmount = 0
        }
        saveContext()
        dailyTaskRevision += 1
    }

    /// Renames a task; a synced task's reminder follows.
    func renameDailyTask(_ task: DailyTask, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != task.title else { return }
        task.title = trimmed
        saveContext()
        dailyTaskRevision += 1
        if let reminderID = syncedReminderID(of: task) {
            writeToReminders { $0.setReminderTitle(identifier: reminderID, trimmed) }
        }
    }

    /// "+1" on a key result from the running popover or the notch. When today has an open task
    /// linked to it, the +1 goes through that task (so the task's count and the goal agree and
    /// nothing is logged twice); otherwise it is logged on the key result directly.
    func logOneMore(resultID: UUID, now: Date = Date()) {
        if let task = todayTasks(now: now).first(where: { $0.keyResultID == resultID && !$0.isDone }) {
            advanceDailyTask(task, now: now)
        } else {
            logGoalProgress(resultID: resultID, amount: 1, now: now)
        }
    }

    /// Deletes the task; a synced task's reminder is deleted with it (the list mirrors the tasks).
    func deleteDailyTask(_ task: DailyTask) {
        guard let modelContext else { return }
        if let reminderID = syncedReminderID(of: task) {
            writeToReminders { $0.deleteReminder(identifier: reminderID) }
        }
        removeProgressEntries(of: task)
        modelContext.delete(task)
        saveContext()
        dailyTaskRevision += 1
    }

    /// Moves an open task to tomorrow (keeps its links).
    func moveDailyTaskToTomorrow(_ task: DailyTask, now: Date = Date()) {
        guard !task.isDone, let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)) else { return }
        task.day = tomorrow
        task.order = (DailyTaskPlanner.tasks(recentDailyTasks(days: 0, now: tomorrow), on: tomorrow).map(\.order).max() ?? -1) + 1
        saveContext()
        dailyTaskRevision += 1
        if let reminderID = syncedReminderID(of: task) {
            // Due tomorrow in Reminders too, so today's sync doesn't bring it back.
            writeToReminders { $0.setReminderDueDay(identifier: reminderID, tomorrow) }
        }
    }

    /// Moves an open task to the top of its day.
    func moveDailyTaskToTop(_ task: DailyTask) {
        let siblings = DailyTaskPlanner.tasks(recentDailyTasks(days: 1, now: task.day), on: task.day)
        task.order = (siblings.map(\.order).min() ?? 0) - 1
        saveContext()
        dailyTaskRevision += 1
    }

    /// Copies the last planned day's unfinished tasks to today. Returns how many.
    @discardableResult
    func carryOverDailyTasks(now: Date = Date()) -> Int {
        let candidates = DailyTaskPlanner.carryOverCandidates(recentDailyTasks(days: DailyTaskPlanner.carryOverLookbackDays + 1, now: now), today: now)
        for task in candidates {
            addDailyTask(title: task.title, projectID: task.projectID, keyResultID: task.keyResultID, amount: task.amount,
                         carriedFromID: task.id, reminderID: task.reminderID, now: now)
        }
        return candidates.count
    }

    // MARK: Reminders sync (one list per project; design notes in ReminderTaskSync)

    /// EventKit in the app, a fake in tests.
    var reminderBridge: any ReminderBridge = RemindersService.shared
    /// The latest queued write to Reminders (tests await it).
    private(set) var reminderWrite: Task<Void, Never>?
    private var reminderSyncTask: Task<Void, Never>?
    private var isSyncingReminders = false
    private var reminderSyncAgain = false
    /// Set while the sync applies Reminders' state, so it is not written straight back.
    private var applyingReminderSync = false

    var remindersSyncOn: Bool { settings?.remindersIntegrationEnabled == true && reminderBridge.isAuthorized }

    func reminderListID(forProject projectID: UUID?) -> String? {
        guard remindersSyncOn, let projectID, let modelContext,
              let project = try? modelContext.fetch(FetchDescriptor<Project>(predicate: #Predicate { $0.id == projectID })).first,
              let listID = project.reminderListID, !listID.isEmpty, !project.archived else { return nil }
        return listID
    }

    /// Queues an EventKit write after the current UI change, in order, so a tick or delete never
    /// waits on the Reminders store.
    private func writeToReminders(_ work: @escaping @MainActor (any ReminderBridge) -> Void) {
        let previous = reminderWrite
        let bridge = reminderBridge
        reminderWrite = Task { @MainActor in
            await previous?.value
            work(bridge)
        }
    }

    /// The task's reminder, while its project still syncs a list (after "Don't sync" or archiving,
    /// FocusFlow stops writing to the old list).
    func syncedReminderID(of task: DailyTask) -> String? {
        guard let reminderID = task.reminderID, reminderListID(forProject: task.projectID) != nil else { return nil }
        return reminderID
    }

    private func pushReminderCompletion(of task: DailyTask) {
        guard !applyingReminderSync, let reminderID = syncedReminderID(of: task) else { return }
        let done = task.isDone
        writeToReminders { $0.setReminderCompleted(identifier: reminderID, done) }
    }

    /// A project switched lists or stopped syncing. Its open tasks for today and later mirrored the
    /// old list, so they go (the reminders stay in Reminders, untouched); the new list imports on
    /// the next sync. Done tasks, past days and tasks with logged goal progress stay as history,
    /// unlinked, so nothing is ever written to the old list again. (Bug 2026-10-30: unlinking
    /// everything left a whole wrong list behind as plain tasks, and duplicates on a re-switch.)
    func reminderListChanged(forProject projectID: UUID, now: Date = Date()) {
        guard let modelContext else { return }
        let today = Calendar.current.startOfDay(for: now)
        let linked = (try? modelContext.fetch(FetchDescriptor<DailyTask>(
            predicate: #Predicate { $0.projectID == projectID && $0.reminderID != nil }
        ))) ?? []
        var removed = 0
        for task in linked {
            if !task.isDone, task.day >= today, task.loggedCount == 0 {
                modelContext.delete(task)
                removed += 1
            } else {
                task.reminderID = nil
            }
        }
        guard !linked.isEmpty else { return }
        saveContext()
        dailyTaskRevision += 1
        log("reminders: list changed, removed \(removed) open tasks of the old list, kept \(linked.count - removed) as history")
    }

    @ObservationIgnored private var reminderSyncObservers: [NSObjectProtocol] = []

    /// Always-on sync triggers, from launch: a change in Reminders (the phone, the Reminders app,
    /// another Mac) and coming back to the app. They used to live on a view inside the menu-bar
    /// popover, so nothing synced until the popover had been opened (bug 2026-10-30).
    func startReminderSyncObservers() {
        guard reminderSyncObservers.isEmpty else { return }
        let center = NotificationCenter.default
        for name in [Notification.Name.EKEventStoreChanged, NSApplication.didBecomeActiveNotification] {
            reminderSyncObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleReminderSync() }
            })
        }
        scheduleReminderSync()
    }

    /// Asks for a sync soon (coalesced). Called on launch, app activation, EventKit changes, day
    /// rollover, popover open and when a project's list changes.
    func scheduleReminderSync(after delay: Duration = .milliseconds(800)) {
        guard remindersSyncOn else { return }
        reminderSyncTask?.cancel()
        reminderSyncTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.syncReminders()
        }
    }

    /// Pulls each synced project's list into today's tasks (see `ReminderTaskSync`). The fetch runs
    /// off the main thread; applying it is a few SwiftData writes.
    func syncReminders(now: Date = Date()) async {
        guard remindersSyncOn, let modelContext else { return }
        guard !isSyncingReminders else { reminderSyncAgain = true; return }
        isSyncingReminders = true
        defer {
            isSyncingReminders = false
            if reminderSyncAgain { reminderSyncAgain = false; scheduleReminderSync() }
        }
        // Oldest first, so if two projects ever name the same list the same one always wins.
        let projects = (try? modelContext.fetch(FetchDescriptor<Project>(predicate: #Predicate { !$0.archived }, sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        var projectForList: [String: UUID] = [:]
        for project in projects {
            if let listID = project.reminderListID, !listID.isEmpty, projectForList[listID] == nil { projectForList[listID] = project.id }
        }
        guard !projectForList.isEmpty else { return }
        await reminderWrite?.value // our own pending writes land first
        let open = await reminderBridge.fetchIncompleteReminders(in: Array(projectForList.keys), dueDateStarting: nil, dueDateEnding: nil)

        let tasks = recentDailyTasks(days: DailyTaskPlanner.carryOverLookbackDays + 1, now: now)
        let refs = tasks.compactMap { task in
            task.reminderID.map { ReminderTaskSync.TaskRef(id: task.id, reminderID: $0, day: task.day, isDone: task.isDone, title: task.title) }
        }
        let unlinked = DailyTaskPlanner.tasks(tasks, on: now)
            .filter { $0.reminderID == nil && !$0.isDone }
            .map { ReminderTaskSync.UnlinkedTask(id: $0.id, title: $0.title, projectID: $0.projectID) }
        let plan = ReminderTaskSync.plan(open: open, projectForList: projectForList, tasks: refs, unlinkedToday: unlinked, today: now)
        guard !plan.isEmpty else { return }

        applyingReminderSync = true
        defer { applyingReminderSync = false }
        var changed = false
        let byID = Dictionary(tasks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // One insert batch, one save: imports never run a fetch or save per task.
        var nextOrder: [Date: Int] = [:]
        for item in plan.imports {
            let order = nextOrder[item.day] ?? (DailyTaskPlanner.tasks(tasks, on: item.day).map(\.order).max() ?? -1) + 1
            nextOrder[item.day] = order + 1
            let task = DailyTask(title: item.title, day: item.day, order: order, projectID: item.projectID)
            task.carriedFromID = item.carriedFromID
            task.reminderID = item.reminderID
            // A carried-over reminder keeps counting toward the goal it was picked into.
            if let earlier = item.carriedFromID.flatMap({ byID[$0] }), earlier.keyResultID != nil {
                task.keyResultID = earlier.keyResultID
                task.amount = earlier.amount
                task.loggedAmount = 0
            }
            modelContext.insert(task)
            changed = true
        }
        for link in plan.links {
            byID[link.taskID]?.reminderID = link.reminderID
            changed = true
        }
        for rename in plan.renames {
            byID[rename.taskID]?.title = rename.title
            changed = true
        }
        for deferral in plan.deferrals {
            byID[deferral.taskID]?.day = deferral.day
            changed = true
        }
        for id in plan.reopens {
            guard let task = byID[id] else { continue }
            setDailyTask(task, done: false, now: now, receipt: false)
            changed = true
        }
        for check in plan.toCheck {
            guard let task = byID[check.taskID] else { continue }
            switch reminderBridge.reminderState(identifier: check.reminderID) {
            case .completed:
                setDailyTask(task, done: true, inBlock: false, now: now, receipt: false)
                changed = true
            case .missing:
                task.reminderID = nil // deleted in Reminders: the task stays, unlinked
                changed = true
            case .open:
                break // moved to a list this project doesn't sync: leave it linked
            }
        }
        // Nothing changed, no save and no revision bump, so views keyed on it don't redraw.
        guard changed else { return }
        saveContext()
        dailyTaskRevision += 1
        log("reminders: synced \(plan.imports.count) new, \(plan.renames.count) renamed, \(plan.deferrals.count) moved, \(plan.reopens.count) reopened")
    }

    /// Where a project stands with Reminders, for its page (project tasks redesign 2026-11-02): a
    /// reminder that doesn't show up must say why (sync off, no access, no list, list gone).
    enum ProjectReminderLink: Equatable {
        case syncOff
        case noAccess
        case notLinked
        case listMissing
        case linked(listTitle: String)
    }

    func reminderLink(for project: Project) -> ProjectReminderLink {
        guard settings?.remindersIntegrationEnabled == true else { return .syncOff }
        guard reminderBridge.isAuthorized else { return .noAccess }
        guard let listID = project.reminderListID, !listID.isEmpty else { return .notLinked }
        guard let list = reminderBridge.reminderLists().first(where: { $0.id == listID }) else { return .listMissing }
        return .linked(listTitle: list.title)
    }

    /// Links `project` to a Reminders list (nil stops syncing) from its page, as its Edit sheet does.
    func setReminderList(_ listID: String?, for project: Project) {
        guard project.reminderListID != listID else { return }
        project.reminderListID = listID
        saveContext()
        reminderListChanged(forProject: project.id)
        scheduleReminderSync(after: .zero)
    }

    /// The project's open tasks after today, soonest first: its reminders due later (every reminder
    /// is imported on its due day) and tasks moved to a later day.
    func laterTasks(forProject projectID: UUID, now: Date = Date()) -> [DailyTask] {
        guard let modelContext,
              let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)) else { return [] }
        let tasks = (try? modelContext.fetch(FetchDescriptor<DailyTask>(
            predicate: #Predicate { $0.day >= tomorrow && $0.projectID == projectID && !$0.isDone }
        ))) ?? []
        return tasks.sorted { ($0.day, $0.order) < ($1.day, $1.order) }
    }

    /// "Do Today" on a later task: it moves to today, and a reminder's due date in Reminders moves
    /// with it (otherwise the next sync sends the task back to its later day).
    func moveDailyTaskToToday(_ task: DailyTask, now: Date = Date()) {
        let today = Calendar.current.startOfDay(for: now)
        guard !task.isDone, task.day != today else { return }
        task.day = today
        task.order = (DailyTaskPlanner.tasks(recentDailyTasks(days: 0, now: today), on: today).map(\.order).max() ?? -1) + 1
        saveContext()
        dailyTaskRevision += 1
        if let reminderID = syncedReminderID(of: task) {
            writeToReminders { $0.setReminderDueDay(identifier: reminderID, today) }
        }
    }

    /// Picks tasks (a project's reminders, today's or later) into one of `goal`'s numbers
    /// (2026-11-02). `resultID` nil makes a new number called `newTitle`, its target the number of
    /// tasks picked; otherwise `raiseTarget` grows that number's target by the newly picked ones.
    /// Every open copy of the same reminder (a carried-over one too) is linked, so it counts once,
    /// whichever copy you tick. A goal never becomes a task: this only links tasks to its numbers.
    @discardableResult
    func countTasks(_ picked: [DailyTask], toward goal: ProjectGoal, resultID: UUID?, newTitle: String = "Steps",
                    raiseTarget: Bool = true, now: Date = Date()) -> GoalKeyResult? {
        guard let modelContext, !picked.isEmpty else { return nil }
        let result: GoalKeyResult
        if let resultID, let existing = goal.keyResults.first(where: { $0.id == resultID }) {
            result = existing
        } else {
            let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            result = GoalKeyResult(title: title.isEmpty ? "Steps" : title, kind: .count, target: 0,
                                   order: (goal.keyResults.map(\.order).max() ?? -1) + 1)
            modelContext.insert(result)
            goal.keyResults.append(result)
        }
        let added = picked.filter { $0.keyResultID != result.id }
        let reminderIDs = Set(added.compactMap(\.reminderID))
        let copies = reminderIDs.isEmpty ? [] : ((try? modelContext.fetch(FetchDescriptor<DailyTask>(
            predicate: #Predicate { !$0.isDone && $0.reminderID != nil }
        ))) ?? []).filter { reminderIDs.contains($0.reminderID ?? "") }
        for task in added + copies where task.keyResultID != result.id {
            linkDailyTask(task, toResult: result.id, now: now)
        }
        if resultID == nil {
            result.target = Double(max(1, added.count))
        } else if raiseTarget {
            result.target += Double(added.count)
        }
        saveContext()
        dailyTaskRevision += 1
        return result
    }

    private func keyResult(for task: DailyTask) -> GoalKeyResult? {
        guard let modelContext, let resultID = task.keyResultID else { return nil }
        return try? modelContext.fetch(FetchDescriptor<GoalKeyResult>(predicate: #Predicate { $0.id == resultID })).first
    }

    /// A task ticked before entries carried `taskID`: tag its one entry so −1 and untick find it.
    private func adoptLegacyProgressEntry(of task: DailyTask) {
        guard let modelContext, let entryID = task.progressEntryID else { return }
        if let entry = try? modelContext.fetch(FetchDescriptor<GoalProgressEntry>(predicate: #Predicate { $0.id == entryID })).first {
            entry.taskID = task.id
            if task.loggedAmount == nil { task.loggedAmount = entry.amount }
        }
        task.progressEntryID = nil
    }

    /// Removes every goal entry logged through `task`.
    private func removeProgressEntries(of task: DailyTask) {
        guard let modelContext else { return }
        adoptLegacyProgressEntry(of: task)
        let taskID = task.id
        for entry in (try? modelContext.fetch(FetchDescriptor<GoalProgressEntry>(predicate: #Predicate { $0.taskID == taskID }))) ?? [] {
            modelContext.delete(entry)
        }
    }

    /// Notch companion host, set by FocusFlowApp (nil in tests).
    var notchHost: (any NotchHosting)?

    var isNotchCompanionEnabled: Bool { settings?.notchCompanionEnabled ?? true }

    func setNotchCompanionEnabled(_ enabled: Bool) {
        settings?.notchCompanionEnabled = enabled
        saveContext()
        notchHost?.setEnabled(enabled)
    }

    /// A size pill on the start card or a start nudge (§3.3).
    @discardableResult
    func performCoachPanelStart(minutes: Int) -> Bool {
        guard let panel = coachPanel else { return false }
        if panel.kind == .returnFromBreak { return startFromReturnPanel(minutes: minutes) }
        var target = panel.plan ?? CoachStartTarget(minutes: minutes, name: nil, projectID: nil, priorityID: nil)
        target.minutes = minutes
        target.findNextStep = false
        guard startCoachPlan(target, attemptID: panel.attemptID) else { return false }
        interventionActionTaken = true
        return true
    }

    /// "Not now, because…" (§3.4): stores the reason, then acts on it. Too big or no next step
    /// re-asks at once with the small version; busy or tired goes quiet.
    func performCoachPanelDecline(_ reason: FocusCoachSkipReason, now: Date = Date()) {
        guard let panel = coachPanel else { return }
        coachEngine.recordInterventionOutcome(.snoozed, skipReason: reason, attemptID: panel.attemptID)
        interventionActionTaken = true
        coachJournal.record(.declined, "Not now: \(CoachDeclineResponse.label(reason).lowercased()).", at: now)
        switch CoachDeclineResponse.action(for: reason, now: now) {
        case .quietUntil(let until):
            coachQuietUntil = max(coachQuietUntil ?? until, until)
            currentIdleStarterDecision = nil
            if panel.kind == .dailyPlan {
                let store = CoachDailyPlanInviteStore(defaults: defaults)
                var inviteLog = store.load(now: now)
                inviteLog.declined = true
                store.save(inviteLog)
            }
            hideCoachPanel()
        case .counterOffer(let minutes, let findNextStep):
            var target = panel.plan ?? CoachStartTarget(minutes: minutes, name: nil, projectID: nil, priorityID: nil)
            target.minutes = minutes
            target.findNextStep = findNextStep
            let snapshot = coachSnapshot(now: now, idleSeconds: 0, frontmostCategory: AppUsageTracker.shared.currentFrontmostCategory)
            let message = composeCoachMessage(
                trigger: .counterOffer(reason: reason),
                style: settings?.coachStyle ?? .challenger,
                snapshot: CoachSnapshot(
                    now: now, inGoodWindow: snapshot.inGoodWindow, tier: snapshot.tier, pacing: snapshot.pacing,
                    facts: snapshot.facts, target: target, topPriority: snapshot.topPriority, frontCategory: snapshot.frontCategory
                )
            )
            // Same attempt: a start from the counter-offer credits the prompt that was declined.
            if let id = panel.attemptID, let attempt = coachEngine.store.attempt(id: id) {
                noteSizeAsked(attempt, minutes: minutes, now: now)
            }
            presentCoachPanel(CoachPanelPresentation(kind: .startNudge, message: message, plan: target, attemptID: panel.attemptID, createdAt: now))
            coachJournal.record(.shown, "Counter-offer: \(message.primaryTitle).", code: .counterOffer, attemptID: panel.attemptID, hook: message.hook, at: now)
        }
    }

    // MARK: - Idle start nudge (decision policy)

    /// Decision point for "start a block" prompts. Order: hard guardrails, learned window,
    /// pacing, then the Thompson-sampling bandit picks surface × style (or silence).
    func evaluateIdleStarterIntervention(
        idleSeconds: Int,
        frontmostCategory: AppUsageEntry.AppCategory,
        arrival: Bool = false,
        now: Date = Date()
    ) {
        guard state == .idle, !isOvertime, let settings else { return }
        resolveExpiredCoachRewards(now: now)
        if isInReleaseWindow {
            suppressIdlePrompt(.releaseWindowActive, now: now)
            return
        }
        if shouldSuppressGuardianPopups(using: settings) {
            suppressIdlePrompt(.screenShareSuppressed, now: now)
            return
        }
        guard settings.antiProcrastinationEnabled, settings.coachIdleStarterEnabled else {
            suppressIdlePrompt(settings.antiProcrastinationEnabled ? .idleStarterDisabled : .antiProcrastinationDisabled, now: now)
            return
        }
        // Coach audit 2026-10-30: with own-work windows declared, outside them is no decision point.
        if hasDeclaredOwnWorkWindows, currentOwnWorkWindow(now: now) == nil {
            suppressIdlePrompt(.outsideOwnWorkWindow, now: now)
            return
        }
        if let last = lastIdleInterventionAt, now.timeIntervalSince(last) < 120 {
            lastIdleStarterSuppressionReason = .cooldownActive
            coachJournal.record(.quiet, "Quiet: \(IdleStarterSuppressionReason.cooldownActive.debugLabel).", code: .cooldown, at: now)
            return
        }
        // A planned cue or the plan card is on screen: never replace it with a nudge.
        if isStickyCoachPanelBlocking(now: now) {
            coachJournal.record(.quiet, "Quiet: your plan is on screen.", code: .stickyPanel, at: now)
            return
        }
        // Drifting in a focus window: the rescue loop's ladder replaces the plain start nudge, but
        // only while it is actually speaking (coach v6 §3.2). On 3 Nov 2026 the ladder held this
        // turn for 6.5 h while its own rescues were held by the cap and calendar.
        if let drift = currentDrift, drift.isActive, drift.level > .ok, rescueSpokeRecently(now: now) {
            lastIdleStarterSuppressionReason = nil
            coachJournal.record(.quiet, "Quiet: the rescue ladder has this drift (level \(drift.level.rawValue)).", code: .driftActive, at: now)
            return
        }
        // The window's one owed prompt: skips the 70/30 draw and the 2-hour spacing, nothing else.
        let guaranteed = coachArmOverride == nil && owesOwnWorkWindowPrompt(now: now)
        let calendarAvailability = currentCalendarAvailability(now: now)
        log("idle starter calendar: busyNow=\(calendarAvailability.isBusyNow) nextEventMin=\(calendarAvailability.minutesUntilNextEvent.map(String.init) ?? "nil")")
        let guardrailInput = coachGuardrailInput(now: now, calendarBusy: calendarAvailability.isBusyNow, isIdlePrompt: true, guaranteed: guaranteed)
        let baseVerdict = coachGuardrails.verdict(for: .badge, input: guardrailInput)
        if let reason = IdleStarterSuppressionReason(verdict: baseVerdict) {
            suppressIdlePrompt(reason, now: now)
            return
        }
        // v4 §3.2 (F3): only prompt someone who is at the desk. A start panel already on screen
        // stays: its own timeout records whether it was seen.
        if !CoachPresence.isPresent(systemIdleSeconds: systemIdleSeconds()) {
            lastIdleStarterSuppressionReason = .userAway
            coachJournal.record(.quiet, "Quiet: \(IdleStarterSuppressionReason.userAway.debugLabel).", code: .away, at: now)
            return
        }

        reloadWeeklyPriorities(now: now)
        let idleTarget = currentIdleDistractionTarget()
        let idleSeverity = idleTarget.flatMap { loadIdleDistractionCatalog().resolution(for: $0).severity }
        let effectiveCategory = AppUsageTracker.idleAdjustedCategory(
            frontmostCategory: frontmostCategory,
            idleSeverityOverride: idleSeverity
        )
        let ladder = startLadderRecommendation(now: now, explore: coachExploreSizes)
        let snapshot = withStartSize(coachSnapshot(
            now: now,
            idleSeconds: idleSeconds,
            frontmostCategory: effectiveCategory,
            minutesUntilNextEvent: calendarAvailability.minutesUntilNextEvent
        ), ladder: ladder)
        updateCoachDebugReadout(snapshot)

        // Coming back to the desk is a breakpoint (v4 §3.2): it opens its own window. So does a
        // "Deep work" / Focus Time block on the calendar: you set that time aside for this.
        // With declared windows only they count (checked above); else the learned window.
        guard snapshot.inGoodWindow || (!hasDeclaredOwnWorkWindows && (arrival || calendarAvailability.isFocusBlockNow)) else {
            suppressIdlePrompt(.outsideFocusWindow, now: now)
            return
        }
        guard snapshot.pacing.isBehindPace || guaranteed else {
            suppressIdlePrompt(.onTrack, now: now)
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
        // v5 Learner A (docs/plans/2026-10-28-coach-v5-learning-engine-design.md §3.2). A decision point
        // exists only when a prompt could actually be shown (on screen or as a notification); the
        // badge led to 0 starts in 28 and is no longer a start prompt.
        let deliverable: CoachSurface? = gated.surfaces.contains(.panel) ? .panel
            : gated.surfaces.contains(.notification) ? .notification : nil
        let forced = coachArmOverride.flatMap { gated.surfaces.contains($0.surface) ? $0 : nil }
        guard let surface = forced?.surface ?? deliverable else {
            let reason = gated.firstBlock.flatMap(IdleStarterSuppressionReason.init(verdict:))
            lastIdleStarterSuppressionReason = reason ?? .banditChoseSilent
            currentIdleStarterDecision = nil
            coachJournal.record(.quiet, "Quiet: \(reason?.debugLabel ?? "no surface allowed").", code: reason?.journalCode ?? .noSurface, at: now)
            return
        }
        let features = promptFeatures(snapshot: snapshot, frontmostCategory: effectiveCategory, arrival: arrival, now: now).vector
        let prompt: Bool
        let propensity: Double?
        if let forced {
            prompt = forced.surface != .silent
            propensity = nil
        } else if guaranteed {
            // Certain, so it teaches the prompt learner nothing and stays out of its data.
            prompt = true
            propensity = 1
        } else {
            let observations = promptLearningObservations(now: now)
            let model = CoachPromptPolicy.model(from: observations)
            let decision = CoachPromptPolicy.decide(x: features, model: model, resolvedDecisions: observations.count, using: &coachRandom)
            prompt = decision.prompt
            propensity = decision.probability
        }
        guard prompt, surface != .silent else {
            // Logged too: the quiet decisions are the control group that measures a prompt's effect.
            let point = coachEngine.recordDecisionPoint(
                at: now, riskScore: availabilityModel.p(now),
                features: CoachPromptFeatures.encode(features), propensity: propensity
            )
            lastIdleInterventionAt = now
            lastIdleStarterSuppressionReason = .banditChoseSilent
            currentIdleStarterDecision = nil
            coachJournal.record(
                .quiet,
                "Held back on purpose (prompt chance \(Int(((propensity ?? 0) * 100).rounded()))%): quiet moments are how the coach measures whether its prompts help.",
                code: .control, attemptID: point.id, propensity: propensity, at: now
            )
            return
        }
        let arm = forced ?? CoachArm(surface: surface, style: settings.coachStyle)
        let style = arm.style ?? settings.coachStyle

        deliverStartNudge(
            arm: arm, style: style, contextKey: contextKey, snapshot: snapshot, idleSeconds: idleSeconds, ladder: ladder, arrival: arrival,
            learning: (features, propensity), code: forced != nil ? .forced : guaranteed ? .guaranteed : .prompted
        )
        lastIdleInterventionAt = now
        lastIdleStarterSuppressionReason = nil
    }

    private func deliverStartNudge(
        arm: CoachArm,
        style: CoachStyle,
        contextKey: CoachContextKey,
        snapshot: CoachSnapshot,
        idleSeconds: Int,
        ladder: CoachBlockSizeLadder.Recommendation? = nil,
        arrival: Bool = false,
        learning: (features: [Double], propensity: Double?)? = nil,
        code: CoachJournal.Code = .prompted
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
        if let learning {
            // A window's guaranteed prompt is logged apart: certain, so not a learning decision.
            attempt.decisionRaw = code == .guaranteed ? CoachPromptPolicy.guaranteedDecisionKey : CoachPromptPolicy.decisionKey
            attempt.featuresRaw = CoachPromptFeatures.encode(learning.features)
            attempt.propensity = learning.propensity
            attempt.treated = true
        }
        noteSizeAsked(attempt, minutes: snapshot.target.minutes, now: snapshot.now)
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

        let chance = code == .guaranteed ? " (this window's one guaranteed ask)"
            : learning?.propensity.map { " (prompt chance \(Int(($0 * 100).rounded()))%)" } ?? ""
        coachJournal.record(
            .shown,
            "Start nudge (\(arm.surface.rawValue))\(arrival ? " as you came back" : "")\(chance): asked for \(snapshot.target.minutes)m.",
            code: code, attemptID: attempt.id, propensity: learning?.propensity, hook: message.hook,
            at: snapshot.now
        )
        switch arm.surface {
        case .panel, .strongWindow:
            let sizes = ladder.map { _ in CoachBlockSizeLadder.sizes } ?? []
            presentCoachPanel(
                CoachPanelPresentation(
                    kind: .startNudge, message: message, plan: snapshot.target, attemptID: attempt.id,
                    sizeOptions: snapshot.target.findNextStep ? [] : sizes,
                    recommendedMinutes: ladder?.minutes,
                    sizeCaption: ladder?.caption
                ),
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
        // Retired with weekly priorities (screen audit): goals and daily tasks plan the week.
        guard Self.weeklyPrioritiesRetired == false else { return false }
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
        let arrived = arrivalDetector.observe(systemIdleSeconds: systemIdleSeconds())
        // v3: the user's own planned start comes first; it owns the screen until answered.
        if evaluatePlannedCue(now: now) { return }
        evaluateRescueLoop(now: now)
        if arrived, handleArrival(now: now) { return }
        // The rest runs once a minute.
        guard coachIdleTickCount % 4 == 0 else { return }
        resolveExpiredCoachRewards(now: now)
        if evaluatePlanTomorrowCheckIn(now: now) { return }
        if evaluateCoachQuestion(now: now) { return }
        if evaluateDailyPlanInvite(now: now) { return }
        if evaluateOwnWorkWindowPrompt(now: now) { return }
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
        // What you said matters (screen audit): the next task, else today's lever, else the #1 project.
        let priority = pseudoProductivityFocusName(snapshot)
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
            topPriority: snapshot.topPriority,
            frontCategory: frontmostCategory
        )
        let style = settings.coachStyle
        let motivation = pickMotivation(situation: CoachSituation.isLateNight(now) ? .lateNight : .drift, now: now)
        let message = composeCoachMessage(trigger: .pseudoProductivity(priority: priority), style: style, snapshot: pseudoSnapshot, motivation: motivation)
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
        coachJournal.record(.shown, "Pseudo-work check: \(message.hook)", code: .pseudoCheck, attemptID: attempt.id, hook: message.hook, at: now)
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

    /// The name the pseudo-productivity question holds up: the next task, today's lever, or the #1 project.
    private func pseudoProductivityFocusName(_ snapshot: CoachSnapshot) -> String? {
        // A real task's title, else the goal, else the #1 project: never the lever's count line.
        let task = snapshot.target.goalTitle == nil ? snapshot.target.taskTitle : nil
        return snapshot.topPriority?.title ?? task ?? snapshot.target.goalTitle ?? (snapshot.target.rank == 1 ? snapshot.target.name : nil)
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
            let ladder = startLadderRecommendation(now: now)
            let sized = withStartSize(snapshot, ladder: ladder)
            let message = composeCoachMessage(
                trigger: .dailyPlan(goalMinutes: snapshot.pacing.goalMinutes, firstSuggestion: slots.first?.label()),
                style: style, snapshot: sized, motivation: motivation
            )
            log("debug: start card '\(message.hook)' size=\(ladder.minutes) slots=\(slots.map { $0.label() }) motivation='\(message.motivation?.text ?? "")'")
            presentCoachPanel(CoachPanelPresentation(
                kind: .dailyPlan, message: message, plan: sized.target, planSlots: slots,
                sizeOptions: CoachBlockSizeLadder.sizes, recommendedMinutes: sized.target.minutes, sizeCaption: ladder.caption
            ))
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
            // Coach v6 §3.2: outside declared windows the day job's apps are not pseudo-work, however
            // far behind the goal is (a work-app morning held the ladder at L2 until night, 3 Nov 2026).
            // Real derailers still count, so the menu bar counter still shows "YouTube 12m".
            pacingPressure: hasDeclaredOwnWorkWindows && currentOwnWorkWindow(now: now) == nil ? nil : currentPacing(now: now).pressure,
            busyworkContexts: busyworkContexts,
            userAway: systemIdleSeconds() >= 5 * 60,
            role: appRole(key: frontmost.browserHost ?? frontmost.bundleIdentifier ?? "", name: frontmost.displayName ?? frontmost.appName ?? "", now: now).role
        )
        driftMonitor.record(at: now, seconds: seconds, kind: kind, switchesPerMinute: frontmost.switchesPerMinute)
    }

    /// Seconds that count toward the daily goal (`GoalDataBuilder.goalScope`): the ★ #1 project,
    /// else own work once a project is marked Work, else all focus. Office hours never fill the ring
    /// or switch the coach off. The store query is cached for 30 s; new focus time invalidates it.
    func goalProgressSeconds(now: Date = Date()) -> TimeInterval {
        if let cached = goalProgressCache, cached.focusTime == todayFocusTime,
           now.timeIntervalSince(cached.at) < 30, cached.at <= now {
            return cached.seconds
        }
        let seconds = historyReader?.goalScopeSecondsToday(now: now) ?? todayFocusTime
        goalProgressCache = (now, todayFocusTime, seconds)
        return seconds
    }

    /// What the daily goal counts, for labels ("★ Learning"). A store read: safe while drawing.
    func goalScope() -> GoalScope {
        guard let modelContext else { return .allFocus }
        return GoalDataBuilder.goalScope((try? modelContext.fetch(FetchDescriptor<Project>())) ?? [])
    }

    /// Today's daily goal: what it counts and its size (`GoalDataBuilder.dailyGoal`). A store read:
    /// safe while drawing. Every ring, line and the coach's pace use this, never `dailyFocusGoal`.
    func dailyGoal(now: Date = Date()) -> DailyGoal {
        let projects = modelContext.flatMap { try? $0.fetch(FetchDescriptor<Project>()) } ?? []
        let base = GoalDataBuilder.dailyGoal(projects: projects, settings: settings, on: now)
        // Coach v8 §3.5: on a leave, weekend, holiday or sick day your target for that type wins.
        guard storesDayLedger, let type = settledDayType(now: now), type != .workday else { return base }
        let yours = DayTargetStore(defaults: defaults).minutes(for: type)
        guard yours != nil || type == .sick else { return base }
        return base.sized(minutes: DayTargets.minutes(type: type, yours: yours, goalMinutes: Int(base.seconds / 60)), for: type)
    }

    private func currentPacing(now: Date) -> CoachGoalPacing {
        CoachGoalPacing(
            goalMinutes: Int(dailyGoal(now: now).seconds / 60),
            doneMinutes: Int(goalProgressSeconds(now: now) / 60),
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

    func systemIdleSeconds() -> TimeInterval {
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

    /// A rescue panel or pause screen went out in the last 30 minutes.
    func rescueSpokeRecently(now: Date = Date()) -> Bool {
        rescueRecords(now: now).contains { $0.surface != .ambient && now.timeIntervalSince($0.deliveredAt) < 30 * 60 }
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
        let ownWindow = currentOwnWorkWindow(now: now)
        let window = ownWindow.map { CoachFocusWindow(start: $0.start, isLearned: true) }
            ?? CoachFocusWindow.current(now: now, model: availabilityModel)
        let pacing = currentPacing(now: now)
        let records = rescueRecords(now: now)
        let ignored = records.filter { $0.deliveredAt >= window.start && $0.surface != .ambient && $0.wasIgnored }.count
        let lastEnd = historyReader?.lastFocusSessionEnd(before: now)
        let assessment = driftMonitor.assess(.init(
            now: now,
            sessionActive: sessionActive,
            inLearnedWindow: isInOwnWorkWindow(now),
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

        // Declared own-work windows: outside them a rescue is no decision point either.
        if hasDeclaredOwnWorkWindows, ownWindow == nil {
            lastRescueDecision = .init(level: assessment.level, at: now, windowStart: window.start, baseLevel: assessment.baseLevel)
            coachJournal.record(.quiet, "Rescue L\(assessment.level.rawValue) held: outside your own-work windows.", code: .outsideOwnWindow, at: now)
            return false
        }
        let calendarBusy = currentCalendarAvailability(now: now).isBusyNow
        var input = coachGuardrailInput(now: now, calendarBusy: calendarBusy, isIdlePrompt: true)
        input.ignorePanelSpacing = true
        if let reason = IdleStarterSuppressionReason(verdict: coachGuardrails.verdict(for: .badge, input: input)) {
            lastIdleStarterSuppressionReason = reason
            coachJournal.record(.quiet, "Rescue L\(assessment.level.rawValue) held: \(reason.debugLabel).", code: reason.journalCode, at: now)
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
        var candidates = CoachRescueCadence.candidateSurfaces(
            level: assessment.level,
            panelEnabled: settings.coachOnScreenPromptsEnabled,
            pauseScreenAllowed: pauseVerdict == .allowed
        )
        // v4 §3.5 (F5): outside learned windows a rescue stays on the menu-bar counter.
        if !CoachRescueWindowPolicy.allowsOnScreen(
            tier: availabilityModel.tier(now), modelHasData: availabilityModel.mode != .noData,
            declaredWindowOpen: hasDeclaredOwnWorkWindows ? ownWindow != nil : nil
        ) {
            candidates.removeAll { $0 == .panel || $0 == .strongWindow }
        }
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
            coachJournal.record(
                .quiet, "Rescue L\(level.rawValue) stayed on the menu-bar counter (\(assessment.ambientMinutes)m drift).",
                code: .rescueAmbient, attemptID: attempt.id, at: now
            )
            return false

        case .panel:
            guard let style = arm.style else { return false }
            let motivation = pickMotivation(situation: rescueSituation(level: level, facts: snapshot.facts, now: now), now: now)
            let usePseudoPanel: Bool = {
                guard level <= .lost, pseudoProductivityFocusName(snapshot) != nil, case .pseudo = assessment.dominantSignal else { return false }
                return true
            }()
            let trigger: CoachTrigger = usePseudoPanel
                ? .pseudoProductivity(priority: pseudoProductivityFocusName(snapshot) ?? "")
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
            coachJournal.record(
                .shown, "\(usePseudoPanel ? "Pseudo-work check" : "Rescue L\(level.rawValue)"): \(message.hook)",
                code: usePseudoPanel ? .pseudoCheck : .rescue, attemptID: attempt.id, hook: message.hook, at: now
            )
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
            coachJournal.record(
                .shown, "Pause screen (rescue L\(level.rawValue)).",
                code: .rescue, attemptID: attempt.id, hook: rescue.longFact, at: now
            )
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

    /// "⌃⌥Space starts a short block on your next step, from anywhere" while the shortcut is on.
    private var hotkeyFooterHint: String? {
        guard let settings, settings.coachGlobalHotkeyEnabled else { return nil }
        return CoachStarterBlock.hotkeyHint
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
    /// Whether this store knows `BlockStartEvent` (older test containers do not).
    @ObservationIgnored private var blockStartsSupported: Bool?

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
        coachPanel?.kind == .plannedStart || coachPanel?.kind == .dailyPlan || coachPanel?.kind == .planTomorrow
    }

    /// A planned cue, start card or plan check-in stays on screen until answered, but it holds
    /// other prompts back for 15 minutes only (coach v6 §3.2: on 5 Nov 2026 an unanswered 20:00
    /// cue silenced the whole 20–22 window).
    func isStickyCoachPanelBlocking(now: Date) -> Bool {
        guard let panel = coachPanel,
              panel.kind == .plannedStart || panel.kind == .dailyPlan || panel.kind == .planTomorrow else { return false }
        return now.timeIntervalSince(panel.createdAt) < 15 * 60
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
        coachJournal.record(.shown, "Planned cue for \(cue.timeLabel) (\(block.minutes)m).", code: .plannedCue, attemptID: attempt.id, hook: message.hook, at: now)
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
            hasSuggestions: true,
            capReached: coachGuardrails.verdict(
                for: .badge, input: coachGuardrailInput(now: now, calendarBusy: availability.isBusyNow, isIdlePrompt: true)
            ) == .dailyCapReached,
            outsideOwnWindow: hasDeclaredOwnWorkWindows && currentOwnWorkWindow(now: now) == nil,
            beforeDayStart: Calendar.current.component(.hour, from: now) * 60 + Calendar.current.component(.minute, from: now) < settings.coachQuietEndMinute
        )
        guard CoachDailyPlanInvite.shouldInvite(input) else { return false }
        // v4: the card's job is "start now"; time chips are the fallback, so none is fine.
        let slots = dailyPlanSuggestions(now: now)

        let ladder = startLadderRecommendation(now: now, explore: coachExploreSizes)
        let snapshot = withStartSize(
            coachSnapshot(now: now, idleSeconds: 0, frontmostCategory: AppUsageTracker.shared.currentFrontmostCategory),
            ladder: ladder
        )
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
        // Any start in the next 10 minutes answers the card (v4 F1: before, none were credited).
        pendingCoachAttemptID = attempt.id
        noteSizeAsked(attempt, minutes: snapshot.target.minutes, now: now)
        if message.showsMotivation { noteMotivationShown(motivation, attemptID: attempt.id, at: now) }
        inviteLog.shown += 1
        inviteLog.lastShownAt = now
        store.save(inviteLog)
        log("coach plan: start card shown (\(ladder.minutes)m; later: \(slots.map { $0.label() }.joined(separator: ", ")))")
        coachJournal.record(.shown, "Start card: asked for \(snapshot.target.minutes)m (\(ladder.caption))", code: .startCard, attemptID: attempt.id, hook: message.hook, at: now)
        presentCoachPanel(CoachPanelPresentation(
            kind: .dailyPlan,
            message: message,
            plan: snapshot.target,
            attemptID: attempt.id,
            createdAt: now,
            planSlots: slots,
            sizeOptions: snapshot.target.findNextStep ? [] : CoachBlockSizeLadder.sizes,
            recommendedMinutes: snapshot.target.minutes,
            sizeCaption: ladder.caption
        ))
        return true
    }

    /// Commits a start time: creates the plan and confirms on screen. Used by the plan card,
    /// the popover chips and the companion.
    @discardableResult
    func commitDailyPlan(_ slot: CoachPlanSlot, now: Date = Date()) -> PlannedBlock? {
        guard let block = insertPlannedBlock(at: slot.start, now: now) else { return nil }
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

    private func insertPlannedBlock(at start: Date, now: Date) -> PlannedBlock? {
        guard canUsePlannedBlocks(), let modelContext else { return nil }
        reloadWeeklyPriorities(now: now)
        let top = weeklyPriorities.first { !$0.isDone }
        let block = PlannedBlock(
            startAt: start,
            // v4: a planned block is the ladder's size, not a pacing-driven 25–50 minutes.
            minutes: startLadderRecommendation(now: now).minutes,
            title: top?.title,
            priorityID: top?.id,
            projectID: top?.projectID ?? selectedProject?.id
        )
        modelContext.insert(block)
        saveContext()
        return block
    }

    // MARK: Plan tomorrow (coach audit 2026-10-30)

    /// Blocks already planned for tomorrow.
    func tomorrowPlans(now: Date = Date()) -> [PlannedBlock] {
        let calendar = Calendar.current
        guard canUsePlannedBlocks(),
              let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)),
              let after = calendar.date(byAdding: .day, value: 1, to: tomorrow) else { return [] }
        return plannedBlocks(from: tomorrow, to: after).filter { $0.status == .planned }
    }

    /// Times offered for tomorrow's blocks.
    func planTomorrowSlots(now: Date = Date()) -> [CoachPlanSlot] {
        refreshCoachModelsIfNeeded(now: now)
        return CoachPlanTomorrow.slots(
            now: now,
            windows: effectiveOwnWorkWindows(now: now),
            model: availabilityModel,
            quietStartMinute: settings?.coachQuietStartMinute ?? 30,
            quietEndMinute: settings?.coachQuietEndMinute ?? 420,
            planned: tomorrowPlans(now: now).map(\.startAt)
        )
    }

    // MARK: Cycle: land the block, return from the break (coach v7)

    /// A chosen "Keep going" lap ends at this overtime second (nil: none chosen).
    @ObservationIgnored private var overtimeLapEndsAt: Int?
    @ObservationIgnored private var landingCueShownFor: UUID?
    @ObservationIgnored private var returnHazardCache: (day: Date, hazard: CoachReturnHazard)?
    /// This break end drew the return panel (learner B's treated arm).
    @ObservationIgnored private(set) var returnLadderTreated = false
    @ObservationIgnored private var suppressBackAtOffer = false
    /// Tests: force the return experiment's arm (nil: randomise).
    @ObservationIgnored var cycleArmOverride: Bool?

    /// Every finished session since `since`, focus and breaks, for the cycle learners.
    func cycleSessions(since: Date) -> [CoachCycleStats.Session] {
        guard let modelContext else { return [] }
        let descriptor = FetchDescriptor<FocusSession>(predicate: #Predicate { $0.startedAt >= since }, sortBy: [SortDescriptor(\.startedAt)])
        return ((try? modelContext.fetch(descriptor)) ?? []).compactMap { session in
            guard let end = session.endedAt else { return nil }
            return CoachCycleStats.Session(isFocus: session.type == .focus, start: session.startedAt, end: end,
                                           plannedSeconds: session.duration, pausedSeconds: session.totalPausedSeconds)
        }
    }

    func cycleStats(now: Date = Date()) -> CoachCycleStats {
        CoachCycleStats.compute(cycleSessions(since: now.addingTimeInterval(-60 * 86_400)))
    }

    /// Learner A, refit once a day from the last 60 days of breaks.
    func returnHazard(now: Date = Date()) -> CoachReturnHazard {
        let day = Calendar.current.startOfDay(for: now)
        if let cache = returnHazardCache, cache.day == day { return cache.hazard }
        let sessions = cycleSessions(since: now.addingTimeInterval(-60 * 86_400))
        var latencies: [Double?] = []
        for (i, s) in sessions.enumerated() where !s.isFocus {
            let plannedEnd = s.start.addingTimeInterval(s.plannedSeconds)
            let next = sessions[(i + 1)...].first(where: \.isFocus)
            if let next, next.start.timeIntervalSince(plannedEnd) <= TimeInterval(CoachReturnHazard.horizonMinutes * 60) {
                latencies.append(next.start.timeIntervalSince(plannedEnd) / 60)
            } else {
                latencies.append(nil)
            }
        }
        let hazard = CoachReturnHazard.fit(latencies: latencies)
        returnHazardCache = (day, hazard)
        return hazard
    }

    /// The most recent next step written in the last 12 hours.
    func latestNextStep(now: Date = Date()) -> String? {
        guard let modelContext else { return nil }
        let since = now.addingTimeInterval(-12 * 3600)
        var descriptor = FetchDescriptor<FocusSession>(predicate: #Predicate { $0.startedAt >= since }, sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
        descriptor.fetchLimit = 20
        let sessions = (try? modelContext.fetch(descriptor)) ?? []
        return sessions.lazy.compactMap { $0.nextStepText?.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }
    }

    /// The return experiment's decisions (Insights reads its estimate).
    func cycleDecisions() -> [CoachCycleExperiment.Decision] { CoachCycleLog(defaults: defaults).load() }

    // Landing

    /// T − 2 min: "2 min left. What's the next step?" (§3.1). Once per block, not on starters or
    /// blocks under 10 min, never over another panel or while sharing.
    func presentLandingCue(now: Date = Date()) {
        guard state == .focusing, !isStarterBlock, let session = currentSession, session.type == .focus,
              totalSeconds >= 10 * 60, landingCueShownFor != session.id,
              coachPanel == nil, pauseScreen == nil, !isPrivate,
              settings?.coachOnScreenPromptsEnabled == true else { return }
        landingCueShownFor = session.id
        let message = CoachComposedMessage(
            style: settings?.coachStyle ?? .challenger, trigger: .startNudge,
            hook: "2 min left. What's the next step?",
            detail: .line("Write where you'll pick up. It's waiting when the break ends."),
            primaryTitle: "", hookIsFact: false
        )
        coachJournal.record(.shown, "Landing cue.", code: .landing, at: now)
        presentCoachPanel(CoachPanelPresentation(kind: .landing, message: message, createdAt: now, step: session.nextStepText))
    }

    /// Stores the next step on the running block, or on the block that just ended.
    func setNextStep(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let session = (currentSession?.type == .focus && !isOvertime) ? currentSession : (lastCompletedFocusSession ?? currentSession)
        guard let session, session.type == .focus else { return }
        session.nextStepText = trimmed.isEmpty ? nil : trimmed
        saveContext()
    }

    func saveLandingNextStep(_ text: String, now: Date = Date()) {
        setNextStep(text)
        coachJournal.record(.logged, "Next step written.", code: .landing, at: now)
        if coachPanel?.kind == .landing { hideCoachPanel() }
    }

    /// "Keep going" (§3.1): a 10-minute lap, then the block-end window comes back.
    func keepGoingLap(now: Date = Date()) {
        guard isFocusOvertime else { return }
        overtimeLapEndsAt = overtimeSeconds + CoachLanding.lapMinutes * 60
        showSessionComplete = false
        coachJournal.record(.logged, "Kept going: a \(CoachLanding.lapMinutes)-min lap.", code: .stretch, at: now)
    }

    var isInOvertimeLap: Bool { isFocusOvertime && overtimeLapEndsAt != nil }

    private func handleFocusOvertimeStep(now: Date = Date()) {
        switch CoachLanding.overtimeStep(overtimeSeconds: overtimeSeconds, lapEndsAt: overtimeLapEndsAt) {
        case .none:
            return
        case .stretchNudge:
            let fact = cycleStats(now: now).stretchFact
            NotificationService.shared.sendCoachLine(
                id: "stretch", title: "5 min past your block",
                body: fact ?? "Land it: finish, or take the break you earned."
            )
            coachJournal.record(.shown, "Stretch nudge at +5 min.", code: .stretch, hook: fact, at: now)
        case .resurface, .lapEnded:
            let lap = overtimeLapEndsAt != nil
            overtimeLapEndsAt = nil
            if lap {
                NotificationService.shared.sendCoachLine(id: "lap-done", title: "Lap done", body: "Finish, or take your break.")
            }
            coachJournal.record(.shown, lap ? "Lap done: block-end window back." : "Block-end window back at +10 min.", code: .stretch, at: now)
            showSessionComplete = true
            showCompletionWindow()
        }
    }

    // Return

    /// Break end (§3.2, learner B): the return panel with probability 0.7, else only the
    /// notification and the break-over window. Every decision is logged for the lift estimate.
    private func beginReturnLadder(now: Date) {
        guard let settings, settings.coachOnScreenPromptsEnabled, settings.coachIdleStarterEnabled else {
            returnLadderTreated = false
            return
        }
        let treated = cycleArmOverride ?? (Double.random(in: 0..<1) < CoachCycleExperiment.probability)
        returnLadderTreated = treated
        if !isEvidenceMode {
            CoachCycleLog(defaults: defaults).append(.init(at: now, treated: treated, propensity: CoachCycleExperiment.probability))
        }
        coachJournal.record(treated ? .shown : .quiet, treated ? "Return panel at break end." : "Return panel held back (control).",
                            code: .returnLadder, propensity: CoachCycleExperiment.probability, at: now)
        if treated { presentReturnPanel(reentry: false, now: now) }
    }

    func presentReturnPanel(reentry: Bool, now: Date = Date()) {
        let next = latestNextStep(now: now)
        let sizes = CoachReturnLadder.sizes(regular: regularMinutes, reentry: reentry)
        let hook: String
        let detail: String?
        if reentry {
            hook = next.map { "Start 5m on “\(CoachMessageComposer.shortName($0))”?" } ?? "Start 5 minutes. Just get back in."
            detail = "Breaks this long rarely end on their own. Five minutes is enough to be back."
        } else {
            hook = next.map { "Back to: \(CoachMessageComposer.shortName($0))" } ?? "Break's over. Back in?"
            let hazard = returnHazard(now: now)
            detail = hazard.episodes >= CoachReturnHazard.minEpisodes
                ? "After a break you're back within 5 min \(Int((hazard.startedWithin(5) * 100).rounded()))% of the time. Make this one of them."
                : nil
        }
        let projectID = completedBlockContext?.projectId ?? breakEpisodeContext?.earnedBlock.projectId ?? selectedProject?.id
        var target = CoachStartTarget(minutes: sizes.first ?? regularMinutes, name: completedBlockContext?.projectName ?? selectedProject?.name,
                                      projectID: projectID, priorityID: nil)
        target.taskTitle = next
        let message = CoachComposedMessage(
            style: settings?.coachStyle ?? .challenger, trigger: .startNudge,
            hook: hook, detail: detail.map { .line($0) }, primaryTitle: "Start \(target.minutes)m", hookIsFact: false
        )
        presentCoachPanel(CoachPanelPresentation(kind: .returnFromBreak, message: message, plan: target, createdAt: now,
                                                 sizeOptions: sizes, recommendedMinutes: sizes.first))
    }

    private func handleBreakOvertimeStep(now: Date = Date()) {
        let reentry = returnHazard(now: now).reentryMinute * 60
        switch CoachReturnLadder.step(overrunSeconds: overtimeSeconds, reentrySeconds: reentry) {
        case .none:
            return
        case .reentry:
            guard returnLadderTreated, coachPanel == nil || coachPanel?.kind == .returnFromBreak else { return }
            coachJournal.record(.shown, "Re-entry offer at +\(reentry / 60) min.", code: .returnLadder, at: now)
            presentReturnPanel(reentry: true, now: now)
        case .close:
            coachJournal.record(.logged, "Break closed \(CoachReturnLadder.closeSeconds / 60) min over.", code: .returnLadder, at: now)
            if coachPanel?.kind == .returnFromBreak { hideCoachPanel() }
            suppressBackAtOffer = true
            continueAfterCompletion(action: .endSession)
        }
    }

    /// Starts the next block from the return panel (the break is still pending completion).
    private func startFromReturnPanel(minutes: Int, now: Date = Date()) -> Bool {
        let previous = selectedMinutes
        selectedMinutes = minutes
        if pendingIntentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let next = latestNextStep(now: now) {
            pendingIntentText = next
        }
        coachJournal.record(.started, "Back from break: \(minutes)m.", code: .returnLadder, at: now)
        continueAfterCompletion(action: .continueFocusing)
        selectedMinutes = previous
        interventionActionTaken = true
        if coachPanel?.kind == .returnFromBreak { hideCoachPanel() }
        return state == .focusing
    }

    // Walk-away

    /// "Done for today" before 19:00 with the goal not met (§3.3): "Back at…?" A chip plans a
    /// block with its cue; "Really done" closes it. Never blocks the ending itself.
    private func offerBackAt(now: Date) {
        defer { suppressBackAtOffer = false }
        guard !suppressBackAtOffer, let settings, settings.coachOnScreenPromptsEnabled, settings.coachIdleStarterEnabled,
              !isPrivate, coachPanel == nil, pauseScreen == nil, canUsePlannedBlocks(),
              Calendar.current.component(.hour, from: now) < 19,
              currentPacing(now: now).tier != .goalMet else { return }
        let next = latestNextStep(now: now)
        let message = CoachComposedMessage(
            style: settings.coachStyle, trigger: .startNudge,
            hook: "Back at…?",
            detail: .line(next.map { "Pick a time and I'll cue it. Your next step waits: \($0)." } ?? "Pick a time and I'll cue it."),
            primaryTitle: "", hookIsFact: false
        )
        coachJournal.record(.shown, "Back at…? offered.", code: .backAt, at: now)
        presentCoachPanel(CoachPanelPresentation(kind: .question, message: message, createdAt: now, questionID: "back_at", choices: [
            CoachQuestionChoice(id: "30", title: "In 30 min"),
            CoachQuestionChoice(id: "60", title: "In 1 hour"),
            CoachQuestionChoice(id: "120", title: "In 2 hours"),
            CoachQuestionChoice(id: "done", title: "Really done"),
        ]))
    }

    // MARK: Day ledger (coach v8 §3.1)

    @ObservationIgnored private var calendarLabelsRefreshedDay: Date?

    private var storesDayLedger: Bool {
        modelContext?.container.schema.entities.contains { $0.name == "DayLabel" } ?? false
    }

    /// Once a day: leave and holiday marks from the calendar for the last 120 and next 14 days,
    /// stored as `DayLabel(source: .calendar)`. A user's own label is never replaced.
    func refreshCalendarDayLabels(now: Date = Date(), force: Bool = false) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        guard !isEvidenceMode, storesDayLedger, let modelContext, force || calendarLabelsRefreshedDay != today,
              CalendarService.shared.authStatus == .authorized,
              let start = calendar.date(byAdding: .day, value: -120, to: today),
              let end = calendar.date(byAdding: .day, value: 15, to: today) else { return }
        calendarLabelsRefreshedDay = today
        let marks = CalendarService.shared.dayMarks(from: start, to: end)
        let existing = (try? modelContext.fetch(FetchDescriptor<DayLabel>(predicate: #Predicate { $0.day >= start }))) ?? []
        var byDay = Dictionary(existing.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
        for (day, mark) in marks {
            let type: DayType = mark == .leave ? .leave : .holiday
            if let label = byDay[day] {
                if label.source == .calendar, label.type != type { label.typeRaw = type.rawValue }
            } else {
                let label = DayLabel(day: day, type: type, source: .calendar)
                modelContext.insert(label)
                byDay[day] = label
            }
        }
        // A calendar mark that went away (event deleted) goes too.
        for label in existing where label.source == .calendar && marks[label.day] == nil {
            modelContext.delete(label)
        }
        saveContext()
    }

    /// The user's answer for a day ("On leave?" or a change in Insights).
    func setDayType(_ day: Date, type: DayType) {
        guard storesDayLedger, let modelContext else { return }
        let start = Calendar.current.startOfDay(for: day)
        let labels = (try? modelContext.fetch(FetchDescriptor<DayLabel>(predicate: #Predicate { $0.day == start }))) ?? []
        labels.forEach(modelContext.delete)
        modelContext.insert(DayLabel(day: start, type: type, source: .user))
        saveContext()
        todayTypeCache = nil
        goalProgressCache = nil
    }

    /// Today's day type when it is settled (`DayTargets.isSettled`), cached for 10 minutes.
    /// An inferred leave stays a workday for the goal until you answer "On leave?".
    func settledDayType(now: Date = Date()) -> DayType? {
        if let cached = todayTypeCache, now.timeIntervalSince(cached.at) < 600, cached.at <= now,
           Calendar.current.isDate(cached.at, inSameDayAs: now) {
            return cached.settled
        }
        guard let today = dayLedger(days: 1, now: now).last else { return nil }
        let settled = DayTargets.isSettled(today.classification) ? today.type : DayType.workday
        todayTypeCache = (now, today.type, settled)
        return settled
    }

    /// Your own-work targets per day type (nil: follows the daily goal).
    func dayTargets() -> [DayType: Int] { DayTargetStore(defaults: defaults).all }

    /// Sets (or with nil clears) your target for a day type; the goal and the ledger use it at once.
    func setDayTarget(_ minutes: Int?, for type: DayType) {
        DayTargetStore(defaults: defaults).set(minutes, for: type)
        todayTypeCache = nil
        goalProgressCache = nil
        dayTargetsRevision += 1
    }

    /// One day, hour by hour (`DayTimeline`). Read-only (safe in `body`).
    func dayTimeline(_ day: Date, now: Date = Date()) -> DayTimeline {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        guard let modelContext else { return DayTimeline.build(day: start, rows: [], blocks: [], isPull: { _, _, _ in false }) }
        let sessions = (try? modelContext.fetch(FetchDescriptor<FocusSession>(predicate: #Predicate { $0.startedAt >= start && $0.startedAt < end }))) ?? []
        let projects = (try? modelContext.fetch(FetchDescriptor<Project>())) ?? []
        let ownConfigured = GoalDataBuilder.ownWorkConfigured(projects)
        let blocks = sessions.filter { $0.type == .focus }.map { session in
            DayTimeline.Block(start: session.startedAt, end: session.endedAt ?? min(now, session.startedAt.addingTimeInterval(session.actualDuration)),
                              own: !ownConfigured || CoachHistoryReader.isOwnWork(session.project))
        }
        let rows: [DayTimeline.Row] = storesDayLedger
            ? ((try? modelContext.fetch(FetchDescriptor<ActivityHour>(predicate: #Predicate { $0.hourStart >= start && $0.hourStart < end }))) ?? [])
                .map { DayTimeline.Row(hourStart: $0.hourStart, key: $0.key, label: $0.label, inBlock: $0.inBlock, seconds: $0.seconds) }
            : []
        let book = appRoleBook(now: now)
        let type = dayLedger(days: 1, now: start.addingTimeInterval(12 * 3600)).last?.type ?? .workday
        let windows = effectiveOwnWorkWindows(now: now)
        return DayTimeline.build(day: start, rows: rows, blocks: blocks, isPull: { key, label, hour in
            let minute = hour * 60
            let inWindow = windows.contains { minute >= $0.startMinute && minute < $0.endMinute }
            let context = AppContext.outsideBlock(dayType: type, hour: hour, inOwnWindow: inWindow)
            return book.role(key: key, name: label, in: context).role == .pull
        }, calendar: calendar)
    }

    /// The ledger, oldest first, for the `days` days ending today. Read-only (safe in `body`).
    func dayLedger(days: Int, now: Date = Date()) -> [DayEntry] {
        guard let modelContext, days > 0 else { return [] }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: -(days - 1), to: today),
              let end = calendar.date(byAdding: .day, value: 1, to: today) else { return [] }

        let sessions = (try? modelContext.fetch(FetchDescriptor<FocusSession>(predicate: #Predicate { $0.startedAt >= start && $0.startedAt < end }))) ?? []
        let usage = (try? modelContext.fetch(FetchDescriptor<AppUsageEntry>(predicate: #Predicate { $0.date >= start && $0.date < end }))) ?? []
        let projects = (try? modelContext.fetch(FetchDescriptor<Project>())) ?? []
        let ownConfigured = GoalDataBuilder.ownWorkConfigured(projects)
        let labels = storesDayLedger ? ((try? modelContext.fetch(FetchDescriptor<DayLabel>(predicate: #Predicate { $0.day >= start && $0.day < end }))) ?? []) : []
        let hours = storesDayLedger ? ((try? modelContext.fetch(FetchDescriptor<ActivityHour>(predicate: #Predicate { $0.hourStart >= start && $0.hourStart < end }))) ?? []) : []
        let planned = canUsePlannedBlocks() ? plannedBlocks(from: start, to: end) : []
        let tasks = (try? modelContext.fetch(FetchDescriptor<DailyTask>(predicate: #Predicate { $0.day >= start && $0.day < end }))) ?? []
        let keys = currentDriftRuleKeys(now: now)
        let targets = DayTargetStore(defaults: defaults).all

        var entries: [DayEntry] = []
        var day = start
        while day < end {
            let next = calendar.date(byAdding: .day, value: 1, to: day) ?? end
            let daySessions = sessions.filter { $0.type == .focus && $0.startedAt >= day && $0.startedAt < next && $0.endedAt != nil }
            let minutes: (FocusSession) -> Double = { $0.actualDuration / 60 }
            let ownMinutes = daySessions.filter { !ownConfigured || CoachHistoryReader.isOwnWork($0.project) }.map(minutes).reduce(0, +)
            let workBlockMinutes = ownConfigured
                ? daySessions.filter { $0.project?.areaRaw != nil && $0.project?.area == .work }.map(minutes).reduce(0, +)
                : 0
            let dayUsage = usage.filter { $0.date >= day && $0.date < next }
            let appRows = dayUsage.filter { !$0.bundleIdentifier.hasPrefix("domain:") && !AppUsageTracker.isIgnoredSystemBundleIdentifier($0.bundleIdentifier) && $0.bundleIdentifier != "com.apple.loginwindow" }
            let seconds: (AppUsageEntry) -> Double = { Double($0.duringFocusSeconds + $0.outsideFocusSeconds) }
            let officeSeconds = dayUsage.filter { OfficeActivity.isOffice(key: $0.bundleIdentifier) || OfficeActivity.isOffice(key: $0.appName) }.map(seconds).reduce(0, +)
            let activeMinutes = appRows.map(seconds).reduce(0, +) / 60
            let derailSeconds = dayUsage.filter {
                DerailerClassifier.isDerailer(UsageSample($0), confirmedKeys: keys.confirmed, allowedKeys: keys.allowed)
            }.map { Double($0.outsideFocusSeconds) }.reduce(0, +)
            let dayHours = hours.filter { $0.hourStart >= day && $0.hourStart < next }
            let callMinutes = dayHours.isEmpty ? nil : Double(dayHours.filter { $0.key == "call" }.map(\.seconds).reduce(0, +)) / 60
            let awayMinutes = dayHours.isEmpty ? nil : Double(dayHours.filter { $0.key == "away" }.map(\.seconds).reduce(0, +)) / 60

            let label = labels.filter { $0.day == day }.sorted { $0.source == .user && $1.source != .user }.first
            let signals = DaySignals(
                day: day,
                userLabel: label?.source == .user ? label?.type : nil,
                calendarMark: label?.source == .calendar ? (label?.type == .leave ? .leave : .holiday) : nil,
                officeMinutes: officeSeconds / 60 + workBlockMinutes + (callMinutes ?? 0),
                activeMinutes: max(activeMinutes, daySessions.map(minutes).reduce(0, +))
            )
            let classification = DayClassifier.classify(signals, now: now, calendar: calendar)

            // Planned: a block planned for the day, or a task you added for it, before you acted.
            let firstStart = daySessions.map(\.startedAt).min() ?? next
            let hadPlan = planned.contains { calendar.isDate($0.day, inSameDayAs: day) && $0.createdAt < min(firstStart, $0.startAt) }
                || tasks.contains { calendar.isDate($0.day, inSameDayAs: day) && $0.reminderID == nil && $0.carriedFromID == nil && $0.createdAt < firstStart }

            let goalMinutes = Int(GoalDataBuilder.dailyGoal(projects: projects, settings: settings, on: day, calendar: calendar).seconds / 60)
            let target = DayTargets.minutes(type: classification.type, yours: targets[classification.type], goalMinutes: goalMinutes)
            entries.append(DayEntry(
                day: day, classification: classification, planned: hadPlan,
                ownMinutes: ownMinutes, officeMinutes: signals.officeMinutes, callMinutes: callMinutes, awayMinutes: awayMinutes,
                derailMinutes: derailSeconds / 60, targetMinutes: target,
                verdict: DayVerdict.of(planned: hadPlan, ownMinutes: ownMinutes, targetMinutes: target, isPast: next <= now)
            ))
            day = next
        }
        return entries
    }

    // MARK: Apps in context (coach v8 §3.3)

    @ObservationIgnored private var appRoleBookCache: (at: Date, book: AppRoleBook, names: [String: String])?
    @ObservationIgnored private var todayTypeCache: (at: Date, type: DayType, settled: DayType)?
    /// Bumped when a day-type target changes, so pages showing targets redraw.
    private(set) var dayTargetsRevision = 0

    private var storesAppRoles: Bool {
        modelContext?.container.schema.entities.contains { $0.name == "AppRoleRuleRecord" } ?? false
    }

    /// Your rules (global distraction rules plus per-project and per-area roles) and what your
    /// blocks show, refreshed every 5 minutes or after a change. Read-only on the store.
    func appRoleBook(now: Date = Date()) -> AppRoleBook {
        if let cached = appRoleBookCache, now.timeIntervalSince(cached.at) < 300, cached.at <= now { return cached.book }
        let built = buildAppRoleBook(now: now)
        appRoleBookCache = (now, built.book, built.names)
        return built.book
    }

    /// Display names seen for each key (hourly labels and daily app names).
    func appRoleNames(now: Date = Date()) -> [String: String] {
        _ = appRoleBook(now: now)
        return appRoleBookCache?.names ?? [:]
    }

    func invalidateAppRoles() {
        appRoleBookCache = nil
        driftRuleKeys = nil
    }

    private func buildAppRoleBook(now: Date) -> (book: AppRoleBook, names: [String: String]) {
        var book = AppRoleBook()
        var names: [String: String] = [:]
        guard let modelContext else { return (book, names) }
        let items = (try? modelContext.fetch(FetchDescriptor<IdleDistractionItem>())) ?? []
        for item in items where item.status == .active {
            book.rules.append(AppRoleRule(key: item.key.lowercased(), scope: .everywhere, role: item.severity == .allowed ? .tool : .pull))
        }
        if storesAppRoles {
            let records = (try? modelContext.fetch(FetchDescriptor<AppRoleRuleRecord>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))) ?? []
            // Newest first, so a later answer for the same scope wins.
            book.rules = records.map(\.rule) + book.rules
            for record in records { names[record.key] = record.displayName }
        }

        let calendar = Calendar.current
        let since = calendar.startOfDay(for: now.addingTimeInterval(-28 * 86_400))
        var hourDays = Set<Date>()
        if storesDayLedger {
            let hours = (try? modelContext.fetch(FetchDescriptor<ActivityHour>(predicate: #Predicate { $0.hourStart >= since && $0.inBlock }))) ?? []
            for hour in hours {
                guard let projectID = hour.projectID, hour.key != "away", hour.key != "call" else { continue }
                let key = AppRoleBook.normalize(hour.key)
                let day = calendar.startOfDay(for: hour.hourStart)
                hourDays.insert(day)
                book.evidence[key, default: [:]][projectID, default: AppRoleEvidence()].minutes += Double(hour.seconds) / 60
                book.evidence[key, default: [:]][projectID, default: AppRoleEvidence()].days.insert(day)
                names[key] = names[key] ?? hour.label
            }
        }
        // Before the hourly rollup: days whose blocks were all one project lend it that day's
        // in-block app time (the daily rows know "in a block", not which block).
        let sessions = (try? modelContext.fetch(FetchDescriptor<FocusSession>(predicate: #Predicate { $0.startedAt >= since }))) ?? []
        let projectByDay = Dictionary(grouping: sessions.filter { $0.type == .focus }, by: { calendar.startOfDay(for: $0.startedAt) })
            .compactMapValues { day -> UUID? in
                let ids = Set(day.compactMap { $0.project?.id })
                return ids.count == 1 && day.allSatisfy { $0.project != nil } ? ids.first : nil
            }
        let usage = (try? modelContext.fetch(FetchDescriptor<AppUsageEntry>(predicate: #Predicate { $0.date >= since && $0.duringFocusSeconds > 0 }))) ?? []
        for entry in usage {
            let day = calendar.startOfDay(for: entry.date)
            guard !hourDays.contains(day), let projectID = projectByDay[day] else { continue }
            let key = AppRoleBook.normalize(entry.bundleIdentifier)
            book.evidence[key, default: [:]][projectID, default: AppRoleEvidence()].minutes += Double(entry.duringFocusSeconds) / 60
            book.evidence[key, default: [:]][projectID, default: AppRoleEvidence()].days.insert(day)
            names[key] = names[key] ?? entry.appName
        }
        // Block reviews where you kept an app for a project ("planned").
        if let memory = coachEngine.driftMemoryStore?.memory {
            for (compound, count) in memory.plannedCounts(now: now) {
                let parts = compound.split(separator: "|").map(String.init)
                guard parts.count == 3, let projectID = UUID(uuidString: parts[0]) else { continue }
                book.evidence[AppRoleBook.normalize(parts[2]), default: [:]][projectID, default: AppRoleEvidence()].plannedMarks += count
            }
        }
        return (book, names)
    }

    /// Where you are now, for app roles.
    func currentAppContext(now: Date = Date()) -> AppContext {
        if state == .focusing || state == .paused {
            if let project = selectedProject { return .project(project.id, AreaGroup.of(project.areaRaw == nil ? nil : project.area)) }
            return .own
        }
        _ = settledDayType(now: now)
        let type = todayTypeCache?.type ?? (DayType.isWeekend(now) ? .weekend : .workday)
        return AppContext.outsideBlock(dayType: type, hour: Calendar.current.component(.hour, from: now), inOwnWindow: currentOwnWorkWindow(now: now) != nil)
    }

    func appRole(key: String, name: String, now: Date = Date()) -> AppRoleDecision {
        appRoleBook(now: now).role(key: key, name: name, in: currentAppContext(now: now))
    }

    /// "Distraction / It's work" with a scope (coach v8): everywhere writes the old global rule;
    /// an area or a project writes an `AppRoleRuleRecord`, replacing the same key and scope.
    func setAppRole(key rawKey: String, kind: DerailerTarget.Kind, name: String, scope: AppRoleScope, role: AppRole) {
        guard let modelContext else { return }
        let key = AppRoleBook.normalize(rawKey)
        if scope == .everywhere {
            try? DistractionRuleWriter.mark(kind: kind == .website ? .website : .app, key: key, name: name,
                                            as: role == .tool ? .allowed : .minor, source: .manual, in: modelContext)
        } else if storesAppRoles {
            let probe = AppRoleRuleRecord(key: key, displayName: name, scope: scope, role: role)
            let kindRaw = probe.scopeKindRaw, value = probe.scopeValue
            let existing = (try? modelContext.fetch(FetchDescriptor<AppRoleRuleRecord>(predicate: #Predicate { $0.key == key && $0.scopeKindRaw == kindRaw && $0.scopeValue == value }))) ?? []
            existing.forEach(modelContext.delete)
            if role != .neutral { modelContext.insert(probe) }
            saveContext()
        }
        invalidateAppRoles()
    }

    /// The tracker's category for the frontmost app during a block: your roles first.
    func contextualCategory(_ base: AppUsageEntry.AppCategory, key: String, name: String, now: Date = Date()) -> AppUsageEntry.AppCategory {
        let decision = appRole(key: key, name: name, now: now)
        guard decision.source != .standard else { return base }
        switch decision.role {
        case .pull: return .distracting
        case .tool: return .productive
        case .neutral: return base
        }
    }

    /// An office tool or a default pull open in an own-work project's blocks: ask which it is.
    func appRoleQuestion(now: Date = Date()) -> CoachQuestion? {
        guard let modelContext else { return nil }
        let book = appRoleBook(now: now)
        let projects = (try? modelContext.fetch(FetchDescriptor<Project>(predicate: #Predicate { !$0.archived }))) ?? []
        let own = Set(projects.filter { $0.areaRaw == nil || $0.area.isOwnWork }.map(\.id))
        // Only the last 7 days' evidence counts for asking.
        let weekAgo = Calendar.current.startOfDay(for: now.addingTimeInterval(-7 * 86_400))
        var recent = book.evidence
        for (key, byProject) in recent {
            for (id, found) in byProject {
                var trimmed = found
                trimmed.days = found.days.filter { $0 >= weekAgo }
                if trimmed.days.isEmpty { recent[key]?[id] = nil } else { recent[key]?[id] = trimmed }
            }
        }
        guard let candidate = AppRoleQuestionPicker.pick(evidence: recent, names: appRoleNames(now: now), ownProjects: own, book: book),
              let project = projects.first(where: { $0.id == candidate.projectID }) else { return nil }
        return .appRole(key: candidate.key, name: candidate.name, projectID: project.id, projectName: project.name, days: candidate.days)
    }

    /// Today, when the coach should ask what kind of day it is (likely leave, not yet answered).
    func dayTypeQuestion(now: Date = Date()) -> CoachQuestion? {
        guard storesDayLedger, let today = dayLedger(days: 1, now: now).last else { return nil }
        let c = today.classification
        guard c.source == .inferred, c.type == .leave, c.confidence < DayClassification.askBelow else { return nil }
        return .dayType(day: today.day, inferred: c.type, reason: c.reason)
    }

    // MARK: Quick questions (coach v6 §3.4)

    /// The questions the coach has right now, most useful first (snoozed ones included).
    func coachQuestionCandidates(now: Date = Date()) -> [CoachQuestion] {
        let declared = settings?.coachOwnWorkWindows ?? []
        refreshWindowFit(now: now)
        var questions: [CoachQuestion] = []
        // Coach v8: what kind of day it is decides every target, so it is asked first.
        if let day = dayTypeQuestion(now: now) { questions.append(day) }
        if let role = appRoleQuestion(now: now) { questions.append(role) }
        if let fit = windowFit, fit.isMismatch(declared: declared), !keepsDeclaredWindows(now: now) {
            questions.append(.windowFit(fit, declared: declared))
        }
        if let project = unclassifiedProjectQuestion(now: now) { questions.append(project) }
        let regular = regularMinutes
        if let minutes = CoachNaturalLength.suggestion(cycleSessions(since: now.addingTimeInterval(-30 * 86_400)), regularMinutes: regular) {
            questions.append(.naturalLength(minutes: minutes, regular: regular))
        }
        return questions
    }

    /// The question the coach would ask now: the first one not snoozed by "Not now".
    func pendingCoachQuestion(now: Date = Date()) -> CoachQuestion? {
        let store = CoachQuestionStore(defaults: defaults)
        return coachQuestionCandidates(now: now).first { question in
            store.snoozedUntil(question.id).map { $0 <= now } ?? true
        }
    }

    /// "Is ProjectWork your own work, or your day job?" (`CoachQuestion.unclassifiedProject`).
    func unclassifiedProjectQuestion(now: Date = Date()) -> CoachQuestion? {
        guard let context = modelContext,
              let projects = try? context.fetch(FetchDescriptor<Project>(predicate: #Predicate { !$0.archived })) else { return nil }
        let since = now.addingTimeInterval(-TimeInterval(CoachWindowFit.lookbackDays) * 86_400)
        let sessions = historyReader?.focusSessions(since: since) ?? []
        let counts = Dictionary(grouping: sessions.compactMap { $0.project?.id }, by: { $0 }).mapValues(\.count)
        return CoachQuestion.unclassifiedProject(projects.map {
            (id: $0.id, name: $0.name, hasArea: $0.areaRaw != nil, isWork: $0.areaRaw != nil && $0.area == .work, blocks: counts[$0.id] ?? 0)
        })
    }

    /// Runs once a minute. At most one question a day, at a breakpoint with someone at the desk.
    @discardableResult
    func evaluateCoachQuestion(now: Date = Date()) -> Bool {
        guard let settings, settings.coachOnScreenPromptsEnabled, settings.coachIdleStarterEnabled,
              let question = pendingCoachQuestion(now: now) else { return false }
        let store = CoachQuestionStore(defaults: defaults)
        let input = CoachQuestionPolicy.Input(
            now: now,
            askedToday: store.askedToday(now: now),
            sessionActive: state != .idle || isOvertime,
            panelShowing: coachPanel != nil || pauseScreen != nil,
            quietHours: CoachGuardrails.isQuietHours(now, start: settings.coachQuietStartMinute, end: settings.coachQuietEndMinute),
            screenShare: shouldSuppressGuardianPopups(using: settings),
            userIdleSeconds: systemIdleSeconds(),
            questionSnoozedUntil: nil
        )
        guard CoachQuestionPolicy.mayAsk(input) else { return false }
        store.markAsked(now: now)
        presentCoachQuestion(question, now: now)
        return coachPanel?.kind == .question
    }

    func presentCoachQuestion(_ question: CoachQuestion, now: Date = Date()) {
        let message = CoachComposedMessage(
            style: settings?.coachStyle ?? .challenger,
            trigger: .startNudge,
            hook: question.hook,
            detail: .line(question.detail),
            primaryTitle: "",
            hookIsFact: true
        )
        coachJournal.record(.shown, "Quick question: \(question.hook)", code: .question, at: now)
        presentCoachPanel(CoachPanelPresentation(kind: .question, message: message, createdAt: now, questionID: question.id, choices: question.choices))
    }

    /// A quick question was answered: act on it now.
    func answerCoachQuestion(_ choice: CoachQuestionChoice, now: Date = Date()) {
        guard let panel = coachPanel, panel.kind == .question else { return }
        switch panel.questionID {
        case "window_fit":
            if let answer = CoachQuestion.WindowFitAnswer(rawValue: choice.id), let settings {
                applyWindowFitAnswer(answer, settings: settings, now: now)
            }
        case "back_at":
            if let minutes = Int(choice.id) {
                let at = now.addingTimeInterval(TimeInterval(minutes * 60))
                if insertPlannedBlock(at: at, now: now) != nil {
                    coachJournal.record(.logged, "Back at \(Self.clockLabel(at)): planned.", code: .backAt, at: now)
                }
            } else {
                coachJournal.record(.declined, "Really done for today.", code: .backAt, at: now)
            }
        case "natural_length":
            applyNaturalLengthAnswer(choice, now: now)
        case let id? where id.hasPrefix("app_role."):
            if case .appRole(let key, let name, let projectID, _, _)? = coachQuestionCandidates(now: now).first(where: { $0.id == id }),
               let role = AppRole(rawValue: choice.id) {
                setAppRole(key: key, kind: AppRoleBook.isHost(key) ? .website : .app, name: name, scope: .project(projectID), role: role)
                coachJournal.record(.logged, "\(name): \(role.title.lowercased()) for this project.", code: .question, at: now)
            }
        case let id? where id.hasPrefix("day_type."):
            if let type = DayType(rawValue: choice.id) {
                setDayType(now, type: type)
                coachJournal.record(.logged, "Today is a \(type.title.lowercased()).", code: .question, at: now)
            }
        case let id? where id.hasPrefix("project_area."):
            if let uuid = UUID(uuidString: String(id.dropFirst("project_area.".count))), let area = ProjectArea(rawValue: choice.id) {
                setProjectArea(uuid, area: area)
            }
        default:
            break
        }
        coachJournal.record(.logged, "Quick question answered: \(choice.title).", code: .question, at: now)
        interventionActionTaken = true
        hideCoachPanel()
    }

    /// "Not now" or "Keep…" holds this question back (Insights hides it too).
    func isCoachQuestionSnoozed(_ id: String, now: Date = Date()) -> Bool {
        CoachQuestionStore(defaults: defaults).snoozedUntil(id).map { $0 > now } ?? false
    }

    /// "Make it 35 min" / "Keep 25 min" (coach v7 §3.1; also offered in Insights).
    func applyNaturalLengthAnswer(_ choice: CoachQuestionChoice, now: Date = Date()) {
        if let minutes = Int(choice.id) {
            settings?.focusDuration = TimeInterval(minutes * 60)
            selectedMinutes = minutes
            saveContext()
        } else {
            CoachQuestionStore(defaults: defaults).snooze("natural_length", until: now.addingTimeInterval(30 * 86_400))
        }
    }

    /// Sets a project's area from a quick question (also offered in Insights).
    func setProjectArea(_ projectID: UUID, area: ProjectArea) {
        guard let context = modelContext,
              let project = try? context.fetch(FetchDescriptor<Project>(predicate: #Predicate { $0.id == projectID })).first else { return }
        project.area = area
        saveContext()
        refreshWindowFit(now: Date(), force: true)
    }

    /// Applies the window question's answer (also offered in Insights).
    func applyWindowFitAnswer(_ answer: CoachQuestion.WindowFitAnswer, settings: AppSettings, now: Date = Date()) {
        refreshWindowFit(now: now)
        let declared = settings.coachOwnWorkWindows
        if let fit = windowFit, let windows = CoachQuestion.windows(after: answer, declared: declared, fit: fit) {
            settings.coachOwnWorkWindows = windows
            saveContext()
            refreshWindowFit(now: now, force: true)
        }
        if answer == .keepMine {
            defaults.set(now.addingTimeInterval(CoachQuestionPolicy.keepMineCooldown), forKey: Self.keepDeclaredWindowsUntilKey)
        } else {
            defaults.removeObject(forKey: Self.keepDeclaredWindowsUntilKey)
        }
    }

    /// Runs once a minute. In the evening, once, at a breakpoint: "When are tomorrow's 2 blocks?"
    @discardableResult
    func evaluatePlanTomorrowCheckIn(now: Date = Date()) -> Bool {
        guard let settings, canUsePlannedBlocks(), settings.coachOnScreenPromptsEnabled, settings.coachIdleStarterEnabled else { return false }
        let store = CoachPlanTomorrowStore(defaults: defaults)
        let input = CoachPlanTomorrow.Input(
            now: now,
            enabled: settings.coachPlanTomorrowEnabled ?? true,
            plannedTomorrow: tomorrowPlans(now: now).count,
            askedToday: store.askedToday(now: now),
            sessionActive: state != .idle || isOvertime,
            quietHours: CoachGuardrails.isQuietHours(now, start: settings.coachQuietStartMinute, end: settings.coachQuietEndMinute),
            screenShare: shouldSuppressGuardianPopups(using: settings),
            panelShowing: coachPanel != nil || pauseScreen != nil,
            userIdleSeconds: systemIdleSeconds(),
            lastWindowEndMinute: settings.coachOwnWorkWindows.map(\.endMinute).max()
        )
        guard CoachPlanTomorrow.shouldAsk(input) else { return false }
        let slots = planTomorrowSlots(now: now)
        guard !slots.isEmpty else { return false }
        store.markAsked(now: now)
        let style = settings.coachStyle
        let attempt = coachEngine.recordDeliveredIntervention(
            kind: .strongPrompt, riskScore: 0, sessionId: nil, now: now,
            surface: .panel, style: style, contextKey: CoachPlanTomorrow.contextKey
        )
        let message = planTomorrowMessage(style: style, planned: tomorrowPlans(now: now))
        coachJournal.record(
            .shown, "Plan tomorrow: offered \(slots.map { $0.label() }.joined(separator: ", ")).",
            code: .planTomorrow, attemptID: attempt.id, hook: message.hook, at: now
        )
        presentCoachPanel(CoachPanelPresentation(kind: .planTomorrow, message: message, attemptID: attempt.id, createdAt: now, planSlots: slots))
        return true
    }

    private func planTomorrowMessage(style: CoachStyle, planned: [PlannedBlock]) -> CoachComposedMessage {
        let remaining = CoachPlanTomorrow.blocks - planned.count
        let hook = planned.isEmpty
            ? "When are tomorrow's \(CoachPlanTomorrow.blocks) blocks?"
            : "\(planned.map { Self.clockLabel($0.startAt) }.joined(separator: " and ")) is set. When's the \(remaining == 1 ? "second" : "next")?"
        return CoachComposedMessage(
            style: style,
            trigger: .dailyPlan(goalMinutes: 0, firstSuggestion: nil),
            hook: hook,
            detail: .line("Decide tonight and you only have to start. I'll be on screen at each time."),
            primaryTitle: "",
            hookIsFact: false
        )
    }

    /// A time chip on the plan-tomorrow check-in: plans that block, then asks for the next one
    /// until tomorrow has two.
    @discardableResult
    func commitTomorrowSlot(_ slot: CoachPlanSlot, now: Date = Date()) -> PlannedBlock? {
        guard let block = insertPlannedBlock(at: slot.start, now: now) else { return nil }
        let panel = coachPanel
        let planned = tomorrowPlans(now: now)
        log("coach plan: tomorrow \(slot.label()) · \(block.minutes)m")
        coachJournal.record(.logged, "Planned tomorrow \(slot.label()) (\(block.minutes)m).", code: .planTomorrow, attemptID: panel?.attemptID, at: now)
        interventionActionTaken = true
        let style = settings?.coachStyle ?? .challenger
        if planned.count < CoachPlanTomorrow.blocks, let panel, panel.kind == .planTomorrow {
            let slots = planTomorrowSlots(now: now)
            if !slots.isEmpty {
                interventionActionTaken = false
                presentCoachPanel(CoachPanelPresentation(
                    kind: .planTomorrow, message: planTomorrowMessage(style: style, planned: planned),
                    attemptID: panel.attemptID, createdAt: panel.createdAt, planSlots: slots
                ))
                return block
            }
        }
        if let panel { coachEngine.recordInterventionOutcome(.improved, attemptID: panel.attemptID) }
        let times = planned.map { Self.clockLabel($0.startAt) }.joined(separator: " and ")
        presentCoachPanel(CoachPanelPresentation(
            kind: .notice,
            message: CoachComposedMessage(
                style: style,
                trigger: .dailyPlan(goalMinutes: 0, firstSuggestion: nil),
                hook: "Tomorrow: \(times).",
                detail: .line("I'll be on screen at each time. Be ready."),
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
        guard !isPrivate else { return }
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
            // The button names the next step; start that when there is one (same rule as ⌃⌥Space).
            let target = coachSnapshot(now: now, idleSeconds: 0, frontmostCategory: AppUsageTracker.shared.currentFrontmostCategory).target
            if target.taskTitle != nil {
                var plan = target
                plan.minutes = CoachStarterBlock.clampedMinutes(settings?.coachStarterBlockMinutes ?? 5)
                return startCoachPlan(plan, attemptID: screen.attemptID)
            }
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
        // With a concrete next step (a task or today's lever), start it at the learned size;
        // otherwise the starter block's job is to find the step.
        let snapshot = coachSnapshot(now: Date(), idleSeconds: 0, frontmostCategory: AppUsageTracker.shared.currentFrontmostCategory)
        if snapshot.target.taskTitle != nil {
            return startNextBlock(minutes: startLadderRecommendation().minutes)
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
        case .taskTooBig, .unclearNextStep:
            return nil
        }
    }

    private func shouldSuppressGuardianPopups(using settings: AppSettings) -> Bool {
        isPrivate || screenShareGuard.shouldSuppressGuardianPopups(
            enabled: settings.coachSuppressPopupsDuringScreenShare
        )
    }

    // MARK: Hide while sharing my screen (SharePrivacy)

    /// FocusFlow is hiding itself: the screen is being shared, or "Private now" is set.
    private(set) var isPrivate = false
    /// "Private now" from the popover. Not saved: a relaunch starts visible.
    private(set) var isPrivateManual = false
    @ObservationIgnored private var lastSharedAt: Date?
    @ObservationIgnored private var privacyTimer: Timer?
    /// The block ended while private: the window opens when the share is over.
    @ObservationIgnored private var completionWindowDeferred = false
    /// Tests replace the live signal (`ScreenCapture.isActive`).
    @ObservationIgnored var shareSignalsProvider: (() -> SharePrivacy.Signals)?

    func setPrivateManually(_ on: Bool) {
        isPrivateManual = on
        refreshPrivacy()
    }

    /// Opens the block-end window, or holds it until the share is over.
    func showCompletionWindow() {
        guard !isPrivate else {
            completionWindowDeferred = true
            return
        }
        openCompletionWindow?()
        requestAppActivation?()
    }

    /// Checks once a second (one cheap CoreGraphics call), so FocusFlow is gone within a second
    /// of a share starting.
    func startPrivacyMonitor() {
        guard privacyTimer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPrivacy() }
        }
        RunLoop.main.add(timer, forMode: .common)
        privacyTimer = timer
        refreshPrivacy()
    }

    func refreshPrivacy(now: Date = Date()) {
        var signals = shareSignalsProvider?() ?? liveShareSignals()
        signals.manual = isPrivateManual
        if signals.screenShared { lastSharedAt = now }
        let on = SharePrivacy.isPrivate(signals, lastSharedAt: lastSharedAt, now: now)
        guard on != isPrivate else { return }
        isPrivate = on
        log("privacy: \(on ? "hidden" : "visible") (manual \(signals.manual), screen shared \(signals.screenShared))")
        applyPrivacy(on)
    }

    /// The automatic signal follows "Hide while sharing my screen"; "Private now" always works.
    private func liveShareSignals() -> SharePrivacy.Signals {
        guard settings?.coachSuppressPopupsDuringScreenShare == true else { return .init() }
        return .init(screenShared: ScreenCapture.isActive)
    }

    private func applyPrivacy(_ on: Bool) {
        NotificationService.shared.isPrivate = on
        notchHost?.setEnabled(on ? false : isNotchCompanionEnabled)
        if on {
            if coachPanel != nil { hideCoachPanel() }
            if pauseScreen != nil {
                pauseScreen = nil
                pauseScreenHost?.hidePauseScreen()
            }
            closePopover()
            // An open block-end window names the project: put it away and bring it back after.
            for window in NSApp?.windows ?? [] where window.isVisible
                && window.identifier?.rawValue.contains("session-complete") == true {
                window.orderOut(nil)
                completionWindowDeferred = true
            }
        }
        // Best effort for windows you open yourself; some capture paths ignore it (see SharePrivacy).
        for window in NSApp?.windows ?? [] {
            window.sharingType = on ? .none : .readOnly
        }
        if !on, completionWindowDeferred {
            completionWindowDeferred = false
            if showSessionComplete || isOvertime { showCompletionWindow() }
        }
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
            dailyGoalSeconds: dailyGoal().seconds,
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
