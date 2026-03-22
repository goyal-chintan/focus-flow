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
    private let store: FocusCoachPersisting

    // MARK: - State
    private(set) var currentSignals = FocusCoachSignals.zero
    private(set) var promptState = FocusCoachPromptState.initial
    private(set) var lastRiskResult = FocusCoachRiskResult.stable
    private(set) var lastDecision: FocusCoachDecision = .none
    private(set) var currentSessionId: UUID?
    private(set) var sessionStartedAt: Date?
    private(set) var isActive = false

    /// Published for UI observation
    var riskLevel: FocusCoachRiskLevel { lastRiskResult.level }
    var riskScore: Double { lastRiskResult.score }

    /// Prompt budget (configurable via settings)
    var promptBudget: Int = 4

    init(store: FocusCoachPersisting = InMemoryCoachStore()) {
        self.store = store
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
    }

    func endSession() {
        isActive = false
        currentSessionId = nil
        sessionStartedAt = nil
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

        // Record intervention attempt if it's a prompt (not none or soft strip)
        if decision.kind == .quickPrompt || decision.kind == .strongPrompt {
            let attempt = InterventionAttempt(
                kind: decision.kind == .strongPrompt ? .strongPrompt : .quickPrompt,
                riskScore: lastRiskResult.score,
                sessionId: currentSessionId
            )
            store.saveInterventionAttempt(attempt)
            promptState.promptCountThisSession += 1
            promptState.lastPromptAt = now
        }

        return decision.kind == .none ? nil : decision
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
    func recordInterventionOutcome(_ outcome: FocusCoachOutcome) {
        if let lastAttempt = store.attempts.last {
            lastAttempt.outcome = outcome
            lastAttempt.resolvedAt = Date()

            if outcome == .snoozed {
                // Default 10-minute snooze
                promptState.snoozedUntil = Date().addingTimeInterval(600)
            }
        }
    }

    // MARK: - Snooze

    func snooze(minutes: Int) {
        promptState.snoozedUntil = Date().addingTimeInterval(TimeInterval(minutes * 60))
        recordInterventionOutcome(.snoozed)
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
