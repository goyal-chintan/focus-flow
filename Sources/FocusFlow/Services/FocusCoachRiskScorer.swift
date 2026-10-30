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

    static let zero = FocusCoachSignals(
        startDelaySeconds: 0,
        appSwitchesPerMinute: 0,
        nonWorkForegroundRatio: 0,
        inactivityBurstSeconds: 0,
        blockedAppAttempts: 0,
        pauseCount: 0
    )

    /// High-risk sample for testing
    static let sampleHighRisk = FocusCoachSignals(
        startDelaySeconds: 480,
        appSwitchesPerMinute: 14,
        nonWorkForegroundRatio: 0.75,
        inactivityBurstSeconds: 120,
        blockedAppAttempts: 2,
        pauseCount: 2
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
/// - Self-control deficit signals: pause creep, inactivity bursts
///
/// Break overrun and the "legitimate reason" dampening were inputs fed by the break-overrun and
/// reason chips, removed 2026-10-30 (nothing else set them). The weights sum to 0.85 so live
/// scores and the drift / high-risk thresholds are unchanged.
struct FocusCoachRiskScorer: Sendable {

    // MARK: - Weights (sum = 0.85; see the type comment)

    private let wStartDelay: Double = 0.15
    private let wAppSwitch: Double = 0.20
    private let wNonWorkRatio: Double = 0.20
    private let wInactivity: Double = 0.10
    private let wBlockedAttempts: Double = 0.10
    private let wPauseCreep: Double = 0.10

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

    func score(_ signals: FocusCoachSignals, profile: CoachPersonalProfile? = nil) -> FocusCoachRiskResult {
        let startDelayNorm = normalize(signals.startDelaySeconds, max: maxStartDelay)
        let appSwitchNorm = normalize(signals.appSwitchesPerMinute, max: maxAppSwitches)
        let nonWorkNorm = clamp(signals.nonWorkForegroundRatio)
        let inactivityNorm = normalize(signals.inactivityBurstSeconds, max: maxInactivity)
        let blockedNorm = normalize(Double(signals.blockedAppAttempts), max: maxBlockedAttempts)
        let pauseNorm = normalize(Double(signals.pauseCount), max: maxPauses)

        let raw = wStartDelay * startDelayNorm
            + wAppSwitch * appSwitchNorm
            + wNonWorkRatio * nonWorkNorm
            + wInactivity * inactivityNorm
            + wBlockedAttempts * blockedNorm
            + wPauseCreep * pauseNorm

        let finalScore = clamp(raw)

        // Confidence increases with more active signals (non-zero components)
        let activeSignals = [
            startDelayNorm, appSwitchNorm, nonWorkNorm,
            inactivityNorm, blockedNorm, pauseNorm
        ].filter { $0 > 0.01 }.count
        let confidence = clamp(Double(activeSignals) / 4.0)

        // Use personal thresholds if calibrated, otherwise defaults
        let driftThreshold = profile?.effectiveDriftThreshold ?? 0.35
        let highRiskThreshold = profile?.effectiveHighRiskThreshold ?? 0.65

        let level: FocusCoachRiskLevel
        switch finalScore {
        case 0..<driftThreshold:
            level = .stable
        case driftThreshold..<highRiskThreshold:
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
