import XCTest
@testable import FocusFlow

final class InsightsWindowingTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testOverlappingFocusSessionsIncludeSessionStartingBeforeWindowAndEndingInside() {
        let interval = DateInterval(
            start: date(year: 2026, month: 4, day: 10, hour: 0, minute: 0),
            end: date(year: 2026, month: 4, day: 17, hour: 0, minute: 0)
        )
        let overlapping = makeFocusSession(
            startedAt: date(year: 2026, month: 4, day: 9, hour: 23, minute: 45),
            endedAt: date(year: 2026, month: 4, day: 10, hour: 0, minute: 20),
            completed: true
        )

        let sessions = InsightsWindowing.overlappingFocusSessions([overlapping], in: interval)

        XCTAssertEqual(sessions.map { $0.id }, [overlapping.id])
    }

    func testOverlappingFocusSessionsExcludeSessionsOutsideOrTouchingBoundary() {
        let interval = DateInterval(
            start: date(year: 2026, month: 4, day: 10, hour: 0, minute: 0),
            end: date(year: 2026, month: 4, day: 17, hour: 0, minute: 0)
        )
        let endsAtStartBoundary = makeFocusSession(
            startedAt: date(year: 2026, month: 4, day: 9, hour: 23, minute: 0),
            endedAt: date(year: 2026, month: 4, day: 10, hour: 0, minute: 0),
            completed: true
        )
        let startsAtEndBoundary = makeFocusSession(
            startedAt: date(year: 2026, month: 4, day: 17, hour: 0, minute: 0),
            endedAt: date(year: 2026, month: 4, day: 17, hour: 0, minute: 25),
            completed: true
        )
        let fullyBeforeWindow = makeFocusSession(
            startedAt: date(year: 2026, month: 4, day: 9, hour: 20, minute: 0),
            endedAt: date(year: 2026, month: 4, day: 9, hour: 20, minute: 25),
            completed: true
        )

        let sessions = InsightsWindowing.overlappingFocusSessions(
            [endsAtStartBoundary, startsAtEndBoundary, fullyBeforeWindow],
            in: interval
        )

        XCTAssertTrue(sessions.isEmpty)
    }

    func testCompletionRateUsesOnlySessionsOverlappingExplicitTrailingSevenDayWindow() throws {
        let now = date(year: 2026, month: 4, day: 16, hour: 14, minute: 0)
        let interval = try XCTUnwrap(
            InsightsWindowing.trailing7DayInterval(relativeTo: now, calendar: calendar)
        )
        let overlappingCompleted = makeFocusSession(
            startedAt: interval.start.addingTimeInterval(-15 * 60),
            endedAt: interval.start.addingTimeInterval(20 * 60),
            completed: true
        )
        let insideDayOffset = TimeInterval((2 * 24 * 60 * 60) + (9 * 60 * 60))
        let overlappingIncomplete = makeFocusSession(
            startedAt: interval.start.addingTimeInterval(insideDayOffset),
            endedAt: interval.start.addingTimeInterval(insideDayOffset + 25 * 60),
            completed: false
        )
        let outsideBeforeWindow = makeFocusSession(
            startedAt: interval.start.addingTimeInterval(-2 * 60 * 60),
            endedAt: interval.start.addingTimeInterval(-60 * 60),
            completed: true
        )
        let startsAtWindowEnd = makeFocusSession(
            startedAt: interval.end,
            endedAt: interval.end.addingTimeInterval(25 * 60),
            completed: true
        )

        let rate = InsightsWindowing.completionRate(
            for: [overlappingCompleted, overlappingIncomplete, outsideBeforeWindow, startsAtWindowEnd],
            in: interval
        )

        XCTAssertEqual(rate, 0.5, accuracy: 0.0001)
    }

    private func makeFocusSession(startedAt: Date, endedAt: Date, completed: Bool) -> FocusSession {
        let session = FocusSession(type: .focus, duration: endedAt.timeIntervalSince(startedAt))
        session.startedAt = startedAt
        session.endedAt = endedAt
        session.completed = completed
        return session
    }

    private func date(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
        let components = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        )
        return components.date!
    }
}
