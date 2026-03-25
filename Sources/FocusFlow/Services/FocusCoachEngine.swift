import Foundation

/// Protocol for persisting coach data. Enables in-memory testing without SwiftData.
protocol FocusCoachPersisting: AnyObject {
    func saveInterruption(_ interruption: CoachInterruption)
    func saveInterventionAttempt(_ attempt: InterventionAttempt)
    var interruptions: [CoachInterruption] { get }
    var attempts: [InterventionAttempt] { get }
}

/// In-memory store for unit testing without SwiftData.
final class InMemoryCoachStore: FocusCoachPersisting {
    var interruptions: [CoachInterruption] = []
    var attempts: [InterventionAttempt] = []

    func saveInterruption(_ interruption: CoachInterruption) {
        interruptions.append(interruption)
    }

    func saveInterventionAttempt(_ attempt: InterventionAttempt) {
        attempts.append(attempt)
    }
}

/// Orchestrates the focus coach pipeline: signals → risk scoring → intervention decisions → outcome logging.
///
/// The engine is designed to be wired into TimerViewModel. On each tick (~30s), it:
/// 1. Scores current behavioral signals
/// 2. Decides whether to intervene (respecting budget, snooze, cooldown)
/// 3. Records the decision for personalization learning
///
/// The engine is `@MainActor` because it's driven by TimerViewModel (which is `@MainActor`).
@MainActor
final class FocusCoachEngine {
    private let scorer = FocusCoachRiskScorer()
    private let policy = FocusCoachInterventionPolicy()
    private(set) var store: FocusCoachPersisting

    // MARK: - State
    private(set) var currentSignals = FocusCoachSignals.zero
    private(set) var promptState = FocusCoachPromptState.initial
    private(set) var lastRiskResult = FocusCoachRiskResult.stable
    private(set) var lastDecision: FocusCoachDecision = .none
    private(set) var currentSessionId: UUID?
    private(set) var sessionStartedAt: Date?
    private(set) var isActive = false

    /// Drift classification memory store — records planned/avoidant chip confirmations.
    var driftMemoryStore: DriftMemoryStore?

    /// Blocking recommendation engine — generates project-scoped block/allow suggestions.
    let blockingRecommendationEngine = FocusCoachBlockingRecommendationEngine()

    /// Pending blocking recommendation to surface to the user (set after evidence threshold met).
    var pendingBlockingRecommendation: BlockingRecommendation?

    /// Latest suspicious-context observation from AppUsageTracker (updated each foreground change).
    var latestObservation: SuspiciousContextObservation?

    /// Called when an avoidant observation (procrastinating / lowPriorityWork) arrives during an
    /// active session and DriftMemory has no project-scoped allowance for it.
    /// Wire in TimerViewModel to trigger guardian-state escalation.
    var onAvoidantObservationWithoutAllowance: ((SuspiciousContextObservation) -> Void)?

    /// The TaskIntent ID for the current session (set from pre-session card)
    var currentTaskIntentId: UUID?

    /// Current task resistance (1-5) for adaptive threshold scaling
    var currentTaskResistance: Int = 3

    /// Personal profile calibrated from historical data
    private(set) var personalProfile: CoachPersonalProfile = .uncalibrated

    /// Published for UI observation
    var riskLevel: FocusCoachRiskLevel { lastRiskResult.level }
    var riskScore: Double { lastRiskResult.score }

    /// Prompt budget (adaptive or from settings)
    var promptBudget: Int = 4

    /// Whether the reason chip sheet should be shown (set by anomaly detection)
    var shouldShowReasonSheet = false
    var pendingAnomalyKind: FocusCoachInterruptionKind?
    /// Prevents repeated drift reason prompts while the same high-risk streak is still active.
    private var hasPromptedDriftReasonInCurrentStreak = false

    init(store: FocusCoachPersisting = InMemoryCoachStore()) {
        self.store = store
    }

    /// Replaces the persistence store (e.g., from InMemory to SwiftData).
    /// Call during app configuration before any sessions start.
    func configureStore(_ newStore: FocusCoachPersisting) {
        self.store = newStore
    }

    /// Wires the drift memory store. Call during app configuration.
    func configureDriftMemory(_ store: DriftMemoryStore) {
        self.driftMemoryStore = store
    }

    // MARK: - Outside-session pattern signals

