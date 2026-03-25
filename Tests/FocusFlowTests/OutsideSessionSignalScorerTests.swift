import XCTest
@testable import FocusFlow

final class OutsideSessionSignalScorerTests: XCTestCase {
    private let scorer = OutsideSessionSignalScorer()

    func testWorkIntentScoreHighWithMultiplePositiveSignals() {
        let result = scorer.scoreWorkIntent(
            .init(
                openedAppRecently: true,
                selectedProjectRecently: true,
                recentlyAbandonedStart: false,
                withinTypicalWorkHours: true,
                isWeekday: true,
                preMeetingRunwayMinutes: 25,
                matchesHistoricalMissedStart: false,
                productiveContinuity: true
            )
        )

        XCTAssertGreaterThan(result.score, 0.65)
        XCTAssertGreaterThanOrEqual(result.availableSignalCount, 7)
        XCTAssertTrue(result.activeSignals.contains("opened_app_recently"))
    }

    func testDriftScoreHighForDistractingContextAndSwitchBurst() {
        let result = scorer.scoreDrift(
            .init(
                frontmostCategory: .distracting,
                appSwitchesPerMinute: 13,
                contextMismatch: true,
                overPlanningLoopDetected: true,
                breakOverrunRisk: true,
                startFrictionRepeats: 3,
                fatigueRisk: true
            )
        )

        XCTAssertGreaterThan(result.score, 0.65)
        XCTAssertEqual(result.level, .high)
    }

    func testMissingSignalsRenormalizeInsteadOfZeroingScore() {
        let result = scorer.scoreWorkIntent(
            .init(
                openedAppRecently: true,
                selectedProjectRecently: false,
                recentlyAbandonedStart: false,
                withinTypicalWorkHours: false,
                isWeekday: true,
                preMeetingRunwayMinutes: nil,
                matchesHistoricalMissedStart: false,
                productiveContinuity: nil
            )
        )

        XCTAssertGreaterThan(result.score, 0.3)
        XCTAssertEqual(result.availableSignalCount, 6)
    }
}
