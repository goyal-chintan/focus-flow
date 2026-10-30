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
            pauseCount: 3
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
            pauseCount: 0
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
            pauseCount: 2
        )
        let result = scorer.score(signals)
        XCTAssertEqual(result.level, .driftRisk)
        XCTAssertGreaterThanOrEqual(result.score, 0.35)
        XCTAssertLessThan(result.score, 0.65)
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
            pauseCount: 99
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
            pauseCount: 0
        )
        let manySignals = FocusCoachSignals.sampleHighRisk
        let fewResult = scorer.score(fewSignals)
        let manyResult = scorer.score(manySignals)
        XCTAssertGreaterThan(manyResult.confidence, fewResult.confidence)
    }
}