    /// True when current latest observation matches deterministic repeated risk evidence for the
    /// current (project, workMode, normalizedContextKey) tuple.
    func hasRepeatedProjectPatternForLatestObservation() -> Bool {
        guard let observation = latestObservation else { return false }
        return hasRepeatedProjectPattern(for: observation)
    }

    /// True when latest observation has historical missed-start evidence for this project tuple.
    func hasHistoricalMissedStartPatternForLatestObservation() -> Bool {
        guard let observation = latestObservation else { return false }
        return blockingRecommendationEngine.hasMissedStartPattern(
            projectId: observation.selectedProjectId,
            workMode: observation.selectedWorkMode,
            contextKey: observation.normalizedContextKey
        )
    }

    /// Exposed for unit tests and deterministic planner wiring.
    func hasRepeatedProjectPattern(for observation: SuspiciousContextObservation) -> Bool {
        let key = observation.normalizedContextKey
        let projectId = observation.selectedProjectId
        let workMode = observation.selectedWorkMode
        let repeatedFromMemory = driftMemoryStore?.projectScopedRisk(
            projectId: projectId,
            workMode: workMode,
            appOrDomain: key
        ) ?? false
        let repeatedFromRisk = blockingRecommendationEngine.hasRepeatedPatternEvidence(
            projectId: projectId,
            workMode: workMode,
            contextKey: key
        )
        return repeatedFromMemory || repeatedFromRisk
    }

    /// Records an explicit outside-session classification (e.g. skip reason chips / "This is planned")
    /// into project-scoped learning memory and risk evidence for the latest observed context.
    func recordOutsideSessionClassification(_ disposition: ContextDisposition) {
        guard !isActive else { return } // outside-session only
        guard let observation = latestObservation else { return }
        recordClassification(disposition, for: observation)
    }

    /// Convenience mapping for skip reason chips selected during outside-session prompts.
    func recordOutsideSessionClassification(skipReason: FocusCoachSkipReason) {
        guard let mapped = mapOutsideSessionDisposition(from: skipReason) else { return }
        recordOutsideSessionClassification(mapped)
    }

    /// Records an outside-session missed-start signal for the latest observed context.
    func recordOutsideSessionMissedStart() {
        guard !isActive, let observation = latestObservation,
              let projectId = observation.selectedProjectId,
              let workMode = observation.selectedWorkMode else { return }
        blockingRecommendationEngine.recordMissedStart(
            projectId: projectId,
            workMode: workMode,
            contextKey: observation.normalizedContextKey,
            displayName: observation.normalizedContextDisplayName
        )
    }

    // MARK: - Observation Routing

    /// Processes a new suspicious context observation from AppUsageTracker.
    /// Stores it in `latestObservation` and, during active sessions, routes avoidant
    /// dispositions to guardian escalation unless DriftMemory grants a project-scoped allowance.
    func handleNewObservation(_ observation: SuspiciousContextObservation) {
        latestObservation = observation

        guard isActive,
              let disposition = observation.suggestedDisposition,
              disposition.isAvoidant else { return }

        let contextKey = observation.normalizedContextKey
        let projectId   = observation.selectedProjectId
        let workMode    = observation.selectedWorkMode

        // Skip challenge if user has previously confirmed this context as planned work
        if let store = driftMemoryStore,
           store.projectScopedAllowance(projectId: projectId, workMode: workMode, appOrDomain: contextKey) {
            return
        }

        // Route to guardian advisor for potential escalation
        onAvoidantObservationWithoutAllowance?(observation)
    }

    // MARK: - Session Lifecycle

    func startSession(id: UUID) {
        currentSessionId = id
        sessionStartedAt = Date()
        isActive = true
        currentSignals = .zero
        promptState = .initial
        lastRiskResult = .stable
        lastDecision = .none
        shouldShowReasonSheet = false
        pendingAnomalyKind = nil
        hasPromptedDriftReasonInCurrentStreak = false

        // Calibrate personal profile from 14-day rolling window
        calibrateProfile()
        driftMemoryStore?.beginSession()
    }

    func endSession() {
        isActive = false
        currentSessionId = nil
        sessionStartedAt = nil
        currentTaskIntentId = nil
        shouldShowReasonSheet = false
        pendingAnomalyKind = nil
        hasPromptedDriftReasonInCurrentStreak = false
    }

    // MARK: - Signal Ingestion

    /// Records a new behavioral sample from AppUsageTracker.
    func recordBehaviorSample(_ signals: FocusCoachSignals) {
        currentSignals = signals
    }

