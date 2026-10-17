import XCTest
@testable import FocusFlow

final class CoachGoalPacingTests: XCTestCase {
    func testPressureTiers() {
        XCTAssertEqual(CoachGoalPacing(goalMinutes: 120, doneMinutes: 0, windowMinutesLeft: 300).tier, .onTrack)
        XCTAssertEqual(CoachGoalPacing(goalMinutes: 120, doneMinutes: 0, windowMinutesLeft: 180).tier, .nudge)
        XCTAssertEqual(CoachGoalPacing(goalMinutes: 120, doneMinutes: 0, windowMinutesLeft: 240).tier, .nudge, "0.5 is a nudge")
        XCTAssertEqual(CoachGoalPacing(goalMinutes: 120, doneMinutes: 0, windowMinutesLeft: 120).tier, .nudge, "1.0 is still a nudge")
        XCTAssertEqual(CoachGoalPacing(goalMinutes: 120, doneMinutes: 30, windowMinutesLeft: 60).tier, .atRisk)
        XCTAssertEqual(CoachGoalPacing(goalMinutes: 120, doneMinutes: 120, windowMinutesLeft: 60).tier, .goalMet)
        XCTAssertEqual(CoachGoalPacing(goalMinutes: 120, doneMinutes: 0, windowMinutesLeft: nil).tier, .unknown)
    }

    func testNoWindowLeftIsAtRisk() {
        let pacing = CoachGoalPacing(goalMinutes: 120, doneMinutes: 60, windowMinutesLeft: 0)
        XCTAssertEqual(pacing.tier, .atRisk)
        XCTAssertEqual(pacing.pressure, .infinity)
        XCTAssertTrue(pacing.isBehindPace)
    }

    func testRemainingAndPercent() {
        let pacing = CoachGoalPacing(goalMinutes: 120, doneMinutes: 101, windowMinutesLeft: 90)
        XCTAssertEqual(pacing.remainingMinutes, 19)
        XCTAssertEqual(pacing.percentOfGoal, 84)
        XCTAssertEqual(pacing.pressure ?? 0, 19.0 / 90.0, accuracy: 1e-9)
        XCTAssertFalse(pacing.isBehindPace)
    }

    func testSuggestedBlockLengthIsMaxOf25AndMinOfRemainingAnd50() {
        XCTAssertEqual(CoachGoalPacing(goalMinutes: 120, doneMinutes: 0, windowMinutesLeft: 100).suggestedBlockMinutes, 50)
        XCTAssertEqual(CoachGoalPacing(goalMinutes: 120, doneMinutes: 80, windowMinutesLeft: 100).suggestedBlockMinutes, 40)
        XCTAssertEqual(CoachGoalPacing(goalMinutes: 120, doneMinutes: 110, windowMinutesLeft: 100).suggestedBlockMinutes, 25)
        XCTAssertEqual(CoachGoalPacing(goalMinutes: 120, doneMinutes: 150, windowMinutesLeft: 100).suggestedBlockMinutes, 25)
    }
}
