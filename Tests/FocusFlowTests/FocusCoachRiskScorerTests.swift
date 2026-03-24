import XCTest
@testable import FocusFlow

final class FocusCoachRiskScorerTests: XCTestCase {

    let scorer = FocusCoachRiskScorer()

    // MARK: - High Risk

    func testHighDelayAndSwitchingYieldHighRisk() {
        let signals = FocusCoachSignals(
            startDelaySeconds: 480,
            appSwitchesPerMinute: 14,
            nonWorkForegroundRatio: 0.85,
            inactivityBurstSeconds: 150,
            blockedAppAttempts: 3,
            pauseCount: 3,
            breakOverrunSeconds: 120,
            recentLegitimateReason: false
        )
        let result = scorer.score(signals)
        XCTAssertEqual(result.level, .highRisk)
        XCTAssertGreaterThan(result.score, 0.65)
    }

    // MARK: - Stable

    func testZeroSignalsYieldStable() {
        let result = scorer.score(.zero)
        XCTAssertEqual(result.level, .stable)
        XCTAssertEqual(result.score, 0)
    }

    func testLowSignalsYieldStable() {
        let signals = FocusCoachSignals(
            startDelaySeconds: 30,
            appSwitchesPerMinute: 2,
            nonWorkForegroundRatio: 0.1,
            inactivityBurstSeconds: 10,
            blockedAppAttempts: 0,
            pauseCount: 0,
            breakOverrunSeconds: 0,
            recentLegitimateReason: false
        )
        let result = scorer.score(signals)
        XCTAssertEqual(result.level, .stable)
        XCTAssertLessThan(result.score, 0.35)
    }

    // MARK: - Drift Risk (medium)

    func testModerateSignalsYieldDriftRisk() {
        let signals = FocusCoachSignals(
            startDelaySeconds: 240,
            appSwitchesPerMinute: 8,
            nonWorkForegroundRatio: 0.45,
            inactivityBurstSeconds: 60,
            blockedAppAttempts: 1,
            pauseCount: 2,
            breakOverrunSeconds: 80,
            recentLegitimateReason: false
        )
        let result = scorer.score(signals)
        XCTAssertEqual(result.level, .driftRisk)
        XCTAssertGreaterThanOrEqual(result.score, 0.35)
        XCTAssertLessThan(result.score, 0.65)
    }

    // MARK: - False Positive Dampening

    func testLegitimateReasonReducesFalsePositiveRisk() {
        var signals = FocusCoachSignals.sampleHighRisk
        signals.recentLegitimateReason = true
        let result = scorer.score(signals)
        XCTAssertLessThan(result.score, 0.65, "Legitimate reason should dampen score below highRisk threshold")
    }

    func testLegitimateReasonDampensByExpectedFactor() {
        let undampenedResult = scorer.score(.sampleHighRisk)
        var dampened = FocusCoachSignals.sampleHighRisk
        dampened.recentLegitimateReason = true
        let dampenedResult = scorer.score(dampened)

        // Score should be ~60% of undampened
        let ratio = dampenedResult.score / undampenedResult.score
        XCTAssertEqual(ratio, 0.6, accuracy: 0.01)
    }

    // MARK: - Score Bounds

    func testScoreIsAlwaysClamped0To1() {
        // All maxed out signals
        let extreme = FocusCoachSignals(
            startDelaySeconds: 9999,
            appSwitchesPerMinute: 999,
            nonWorkForegroundRatio: 1.0,
            inactivityBurstSeconds: 9999,
            blockedAppAttempts: 99,
            pauseCount: 99,
            breakOverrunSeconds: 9999,
            recentLegitimateReason: false
        )
        let result = scorer.score(extreme)
        XCTAssertLessThanOrEqual(result.score, 1.0)
        XCTAssertGreaterThanOrEqual(result.score, 0.0)
    }

    // MARK: - Confidence

    func testConfidenceIncreasesWithMoreActiveSignals() {
        let fewSignals = FocusCoachSignals(
            startDelaySeconds: 100,
            appSwitchesPerMinute: 0,
            nonWorkForegroundRatio: 0,
            inactivityBurstSeconds: 0,
            blockedAppAttempts: 0,
            pauseCount: 0,
            breakOverrunSeconds: 0,
            recentLegitimateReason: false
        )
        let manySignals = FocusCoachSignals.sampleHighRisk
        let fewResult = scorer.score(fewSignals)
        let manyResult = scorer.score(manySignals)
        XCTAssertGreaterThan(manyResult.confidence, fewResult.confidence)
    }

    // MARK: - Break Overrun Weight

    func testBreakOverrunContributesToRisk() {
        var signals = FocusCoachSignals.zero
        signals.breakOverrunSeconds = 300
        let result = scorer.score(signals)
        XCTAssertGreaterThan(result.score, 0, "Break overrun alone should increase risk")
    }
}