    /// Updates a single signal dimension (for incremental updates from different sources).
    func updateStartDelay(_ seconds: Double) {
        currentSignals.startDelaySeconds = seconds
    }

    func updatePauseCount(_ count: Int) {
        currentSignals.pauseCount = count
    }

    func updateBreakOverrun(_ seconds: Double) {
        currentSignals.breakOverrunSeconds = seconds
    }

    // MARK: - Tick (called ~every 30s during active session)

    /// Runs the scoring → policy pipeline and returns a decision if intervention is needed.
    func tick(now: Date = Date()) -> FocusCoachDecision? {
        guard isActive else { return nil }

        // Score current signals using personal profile
        lastRiskResult = scorer.score(currentSignals, profile: personalProfile)

        // Update consecutive high-risk window tracking
        if lastRiskResult.level == .highRisk {
            promptState.consecutiveHighRiskWindows += 1
        } else {
            promptState.consecutiveHighRiskWindows = 0
            hasPromptedDriftReasonInCurrentStreak = false
        }

        // Use adaptive prompt budget from personal profile if calibrated
        let effectiveBudget = personalProfile.isCalibrated
            ? personalProfile.adaptivePromptBudget
            : promptBudget

        // Get intervention decision
        let decision = policy.decide(
            now: now,
            risk: lastRiskResult.level,
            state: promptState,
            promptBudget: effectiveBudget
        )

        lastDecision = decision

        // Trigger reason chip sheet for repeated drift (≥3 consecutive high-risk windows)
        let classifier = FocusCoachAnomalyClassifier()
        if classifier.shouldPromptReason(event: .repeatedDrift(consecutiveHighRiskWindows: promptState.consecutiveHighRiskWindows)),
           !hasPromptedDriftReasonInCurrentStreak {
            shouldShowReasonSheet = true
            pendingAnomalyKind = .drift
            hasPromptedDriftReasonInCurrentStreak = true
        }

        return decision.kind == .none ? nil : decision
    }

    /// Records a concrete intervention actually delivered to the user.
    /// This is called by presentation-routing code so analytics reflect the shown surface.
    func recordDeliveredIntervention(
        kind: FocusCoachInterventionKind,
        riskScore: Double? = nil,
        sessionId: UUID? = nil,
        now: Date = Date()
    ) {
        let attempt = InterventionAttempt(
            kind: kind,
            riskScore: riskScore ?? lastRiskResult.score,
            sessionId: sessionId ?? currentSessionId
        )
        store.saveInterventionAttempt(attempt)
        promptState.promptCountThisSession += 1
        promptState.lastPromptAt = now
    }

    // MARK: - Anomaly Reason Recording

    /// Records why an anomaly happened (user-selected reason chip).
    func recordAnomaly(kind: FocusCoachInterruptionKind, reason: FocusCoachReason?, sessionId: UUID?) {
        let interruption = CoachInterruption(
            sessionId: sessionId ?? currentSessionId ?? UUID(),
            kind: kind,
            reason: reason,
            riskScoreAtDetection: lastRiskResult.score
        )
        store.saveInterruption(interruption)

        // Update signals: legitimate reason dampens future scoring
        if let reason, reason.isLegitimate {
            currentSignals.recentLegitimateReason = true
        }

        if let reason,
           let observation = latestObservation {
            recordClassification(mapDisposition(from: reason), for: observation)
        }
    }

    // MARK: - Intervention Outcome

    /// Records user response to an intervention prompt.
    func recordInterventionOutcome(_ outcome: FocusCoachOutcome, skipReason: FocusCoachSkipReason? = nil) {
        if let lastAttempt = store.attempts.last {
            lastAttempt.outcome = outcome
            lastAttempt.resolvedAt = Date()
            if let reason = skipReason {
                lastAttempt.skipReasonRaw = reason.rawValue
            }

            if outcome == .snoozed {
                // Extend snooze duration for legitimate skip reasons — don't re-interrupt mid-meeting
                let snoozeMinutes: TimeInterval = skipReason?.isLegitimate == true ? 20 : 10
                promptState.snoozedUntil = Date().addingTimeInterval(snoozeMinutes * 60)
            }
        }

        if outcome == .snoozed, let skipReason {
            recordOutsideSessionClassification(skipReason: skipReason)
        }
    }

    // MARK: - Snooze

