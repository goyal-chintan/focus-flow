import Foundation

/// Real-time behavioral signals collected every ~30 seconds during a focus session.
/// Fed into the risk scorer to produce a drift/procrastination risk assessment.
struct FocusCoachSignals: Sendable {
    var startDelaySeconds: Double
    var appSwitchesPerMinute: Double
    var nonWorkForegroundRatio: Double
    var inactivityBurstSeconds: Double
    var blockedAppAttempts: Int
    var pauseCount: Int
    var breakOverrunSeconds: Double
    var recentLegitimateReason: Bool

    static let zero = FocusCoachSignals(
        startDelaySeconds: 0,
        appSwitchesPerMinute: 0,
        nonWorkForegroundRatio: 0,
        inactivityBurstSeconds: 0,
        blockedAppAttempts: 0,
        pauseCount: 0,
        breakOverrunSeconds: 0,
        recentLegitimateReason: false
    )

    /// High-risk sample for testing
    static let sampleHighRisk = FocusCoachSignals(
        startDelaySeconds: 480,
        appSwitchesPerMinute: 14,
        nonWorkForegroundRatio: 0.75,
        inactivityBurstSeconds: 120,
        blockedAppAttempts: 2,
        pauseCount: 2,
        breakOverrunSeconds: 0,
        recentLegitimateReason: false
    )
}

/// The output of the risk scorer: a 0–1 score, a confidence level, and a discrete risk level.
struct FocusCoachRiskResult: Sendable {
    let score: Double
    let confidence: Double
    let level: FocusCoachRiskLevel

    static let stable = FocusCoachRiskResult(score: 0, confidence: 1.0, level: .stable)
}

/// Pure scoring service. No side effects — takes signals, returns a risk result.
///
/// Weighted formula based on procrastination research (Steel 2007):
/// - Task aversiveness signals: start delay, non-work ratio
/// - Impulsiveness signals: app switch rate, blocked app attempts
/// - Self-control deficit signals: pause creep, inactivity bursts, break overrun
///
/// False-positive dampening: when user has provided a legitimate reason,
/// the raw score is reduced by 40% to avoid punishing genuine interruptions.
struct FocusCoachRiskScorer: Sendable {

    // MARK: - Weights (sum = 1.0)

    private let wStartDelay: Double = 0.15
    private let wAppSwitch: Double = 0.20
    private let wNonWorkRatio: Double = 0.20
    private let wInactivity: Double = 0.10
    private let wBlockedAttempts: Double = 0.10
    private let wPauseCreep: Double = 0.10
    private let wBreakOverrun: Double = 0.15

    // MARK: - Normalization thresholds

    /// Seconds of start delay that maps to 1.0 (8 minutes)
    private let maxStartDelay: Double = 480
    /// App switches per minute that maps to 1.0
    private let maxAppSwitches: Double = 15
    /// Inactivity burst seconds that maps to 1.0 (3 minutes)
    private let maxInactivity: Double = 180
    /// Blocked app attempts that maps to 1.0
    private let maxBlockedAttempts: Double = 5
    /// Pause count that maps to 1.0
    private let maxPauses: Double = 5
    /// Break overrun seconds that maps to 1.0 (5 minutes)
    private let maxBreakOverrun: Double = 300

    /// False-positive dampening factor when a legitimate reason was recently given
    private let legitimateReasonDampeningFactor: Double = 0.6

    func score(_ signals: FocusCoachSignals) -> FocusCoachRiskResult {
        let startDelayNorm = normalize(signals.startDelaySeconds, max: maxStartDelay)
        let appSwitchNorm = normalize(signals.appSwitchesPerMinute, max: maxAppSwitches)
        let nonWorkNorm = clamp(signals.nonWorkForegroundRatio)
        let inactivityNorm = normalize(signals.inactivityBurstSeconds, max: maxInactivity)
        let blockedNorm = normalize(Double(signals.blockedAppAttempts), max: maxBlockedAttempts)
        let pauseNorm = normalize(Double(signals.pauseCount), max: maxPauses)
        let breakOverrunNorm = normalize(signals.breakOverrunSeconds, max: maxBreakOverrun)

        var raw = wStartDelay * startDelayNorm
            + wAppSwitch * appSwitchNorm
            + wNonWorkRatio * nonWorkNorm
            + wInactivity * inactivityNorm
            + wBlockedAttempts * blockedNorm
            + wPauseCreep * pauseNorm
            + wBreakOverrun * breakOverrunNorm

        // Apply false-positive dampening
        if signals.recentLegitimateReason {
            raw *= legitimateReasonDampeningFactor
        }

        let finalScore = clamp(raw)

        // Confidence increases with more active signals (non-zero components)
        let activeSignals = [
            startDelayNorm, appSwitchNorm, nonWorkNorm,
            inactivityNorm, blockedNorm, pauseNorm, breakOverrunNorm
        ].filter { $0 > 0.01 }.count
        let confidence = clamp(Double(activeSignals) / 4.0)

        let level: FocusCoachRiskLevel
        switch finalScore {
        case 0..<0.35:
            level = .stable
        case 0.35..<0.65:
            level = .driftRisk
        default:
            level = .highRisk
        }

        return FocusCoachRiskResult(score: finalScore, confidence: confidence, level: level)
    }

    // MARK: - Helpers

    private func normalize(_ value: Double, max: Double) -> Double {
        clamp(value / max)
    }

    private func clamp(_ value: Double) -> Double {
        Swift.min(Swift.max(value, 0), 1)
    }
}
