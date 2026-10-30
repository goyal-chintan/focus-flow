import Foundation

/// Protocol for persisting coach data. Enables in-memory testing without SwiftData.
protocol FocusCoachPersisting: AnyObject {
    func saveInterventionAttempt(_ attempt: InterventionAttempt)
    var attempts: [InterventionAttempt] { get }
    /// Attempts delivered at or after `date`. Stores with a query engine should override this.
    func attempts(deliveredSince date: Date) -> [InterventionAttempt]
    /// Persists in-place mutations (outcome, skip reason) of already-saved attempts.
    func saveChanges()
    /// The attempt with this id, if stored.
    func attempt(id: UUID) -> InterventionAttempt?
}

extension FocusCoachPersisting {
    func attempts(deliveredSince date: Date) -> [InterventionAttempt] {
        attempts.filter { $0.deliveredAt >= date }
    }

    func attempt(id: UUID) -> InterventionAttempt? {
        attempts.first { $0.id == id }
    }

    func saveChanges() {}
}

/// In-memory store for unit testing without SwiftData.
final class InMemoryCoachStore: FocusCoachPersisting {
    var attempts: [InterventionAttempt] = []

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

    /// Latest suspicious-context observation from AppUsageTracker (updated each foreground change).
    var latestObservation: SuspiciousContextObservation?

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

    /// The attempt most recently delivered by this engine. Outcomes resolve against it so they
    /// never depend on the store's sort order (bug B3: SwiftData returns newest-first).
    private(set) var lastDeliveredAttempt: InterventionAttempt?

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

    /// Keeps the latest suspicious context observation from AppUsageTracker, which
    /// `recordOutsideSessionClassification` files into drift memory. Escalation from here had no
    /// receiver and was removed with the reason chips (2026-10-30).
    func handleNewObservation(_ observation: SuspiciousContextObservation) {
        latestObservation = observation
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

        // Calibrate personal profile from 14-day rolling window
        calibrateProfile()
        driftMemoryStore?.beginSession()
    }

    func endSession() {
        isActive = false
        currentSessionId = nil
        sessionStartedAt = nil
        currentTaskIntentId = nil
    }

    // MARK: - Signal Ingestion

    /// Records a new behavioral sample from AppUsageTracker.
    func recordBehaviorSample(_ signals: FocusCoachSignals) {
        currentSignals = signals
    }

    func updatePauseCount(_ count: Int) {
        currentSignals.pauseCount = count
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

        return decision.kind == .none ? nil : decision
    }

    /// Records a concrete intervention actually delivered to the user and returns its row.
    /// `surface`, `style` and `contextKey` are the Coach v2.1 learning fields; a non-nil
    /// `contextKey` marks the attempt as a bandit decision that will receive a reward.
    @discardableResult
    func recordDeliveredIntervention(
        kind: FocusCoachInterventionKind,
        riskScore: Double? = nil,
        sessionId: UUID? = nil,
        now: Date = Date(),
        surface: CoachSurface? = nil,
        style: CoachStyle? = nil,
        contextKey: String? = nil
    ) -> InterventionAttempt {
        let attempt = InterventionAttempt(
            kind: kind,
            riskScore: riskScore ?? lastRiskResult.score,
            sessionId: sessionId ?? currentSessionId
        )
        attempt.deliveredAt = now
        attempt.surfaceRawValue = surface?.rawValue
        attempt.styleRawValue = style?.rawValue
        attempt.contextKey = contextKey
        store.saveInterventionAttempt(attempt)
        lastDeliveredAttempt = attempt
        promptState.promptCountThisSession += 1
        promptState.lastPromptAt = now
        return attempt
    }

    /// Coach v5: logs a decision point where the coach chose to stay quiet. Unlike a delivery it
    /// touches no prompt state (budget, cooldown, last delivered): nothing was shown.
    @discardableResult
    func recordDecisionPoint(at now: Date, riskScore: Double, features: String, propensity: Double?) -> InterventionAttempt {
        let attempt = InterventionAttempt(kind: .quickPrompt, riskScore: riskScore, sessionId: nil)
        attempt.deliveredAt = now
        attempt.surfaceRawValue = CoachSurface.silent.rawValue
        attempt.decisionRaw = CoachPromptPolicy.decisionKey
        attempt.featuresRaw = features
        attempt.propensity = propensity
        attempt.treated = false
        store.saveInterventionAttempt(attempt)
        return attempt
    }

    /// Prompts shown since `date` (any surface), for the non-learnable guardrails.
    func guardrailDeliveries(since date: Date) -> [CoachGuardrails.Delivery] {
        store.attempts(deliveredSince: date).map(CoachGuardrails.Delivery.init(attempt:))
    }

    // MARK: - Intervention Outcome

    /// Records user response to an intervention prompt.
    /// Snooze duration is owned by `snooze(minutes:)`; this only labels the attempt (bug B2).
    func recordInterventionOutcome(
        _ outcome: FocusCoachOutcome,
        skipReason: FocusCoachSkipReason? = nil,
        attemptID: UUID? = nil
    ) {
        // Resolve by id when the caller knows which prompt it answered. Otherwise use the attempt
        // this engine delivered; after a relaunch fall back to the newest persisted one. Never use
        // positional `.first`/`.last`: store sort order varies (bug B3).
        let target = attemptID.flatMap { store.attempt(id: $0) }
            ?? lastDeliveredAttempt
            ?? store.attempts.max { $0.deliveredAt < $1.deliveredAt }
        if let target, target.outcome == nil {
            target.outcome = outcome
            target.resolvedAt = Date()
            if let reason = skipReason {
                target.skipReasonRaw = reason.rawValue
            }
            store.saveChanges()
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
        } else if disposition.isLegitimate {
            blockingRecommendationEngine.recordPlanned(
                projectId: projectId,
                workMode: workMode,
                contextKey: contextKey,
                displayName: displayName
            )
        }
    }

    private func mapOutsideSessionDisposition(from reason: FocusCoachSkipReason) -> ContextDisposition? {
        switch reason {
        case .lowPriorityWork:
            return .lowPriorityWork
        case .procrastinating, .cantFocus:
            return .procrastinating
        case .urgentTask, .inMeeting, .takingBreak, .notWell, .justTired, .doneForToday, .taskTooBig, .unclearNextStep:
            return nil
        }
    }
}
