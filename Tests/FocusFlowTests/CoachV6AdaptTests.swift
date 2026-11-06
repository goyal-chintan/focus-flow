import XCTest
@testable import FocusFlow

/// Coach v6 (docs/plans/2026-11-06-coach-v6-adapt-and-speak.md), checked against the live store's
/// shape on 6 Nov 2026.
final class CoachV6AdaptTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return c
    }()

    private func at(day: Int, hour: Int, minute: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    /// Own-work starts per hour in the 30 days before 6 Nov 2026.
    private let liveStartsPerHour: [Int: Int] = [0: 4, 1: 1, 2: 2, 7: 2, 8: 2, 9: 2, 10: 2, 11: 3, 12: 4, 13: 3, 14: 2, 15: 1, 16: 4, 17: 1, 18: 3, 22: 5, 23: 5]
    private let declared = [CoachOwnWorkWindow(startMinute: 420, endMinute: 540), CoachOwnWorkWindow(startMinute: 1200, endMinute: 1320)]

    private func liveStarts() -> [Date] {
        var dates: [Date] = []
        for (hour, count) in liveStartsPerHour {
            for i in 0..<count { dates.append(at(day: 1 + i, hour: hour)) }
        }
        return dates
    }

    // MARK: Window fit

    func testWindowFitFindsWhereOwnWorkActuallyStarts() {
        let fit = CoachWindowFit.compute(startDates: liveStarts(), declared: declared, calendar: calendar)
        XCTAssertEqual(fit.starts, 46)
        XCTAssertEqual(fit.covered, 4, "07–09 holds 4 starts, 20–22 none")
        XCTAssertEqual(fit.observed.map(\.label), ["00:00–01:00", "11:00–14:00", "22:00–24:00"])
        XCTAssertTrue(fit.isMismatch(declared: declared))
    }

    func testEffectiveWindowsAddObservedHoursUntilKeepMine() {
        let fit = CoachWindowFit.compute(startDates: liveStarts(), declared: declared, calendar: calendar)
        let effective = CoachWindowFit.effective(declared: declared, fit: fit, keepMine: false)
        XCTAssertEqual(effective.map(\.label), ["00:00–01:00", "07:00–09:00", "11:00–14:00", "20:00–22:00", "22:00–24:00"])
        XCTAssertNotNil(CoachOwnWorkWindows.current(effective, now: at(day: 6, hour: 22, minute: 30), calendar: calendar), "22:30 is a decision point now")
        XCTAssertEqual(CoachWindowFit.effective(declared: declared, fit: fit, keepMine: true), declared)
    }

    func testWindowsThatMatchAreLeftAlone() {
        let starts = (0..<10).map { at(day: 1 + $0, hour: 7) }
        let fit = CoachWindowFit.compute(startDates: starts, declared: declared, calendar: calendar)
        XCTAssertFalse(fit.isMismatch(declared: declared))
        XCTAssertEqual(CoachWindowFit.effective(declared: declared, fit: fit, keepMine: false), declared)
    }

    func testTooFewStartsIsNotAMismatch() {
        let starts = (0..<5).map { at(day: 1 + $0, hour: 23) }
        XCTAssertFalse(CoachWindowFit.compute(startDates: starts, declared: declared, calendar: calendar).isMismatch(declared: declared))
    }

    // MARK: Questions

    func testWindowAnswersSaveTheRightWindows() {
        let fit = CoachWindowFit.compute(startDates: liveStarts(), declared: declared, calendar: calendar)
        XCTAssertEqual(CoachQuestion.windows(after: .useObserved, declared: declared, fit: fit)?.map(\.label), ["00:00–01:00", "11:00–14:00", "22:00–24:00"])
        XCTAssertEqual(CoachQuestion.windows(after: .addObserved, declared: declared, fit: fit)?.count, 4, "Capped at 4 windows")
        XCTAssertNil(CoachQuestion.windows(after: .keepMine, declared: declared, fit: fit))
    }

    func testWindowQuestionNamesBothSides() {
        let fit = CoachWindowFit.compute(startDates: liveStarts(), declared: declared, calendar: calendar)
        let question = CoachQuestion.windowFit(fit, declared: declared)
        XCTAssertEqual(question.hook, "Your own work starts around 00:00–01:00, 11:00–14:00 and 22:00–24:00. Should I watch those hours?")
        XCTAssertTrue(question.detail.contains("caught 4 of your last 46"))
        XCTAssertEqual(question.choices.map(\.title), ["Use these hours", "Add them to mine", "Keep my windows"])
    }

    func testABusyProjectWithNoAreaIsAskedAbout() {
        let work = UUID(), learning = UUID(), projectWork = UUID()
        let question = CoachQuestion.unclassifiedProject([
            (id: work, name: "Office", hasArea: true, isWork: true, blocks: 20),
            (id: learning, name: "Learning", hasArea: true, isWork: false, blocks: 30),
            (id: projectWork, name: "ProjectWork", hasArea: false, isWork: false, blocks: 31),
        ])
        XCTAssertEqual(question, .projectArea(projectID: projectWork, name: "ProjectWork", blocks: 31))
        XCTAssertNil(CoachQuestion.unclassifiedProject([(id: projectWork, name: "ProjectWork", hasArea: false, isWork: false, blocks: 31)]),
                     "Without a Work project, own work filters nothing, so there is nothing to ask")
    }

    func testQuestionsWaitForAPresentIdleUserOnceADay() {
        let base = CoachQuestionPolicy.Input(now: at(day: 6, hour: 12), askedToday: false, sessionActive: false, panelShowing: false,
                                             quietHours: false, screenShare: false, userIdleSeconds: 5, questionSnoozedUntil: nil)
        XCTAssertTrue(CoachQuestionPolicy.mayAsk(base))
        var input = base; input.askedToday = true
        XCTAssertFalse(CoachQuestionPolicy.mayAsk(input))
        input = base; input.sessionActive = true
        XCTAssertFalse(CoachQuestionPolicy.mayAsk(input))
        input = base; input.userIdleSeconds = 600
        XCTAssertFalse(CoachQuestionPolicy.mayAsk(input))
        input = base; input.screenShare = true
        XCTAssertFalse(CoachQuestionPolicy.mayAsk(input))
        input = base; input.questionSnoozedUntil = at(day: 7, hour: 12)
        XCTAssertFalse(CoachQuestionPolicy.mayAsk(input))
    }

    // MARK: Start card

    func testStartCardNotBeforeTheDayStarts() {
        var input = CoachDailyPlanInvite.Input(
            now: at(day: 6, hour: 0, minute: 5), hasPlanToday: false, goalMet: false, sessionActive: false, quietHours: false,
            calendarBusy: false, screenShare: false, released: false, userIdleSeconds: 5, panelShowing: false,
            log: .fresh(for: at(day: 6, hour: 0, minute: 5), calendar: calendar), hasSuggestions: true
        )
        input.beforeDayStart = true
        XCTAssertFalse(CoachDailyPlanInvite.shouldInvite(input, calendar: calendar))
        input.beforeDayStart = false
        XCTAssertTrue(CoachDailyPlanInvite.shouldInvite(input, calendar: calendar))
    }

    // MARK: Breaks

    func testOverrunReasonsMoveTheBreakTheRightWay() {
        let over = BreakAdaptation.Event(returnedToFocus: false, endedEarly: false, overrunSeconds: 600, reason: nil)
        XCTAssertEqual(BreakAdaptation.minutes(Array(repeating: over, count: 4)), -2, "Unexplained overruns shorten, as before")
        var rest = over; rest.reason = .neededRest
        XCTAssertEqual(BreakAdaptation.minutes(Array(repeating: rest, count: 4)), 3, "Needed the rest: the suggestion was too short")
        var pulled = over; pulled.reason = .pulledAway
        XCTAssertEqual(BreakAdaptation.minutes(Array(repeating: pulled, count: 4)), 0, "Pulled away is not a length problem")
    }

    // MARK: Patterns

    func testBreakPatternStatesTheGap() {
        let breaks = (0..<31).map { i in
            CoachPatterns.Break(suggestedMinutes: 8, actualSeconds: i < 21 ? 21 * 60 : 7 * 60, overrunSeconds: i < 21 ? 13 * 60 : 0, returnedToFocus: i < 22)
        }
        let pattern = CoachPatterns.breakPattern(breaks)
        XCTAssertEqual(pattern?.sentence, "Your breaks run about 21 min against 8 planned. 21 of 31 ran 2+ min over; you came back to focus after 22.")
        XCTAssertNil(CoachPatterns.breakPattern(Array(breaks.prefix(4))), "Needs 5 breaks")
    }

    func testBackToBackBlocksAreNamed() {
        var blocks: [CoachPatterns.Block] = []
        var start = at(day: 5, hour: 10)
        for i in 0..<10 {
            let end = start.addingTimeInterval(25 * 60)
            blocks.append(.init(start: start, end: end, plannedMinutes: 25, focusedSeconds: 1500, completed: true, ownWork: true))
            start = end.addingTimeInterval(i % 2 == 0 ? 1 : 30 * 60)
        }
        XCTAssertEqual(CoachPatterns.backToBack(blocks)?.sentence, "5 of your last 10 blocks started straight after the one before, with no break.")
    }

    func testLengthsSayWhatYouFinish() {
        let start = at(day: 5, hour: 10)
        let blocks = (0..<4).map { _ in CoachPatterns.Block(start: start, end: start, plannedMinutes: 25, focusedSeconds: 31 * 60, completed: true, ownWork: true) }
            + (0..<3).map { _ in CoachPatterns.Block(start: start, end: start, plannedMinutes: 5, focusedSeconds: 17 * 60, completed: true, ownWork: true) }
        XCTAssertEqual(CoachPatterns.lengths(blocks)?.sentence, "5m blocks: 3 of 3 finished, 17 min on average; 25m blocks: 4 of 4 finished, 31 min on average.")
    }

    func testWindowsFitPatternExplainsTheSilence() {
        let fit = CoachWindowFit.compute(startDates: liveStarts(), declared: declared, calendar: calendar)
        XCTAssertEqual(CoachPatterns.windowsFit(fit, declared: declared)?.sentence,
                       "07:00–09:00, 20:00–22:00 caught 4 of 46 own-work starts. The coach only spoke in those hours, so it was quiet when you worked.")
    }

    // MARK: Learners

    func testWarmUpEndsSooner() {
        XCTAssertEqual(CoachPromptPolicy.warmUpDecisions, 15)
    }
}