    func snooze(minutes: Int, skipReason: FocusCoachSkipReason? = nil) {
        let effectiveMinutes = skipReason?.isLegitimate == true ? max(minutes, 20) : minutes
        promptState.snoozedUntil = Date().addingTimeInterval(TimeInterval(effectiveMinutes * 60))
        recordInterventionOutcome(.snoozed, skipReason: skipReason)
    }

    // MARK: - Pattern Analysis

    /// Returns how many times the user selected "lowPriorityWork" as a skip reason
    /// in the last `lookbackDays` days. Uses the in-memory store (backed by SwiftData in production).
    func recentLowPrioritySkipCount(lookbackDays: Int = 7) -> Int {
        let cutoff = Calendar.current.date(
            byAdding: .day, value: -lookbackDays, to: Date()
        ) ?? Date()
        return store.attempts.filter { attempt in
            attempt.skipReasonRaw == FocusCoachSkipReason.lowPriorityWork.rawValue
                && attempt.deliveredAt > cutoff
        }.count
    }

    // MARK: - Coach Signals Computation

    /// Computes app-switch rate from a window of recent app changes.
    static func computeAppSwitchRate(switchTimestamps: [Date], windowSeconds: TimeInterval = 60) -> Double {
        guard switchTimestamps.count > 1 else { return 0 }
        let now = Date()
        let windowStart = now.addingTimeInterval(-windowSeconds)
        let recentSwitches = switchTimestamps.filter { $0 >= windowStart }
        let windowMinutes = windowSeconds / 60.0
        return Double(recentSwitches.count) / windowMinutes
    }

    // MARK: - Adaptive Calibration

    /// Calibrates the personal profile from a 14-day rolling window of intervention outcomes.
    func calibrateProfile() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date()
        let recentAttempts = store.attempts.filter { $0.deliveredAt > cutoff }
        personalProfile = CoachPersonalProfile.calibrate(
            from: recentAttempts,
            currentResistance: currentTaskResistance
        )
    }

    // MARK: - Learning helpers

    private func recordClassification(_ disposition: ContextDisposition, for observation: SuspiciousContextObservation) {
        let contextKey = observation.normalizedContextKey
        let projectId = observation.selectedProjectId
        let workMode = observation.selectedWorkMode
        let projectName = observation.selectedProjectName
        let displayName = observation.normalizedContextDisplayName

        if let store = driftMemoryStore {
            if disposition.isAvoidant {
                store.recordAvoidant(projectId: projectId, workMode: workMode, appOrDomain: contextKey)
            } else if disposition.isLegitimate {
                store.recordPlanned(projectId: projectId, workMode: workMode, appOrDomain: contextKey)
            }
        }

        guard let projectId, let workMode else { return }

        if disposition.isAvoidant {
            blockingRecommendationEngine.recordAvoidant(
                projectId: projectId,
                workMode: workMode,
                contextKey: contextKey,
                displayName: displayName
            )

            if let rec = blockingRecommendationEngine.blockRecommendation(
                for: contextKey,
                projectId: projectId,
                workMode: workMode,
                projectName: projectName
            ) {
                pendingBlockingRecommendation = rec
                blockingRecommendationEngine.markRecommendationSurfaced(
                    projectId: projectId,
                    workMode: workMode,
                    contextKey: contextKey
                )
            }
        } else if disposition.isLegitimate {
            blockingRecommendationEngine.recordPlanned(
                projectId: projectId,
                workMode: workMode,
                contextKey: contextKey,
                displayName: displayName
            )
        }
    }

    private func mapDisposition(from reason: FocusCoachReason) -> ContextDisposition {
        switch reason {
        case .meeting, .familyPersonal:
            return .legitimateInterruption
        case .plannedResearch:
            return .plannedResearch
        case .requiredSwitch:
            return .requiredContextSwitch
        case .realBreak:
            return .realBreak
        case .fatigue:
            return .fatigued
        case .lowPriorityWork:
            return .lowPriorityWork
        case .procrastinating, .vibeCodingDrift, .overPlanning, .scrollingBrowsing, .avoidingHardPart:
            return .procrastinating
        }
    }

    private func mapOutsideSessionDisposition(from reason: FocusCoachSkipReason) -> ContextDisposition? {
        switch reason {
        case .lowPriorityWork:
            return .lowPriorityWork
        case .procrastinating, .cantFocus:
            return .procrastinating
        case .urgentTask, .inMeeting, .takingBreak, .notWell, .justTired, .doneForToday:
            return nil
        }
    }
}
