import Foundation

/// Classifies session events to determine when to show reason-capture prompts.
/// Only triggers on true anomalies — not routine pauses or normal behavior.
struct FocusCoachAnomalyClassifier: Sendable {

    enum SessionEvent: Sendable {
        case pause(seconds: Int)
        case breakOverrun(seconds: Int)
        case midSessionStop(elapsedSeconds: Int, totalSeconds: Int)
        case repeatedDrift(consecutiveHighRiskWindows: Int)
        case fakeStart(idleAfterStartSeconds: Int)

        var displayName: String {
            switch self {
            case .pause: "Pause"
            case .breakOverrun: "Break Overrun"
            case .midSessionStop: "Mid-Session Stop"
            case .repeatedDrift: "Repeated Drift"
            case .fakeStart: "Fake Start"
            }
        }
    }

    /// Thresholds for triggering reason prompts
    private let minPauseSecondsForPrompt: Int = 120
    private let minBreakOverrunSecondsForPrompt: Int = 120
    private let minCompletionRatioForMidStop: Double = 0.15
    private let minConsecutiveHighRiskForDrift: Int = 3
    private let minFakeStartIdleSeconds: Int = 60

    /// Returns true if this event warrants asking the user why it happened.
    func shouldPromptReason(event: SessionEvent) -> Bool {
        switch event {
        case .pause(let seconds):
            return seconds >= minPauseSecondsForPrompt

        case .breakOverrun(let seconds):
            return seconds >= minBreakOverrunSecondsForPrompt

        case .midSessionStop(let elapsed, let total):
            // Only prompt if they completed at least 15% (not immediate abandon)
            // but less than 90% (natural completion doesn't need a reason)
            guard total > 0 else { return false }
            let ratio = Double(elapsed) / Double(total)
            return ratio >= minCompletionRatioForMidStop && ratio < 0.9

        case .repeatedDrift(let windows):
            return windows >= minConsecutiveHighRiskForDrift

        case .fakeStart(let idleSeconds):
            return idleSeconds >= minFakeStartIdleSeconds
        }
    }

    /// Maps a session event to the appropriate interruption kind for recording.
    func interruptionKind(for event: SessionEvent) -> FocusCoachInterruptionKind {
        switch event {
        case .pause: .drift
        case .breakOverrun: .breakOverrun
        case .midSessionStop: .midSessionStop
        case .repeatedDrift: .drift
        case .fakeStart: .fakeStart
        }
    }
}
