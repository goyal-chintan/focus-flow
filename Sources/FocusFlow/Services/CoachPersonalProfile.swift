import Foundation

/// Personal calibration profile for adaptive coach thresholds.
/// Computed from a rolling window of intervention outcomes.
struct CoachPersonalProfile: Sendable {
    /// Personal drift-risk threshold (replaces hardcoded 0.35).
    /// Clamped to [0.25, 0.50].
    let driftThreshold: Double

    /// Personal high-risk threshold (replaces hardcoded 0.65).
    /// Clamped to [0.45, 0.80].
    let highRiskThreshold: Double

    /// Adaptive prompt budget based on win rate.
    /// Range: [2, 6]. Higher win rate → fewer prompts needed.
    let adaptivePromptBudget: Int

    /// Resistance multiplier derived from current task's expected resistance.
    /// 1.0 = neutral, <1.0 = easier task (higher thresholds), >1.0 = harder task (lower thresholds).
    let resistanceMultiplier: Double

    /// Whether the profile has enough data to be meaningful.
    let isCalibrated: Bool

    /// Effective thresholds after applying resistance multiplier.
    var effectiveDriftThreshold: Double {
        clamp(driftThreshold / resistanceMultiplier, min: 0.20, max: 0.55)
    }

    var effectiveHighRiskThreshold: Double {
        clamp(highRiskThreshold / resistanceMultiplier, min: 0.40, max: 0.85)
    }

    static let uncalibrated = CoachPersonalProfile(
        driftThreshold: 0.35,
        highRiskThreshold: 0.65,
        adaptivePromptBudget: 4,
        resistanceMultiplier: 1.0,
        isCalibrated: false
    )

    /// Calibrates a personal profile from historical intervention data.
    /// - Parameters:
    ///   - attempts: Recent intervention attempts (ideally 14-day rolling window)
    ///   - currentResistance: Expected resistance of the current task (1-5 scale)
    static func calibrate(
        from attempts: [InterventionAttempt],
        currentResistance: Int = 3
    ) -> CoachPersonalProfile {
        guard attempts.count >= 5 else {
            return CoachPersonalProfile(
                driftThreshold: 0.35,
                highRiskThreshold: 0.65,
                adaptivePromptBudget: 4,
                resistanceMultiplier: resistanceMultiplier(for: currentResistance),
                isCalibrated: false
            )
        }

        // Compute recovery scores: risk scores at which the user actually recovered
        let recoveredAttempts = attempts.filter { $0.outcome == .improved }
        let recoveryScores = recoveredAttempts.compactMap { $0.riskScore }

        // Personal drift threshold: median of risk scores where user recovered × 0.85
        let personalDrift: Double
        if recoveryScores.count >= 3 {
            let sorted = recoveryScores.sorted()
            let median = sorted[sorted.count / 2]
            personalDrift = clamp(median * 0.85, min: 0.25, max: 0.50)
        } else {
            personalDrift = 0.35
        }

        // High-risk threshold: personal drift + 0.25 spread
        let personalHighRisk = clamp(personalDrift + 0.25, min: 0.45, max: 0.80)

        // Win rate: fraction of non-snoozed interventions that led to improvement
        let actionableAttempts = attempts.filter { $0.outcome != nil && $0.outcome != .snoozed }
        let winRate: Double
        if actionableAttempts.count >= 3 {
            let wins = actionableAttempts.filter { $0.outcome == .improved }.count
            winRate = Double(wins) / Double(actionableAttempts.count)
        } else {
            winRate = 0.5
        }

        // Adaptive budget: high win rate (>70%) → fewer prompts needed (2-3)
        // Low win rate (<30%) → more prompts to catch drift (5-6)
        let budget: Int
        switch winRate {
        case 0.7...: budget = 2
        case 0.5..<0.7: budget = 3
        case 0.3..<0.5: budget = 4
        default: budget = 5
        }

        return CoachPersonalProfile(
            driftThreshold: personalDrift,
            highRiskThreshold: personalHighRisk,
            adaptivePromptBudget: budget,
            resistanceMultiplier: resistanceMultiplier(for: currentResistance),
            isCalibrated: true
        )
    }

    // MARK: - Helpers

    /// Maps 1-5 resistance scale to a multiplier (±20% range).
    /// Resistance 1 (easy) → 0.80 (thresholds effectively raised)
    /// Resistance 3 (neutral) → 1.00
    /// Resistance 5 (hard) → 1.20 (thresholds effectively lowered)
    private static func resistanceMultiplier(for resistance: Int) -> Double {
        let clamped = max(1, min(5, resistance))
        return 0.80 + Double(clamped - 1) * 0.10
    }

    private static func clamp(_ value: Double, min: Double, max: Double) -> Double {
        Swift.min(Swift.max(value, min), max)
    }

    private func clamp(_ value: Double, min: Double, max: Double) -> Double {
        Swift.min(Swift.max(value, min), max)
    }
}
