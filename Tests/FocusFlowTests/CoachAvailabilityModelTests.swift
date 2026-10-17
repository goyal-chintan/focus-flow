import XCTest
@testable import FocusFlow

final class CoachAvailabilityModelTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// Wednesday 2026-10-14 (weekday 4).
    private func date(day: Int = 14, hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    /// Twelve weeks of weekday sessions at 11:00 and 22:00 (the user's real pattern).
    private func learnedModel() -> CoachAvailabilityModel {
        var sessions: [CoachAvailabilityModel.Session] = []
        var days: [Date] = []
        let end = date(day: 13, hour: 0)
        for offset in 0..<84 {
            let day = calendar.date(byAdding: .day, value: -offset, to: end)!
            days.append(day)
            let weekday = calendar.component(.weekday, from: day)
            guard (2...6).contains(weekday) else { continue }
            for hour in [11, 22] {
                let start = calendar.date(byAdding: .hour, value: hour, to: day)!
                sessions.append(.init(start: start, end: start.addingTimeInterval(45 * 60)))
            }
        }
        return CoachAvailabilityModel(sessions: sessions, activeDays: days, calendar: calendar)
    }

    func testNoHistoryOpensEveryHourWithoutInventingWindows() {
        let model = CoachAvailabilityModel(sessions: [], activeDays: [], calendar: calendar)
        XCTAssertEqual(model.mode, .noData)
        XCTAssertTrue(model.isGoodWindow(date(hour: 3)))
        XCTAssertTrue(model.isGoodWindow(date(hour: 15)))
        XCTAssertNil(model.nextGoodWindow(after: date(hour: 15)))
        XCTAssertNil(model.goodWindowMinutesRemainingToday(from: date(hour: 15)))
    }

    func testColdStartFallsBackToHistoricalStartHours() {
        let sessions = (1...3).map { offset -> CoachAvailabilityModel.Session in
            let start = calendar.date(byAdding: .day, value: -offset, to: date(hour: 22, minute: 10))!
            return .init(start: start, end: start.addingTimeInterval(1800))
        }
        let model = CoachAvailabilityModel(sessions: sessions, activeDays: [], calendar: calendar)

        XCTAssertEqual(model.mode, .coldStart(startHours: [22]))
        XCTAssertTrue(model.isGoodWindow(date(hour: 22, minute: 30)))
        XCTAssertTrue(model.isGoodWindow(date(hour: 21)), "±1 hour")
        XCTAssertTrue(model.isGoodWindow(date(hour: 23)))
        XCTAssertFalse(model.isGoodWindow(date(hour: 15)))
        XCTAssertEqual(model.nextGoodWindow(after: date(hour: 15)), date(hour: 21))
    }

    func testLearnedWindowsFollowRealStartsWithOneHourSmoothing() {
        let model = learnedModel()
        XCTAssertEqual(model.mode, .learned)

        XCTAssertTrue(model.isGoodWindow(date(hour: 22, minute: 30)))
        XCTAssertTrue(model.isGoodWindow(date(hour: 11, minute: 15)))
        XCTAssertTrue(model.isGoodWindow(date(hour: 21)), "Smoothing: 22:00 informs 21:00")
        XCTAssertFalse(model.isGoodWindow(date(hour: 15)))
        XCTAssertFalse(model.isGoodWindow(date(hour: 9)))

        XCTAssertGreaterThan(model.p(date(hour: 22)), model.p(date(hour: 21)))
        XCTAssertGreaterThan(model.p(date(hour: 21)), model.p(date(hour: 15)))
        XCTAssertEqual(model.tier(date(hour: 22)), .high)
        XCTAssertEqual(model.tier(date(hour: 4)), .low)
        XCTAssertTrue([11, 22].contains(model.usualStartHour(on: date(hour: 9)) ?? -1))
    }

    func testPosteriorIsBetaWithWeakPrior() {
        let model = learnedModel()
        let posterior = model.posterior(date(hour: 22))
        XCTAssertGreaterThan(posterior.alpha, CoachAvailabilityModel.priorAlpha)
        let empty = CoachAvailabilityModel.empty
        let prior = empty.posterior(date(hour: 22))
        XCTAssertEqual(prior.alpha, 1)
        XCTAssertEqual(prior.beta, 20)
        XCTAssertEqual(empty.p(date(hour: 22)), 1.0 / 21.0, accuracy: 1e-9)
    }

    func testNextGoodWindowAndMinutesLeftToday() {
        let model = learnedModel()
        XCTAssertEqual(model.nextGoodWindow(after: date(hour: 14)), date(hour: 21))
        XCTAssertEqual(model.goodWindowMinutesRemainingToday(from: date(hour: 20)), 180)
        XCTAssertEqual(model.goodWindowMinutesRemainingToday(from: date(hour: 22, minute: 30)), 90)
    }

    func testOpportunityExcludesSessionTimeAndWeightsNightLower() {
        let day = date(hour: 0)
        let start = date(hour: 22)
        let opportunities = CoachAvailabilityModel.opportunityHours(
            sessions: [.init(start: start, end: start.addingTimeInterval(30 * 60))],
            activeDays: [day],
            calendar: calendar
        )
        let index22 = CoachAvailabilityModel.bucketIndex(for: start, calendar: calendar)
        let index3 = CoachAvailabilityModel.bucketIndex(for: date(hour: 3), calendar: calendar)
        let index15 = CoachAvailabilityModel.bucketIndex(for: date(hour: 15), calendar: calendar)
        XCTAssertEqual(opportunities[index22], 0.5, accuracy: 1e-9)
        XCTAssertEqual(opportunities[index3], 0.2, accuracy: 1e-9)
        XCTAssertEqual(opportunities[index15], 1.0, accuracy: 1e-9)
    }

    func testSmoothingWrapsAcrossTheWeek() {
        var values = [Double](repeating: 0, count: 168)
        values[0] = 2
        let smoothed = CoachAvailabilityModel.smooth(values)
        XCTAssertEqual(smoothed[0], 2)
        XCTAssertEqual(smoothed[1], 1)
        XCTAssertEqual(smoothed[167], 1)
    }
}
