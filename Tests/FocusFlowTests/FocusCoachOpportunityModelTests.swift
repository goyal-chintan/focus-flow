import XCTest
@testable import FocusFlow

final class FocusCoachOpportunityModelTests: XCTestCase {

    private let model = FocusCoachOpportunityModel()

    func testRecommendedDurationUsesCalendarGapWhenSoonEvent() {
        let duration = model.recommendedDuration(
            defaultMinutes: 25,
            minutesUntilNextCalendarEvent: 18
        )
        XCTAssertEqual(duration, 10)
    }

    func testRecommendedDurationFallsBackToDefaultWhenNoEvent() {
        let duration = model.recommendedDuration(
            defaultMinutes: 30,
            minutesUntilNextCalendarEvent: nil
        )
        XCTAssertEqual(duration, 30)
    }

    func testIdleDriftConfidenceHigherForDistractingAppAndLongIdle() {
        let high = model.idleDriftConfidence(
            idleSeconds: 16 * 60,
            escalationLevel: 2,
            frontmostCategory: .distracting
        )
        let low = model.idleDriftConfidence(
            idleSeconds: 3 * 60,
            escalationLevel: 0,
            frontmostCategory: .productive
        )
        XCTAssertGreaterThan(high, low)
    }

    func testIdleDriftConfidenceForProductiveAppStillTriggersAtHighIdleEscalation() {
        let value = model.idleDriftConfidence(
            idleSeconds: 10 * 60,
            escalationLevel: 2,
            frontmostCategory: .productive
        )
        XCTAssertGreaterThanOrEqual(value, 0.55)
    }

    func testFocusOpportunityHigherWithModerateCalendarWindow() {
        let high = model.focusOpportunityScore(
            hourOfDay: 10,
            minutesUntilNextCalendarEvent: 40,
            isInActiveSession: false
        )
        let low = model.focusOpportunityScore(
            hourOfDay: 23,
            minutesUntilNextCalendarEvent: 5,
            isInActiveSession: false
        )
        XCTAssertGreaterThan(high, low)
    }

    func testIdleStarterContextBuildsRecommendedDurationAndCopy() {
        let context = model.idleStarterContext(
            idleSeconds: 12 * 60,
            escalationLevel: 2,
            frontmostCategory: .distracting,
            hourOfDay: 11,
            minutesUntilNextCalendarEvent: 28,
            defaultMinutes: 25
        )
        XCTAssertEqual(context.recommendedDurationMinutes, 20)
        XCTAssertGreaterThan(context.driftConfidence, 0.6)
        XCTAssertGreaterThan(context.focusOpportunity, 0.6)
        XCTAssertFalse(context.summary.isEmpty)
    }
}
