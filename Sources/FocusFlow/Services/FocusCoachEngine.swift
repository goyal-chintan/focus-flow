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

    /// The TaskIntent ID for the current session (set from pre-session card)
    var currentTaskIntentId: UUID?

    /// Published for UI observation
    var riskLevel: FocusCoachRiskLevel { lastRiskResult.level }
    var riskScore: Double { lastRiskResult.score }

    /// Prompt budget (configurable via settings)
    var promptBudget: Int = 4

    /// Whether the reason chip sheet should be shown (set by anomaly detection)
    var shouldShowReasonSheet = false
    var pendingAnomalyKind: FocusCoachInterruptionKind?

    init(store: FocusCoachPersisting = InMemoryCoachStore()) {
        self.store = store
    }

    /// Replaces the persistence store (e.g., from InMemory to SwiftData).
    /// Call during app configuration before any sessions start.
    func configureStore(_ newStore: FocusCoachPersisting) {
        self.store = newStore
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
    }

    func endSession() {
        isActive = false
        currentSessionId = nil
        sessionStartedAt = nil
        currentTaskIntentId = nil
        shouldShowReasonSheet = false
        pendingAnomalyKind = nil
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

        // Score current signals
        lastRiskResult = scorer.score(currentSignals)

        // Update consecutive high-risk window tracking
        if lastRiskResult.level == .highRisk {
            promptState.consecutiveHighRiskWindows += 1
        } else {
            promptState.consecutiveHighRiskWindows = 0
        }

        // Get intervention decision
        let decision = policy.decide(
            now: now,
            risk: lastRiskResult.level,
            state: promptState,
            promptBudget: promptBudget
        )

        lastDecision = decision

        // Trigger reason chip sheet for repeated drift (≥3 consecutive high-risk windows)
        let classifier = FocusCoachAnomalyClassifier()
        if classifier.shouldPromptReason(event: .repeatedDrift(consecutiveHighRiskWindows: promptState.consecutiveHighRiskWindows)) {
            shouldShowReasonSheet = true
            pendingAnomalyKind = .drift
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
}
