import XCTest
@testable import FocusFlow

/// Coach v3 start engine (docs/plans/2026-10-19-coach-v3-start-engine-design.md): planned starts,
/// the cap and unseen fixes, the motivation line, today's line and coach insights. Pure logic.
final class CoachV3StartEngineTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return calendar
    }()

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    // MARK: Suggested start times

    func testNoDataSuggestsNextFreeHalfHourAndEveningTimes() {
        let now = date(19, 17, 47)
        let slots = CoachDailyPlanner.suggestions(now: now, model: .empty, busy: [], quietStartMinute: 30, quietEndMinute: 420, calendar: calendar)
        XCTAssertEqual(slots.map { $0.label(calendar: calendar) }, ["18:00", "21:00", "22:00"])
        XCTAssertEqual(slots.first?.reason, .soon)
    }

    func testSuggestionsSkipBusyEventsAndQuietHours() {
        let now = date(19, 17, 47)
        let meeting = DateInterval(start: date(19, 17, 50), end: date(19, 19, 0))
        let slots = CoachDailyPlanner.suggestions(now: now, model: .empty, busy: [meeting], quietStartMinute: 30, quietEndMinute: 420, calendar: calendar)
        XCTAssertEqual(slots.first?.label(calendar: calendar), "19:00", "First slot after the meeting")
        let candidates = CoachDailyPlanner.candidateStarts(now: date(19, 23, 40), busy: [], quietStartMinute: 30, quietEndMinute: 420, calendar: calendar)
        XCTAssertEqual(candidates.map { CoachPlanSlot(start: $0, reason: .soon).label(calendar: calendar) }, ["00:00"], "Nothing in quiet hours")
    }

    func testLearnedWindowsComeFirstWithTheirLift() {
        // A 22:00 start on each of the last 42 days: 22:00 becomes a learned window.
        let sessions: [CoachAvailabilityModel.Session] = (1...42).map { offset in
            let start = date(19, 22).addingTimeInterval(TimeInterval(-offset * 86_400))
            return .init(start: start, end: start.addingTimeInterval(1800))
        }
        let activeDays = (0..<60).map { date(19, 12).addingTimeInterval(TimeInterval(-$0 * 86_400)) }
        let model = CoachAvailabilityModel(sessions: sessions, activeDays: activeDays, calendar: calendar)
        XCTAssertEqual(model.mode, .learned)
        let slots = CoachDailyPlanner.suggestions(now: date(19, 17, 47), model: model, busy: [], quietStartMinute: 30, quietEndMinute: 420, calendar: calendar)
        let best = slots.first { if case .bestWindow = $0.reason { return true }; return false }
        XCTAssertNotNil(best)
        XCTAssertEqual(best.map { calendar.component(.hour, from: $0.start) }.map { (21...23).contains($0) }, true)
        if case .bestWindow(let lift)? = best?.reason { XCTAssertGreaterThan(lift ?? 0, 1.5) }
    }

    // MARK: The cue

    func testCueStepsThroughNotYetCueWaitAndExpire() {
        let start = date(19, 22)
        XCTAssertEqual(CoachPlannedCue.step(startAt: start, now: start.addingTimeInterval(-60), calendarBusy: false), .notYet)
        XCTAssertEqual(CoachPlannedCue.step(startAt: start, now: start, calendarBusy: false), .cue)
        XCTAssertEqual(CoachPlannedCue.step(startAt: start, now: start.addingTimeInterval(30 * 60), calendarBusy: true), .waitForCalendar)
        XCTAssertEqual(CoachPlannedCue.step(startAt: start, now: start.addingTimeInterval(61 * 60), calendarBusy: true), .expire)
        XCTAssertEqual(CoachPlannedCue.step(startAt: start, now: start.addingTimeInterval(91 * 60), calendarBusy: false), .expire)
    }

    func testStartWindowAndPushes() {
        let start = date(19, 22)
        XCTAssertTrue(CoachPlannedCue.fulfills(startAt: start, sessionStart: start.addingTimeInterval(-29 * 60)))
        XCTAssertFalse(CoachPlannedCue.fulfills(startAt: start, sessionStart: start.addingTimeInterval(-31 * 60)))
        XCTAssertTrue(CoachPlannedCue.fulfills(startAt: start, sessionStart: start.addingTimeInterval(89 * 60)))
        XCTAssertEqual(CoachPlannedCue.pushed(startAt: start, now: start.addingTimeInterval(120), minutes: 15), start.addingTimeInterval(17 * 60))
        XCTAssertTrue(CoachPlannedCue.canPush(pushes: 2))
        XCTAssertFalse(CoachPlannedCue.canPush(pushes: 3))
        XCTAssertTrue(CoachPlannedCue.isPlannedContextKey(CoachPlannedCue.contextKey(blockID: UUID())))
        XCTAssertFalse(CoachPlannedCue.isPlannedContextKey("avail:low|idle:30-90"))
    }

    // MARK: The plan card

    func testInviteOnlyAtABreakpointOnceOrTwiceADay() {
        let now = date(19, 9, 30)
        var input = CoachDailyPlanInvite.Input(
            now: now, hasPlanToday: false, goalMet: false, sessionActive: false, quietHours: false,
            calendarBusy: false, screenShare: false, released: false, userIdleSeconds: 3,
            panelShowing: false, log: .fresh(for: now, calendar: calendar), hasSuggestions: true
        )
        XCTAssertTrue(CoachDailyPlanInvite.shouldInvite(input, calendar: calendar))

        input.userIdleSeconds = 600
        XCTAssertFalse(CoachDailyPlanInvite.shouldInvite(input, calendar: calendar), "Away from the desk: wait for a breakpoint")
        input.userIdleSeconds = 3

        input.log.shown = 1
        input.log.lastShownAt = now.addingTimeInterval(-3600)
        XCTAssertFalse(CoachDailyPlanInvite.shouldInvite(input, calendar: calendar), "Retry only after 2 hours")
        input.log.lastShownAt = now.addingTimeInterval(-3 * 3600)
        XCTAssertTrue(CoachDailyPlanInvite.shouldInvite(input, calendar: calendar))
        input.log.shown = 2
        XCTAssertFalse(CoachDailyPlanInvite.shouldInvite(input, calendar: calendar), "At most twice a day")

        input.log = .fresh(for: now, calendar: calendar)
        input.log.declined = true
        XCTAssertFalse(CoachDailyPlanInvite.shouldInvite(input, calendar: calendar), "Not today is respected")

        // A new day resets the log.
        let yesterdayLog = CoachDailyPlanInvite.Log(day: calendar.startOfDay(for: date(18, 9)), shown: 2, lastShownAt: date(18, 21), declined: true)
        input.log = yesterdayLog
        XCTAssertTrue(CoachDailyPlanInvite.shouldInvite(input, calendar: calendar))

        input.hasPlanToday = true
        XCTAssertFalse(CoachDailyPlanInvite.shouldInvite(input, calendar: calendar))
    }

    // MARK: Cap (R1) and unseen (R3)

    func testCapCountsOnlyPromptsThatInterruptedAndWereSeen() {
        let now = date(19, 21)
        var input = CoachGuardrails.Input(now: now, calendar: calendar, quietStartMinute: 0, quietEndMinute: 0)
        input.maxPromptsPerDay = 3
        input.deliveries = [
            .init(surface: .badge, deliveredAt: now.addingTimeInterval(-600)),
            .init(surface: .badge, deliveredAt: now.addingTimeInterval(-900)),
            .init(surface: .panel, deliveredAt: now.addingTimeInterval(-1200), countsTowardCap: false),
            .init(surface: .panel, deliveredAt: now.addingTimeInterval(-1500)),
            .init(surface: .panel, deliveredAt: now.addingTimeInterval(-1800)),
        ]
        input.ignorePanelSpacing = true
        XCTAssertEqual(CoachGuardrails().verdict(for: .panel, input: input), .allowed, "Badges and planned/unseen panels don't use up the cap")
        input.deliveries.append(.init(surface: .panel, deliveredAt: now.addingTimeInterval(-2100)))
        XCTAssertEqual(CoachGuardrails().verdict(for: .panel, input: input), .dailyCapReached)
    }

    func testAPanelIsUnseenOnlyWhenThereWasNoInputForItsWholeLife() {
        XCTAssertTrue(TimerViewModel.panelWasUnseen(shownFor: 180, systemIdleSeconds: 400))
        XCTAssertTrue(TimerViewModel.panelWasUnseen(shownFor: 180, systemIdleSeconds: 176))
        XCTAssertFalse(TimerViewModel.panelWasUnseen(shownFor: 180, systemIdleSeconds: 30))
    }

    func testStickyPanelsNeverAutoHide() {
        let message = CoachMessageComposer.neutralFallback(isInSession: false)
        XCTAssertNil(CoachPanelPresentation(kind: .plannedStart, message: message).autoHideSeconds)
        XCTAssertNil(CoachPanelPresentation(kind: .dailyPlan, message: message).autoHideSeconds)
        XCTAssertEqual(CoachPanelPresentation(kind: .rescue, message: message).autoHideSeconds, 180)
        XCTAssertEqual(CoachPanelPresentation(kind: .notice, message: message).autoHideSeconds, 3.5)
        XCTAssertEqual(CoachPanelPresentation(kind: .plannedStart, message: message).escapeAction, .push15)
        XCTAssertFalse(CoachPanelPresentation(kind: .dailyPlan, message: message).hasPrimary)
    }

    // MARK: Motivation line (R6)

    private func compose(_ trigger: CoachTrigger, style: CoachStyle = .challenger, facts: CoachFacts = CoachFacts(), picked: CoachDetail? = nil) -> CoachComposedMessage {
        var input = CoachComposerInput(style: style, trigger: trigger, facts: facts, target: CoachStartTarget(minutes: 50, name: "Book draft"))
        input.pickedDetail = picked
        return CoachMessageComposer.compose(input)
    }

    func testChallengerPromptsCarryAQuoteNextToTheFact() {
        var facts = CoachFacts()
        facts.goalMinutes = 120
        facts.doneMinutesToday = 25
        facts.sessionsToday = 1
        let quote = CoachQuoteLibrary.quote(id: "clear-systems")!

        let start = compose(.startNudge, facts: facts, picked: .quote(quote))
        XCTAssertEqual(start.detail, .fact("25m of 120m today."))
        XCTAssertEqual(start.motivation, .quote(quote), "Before v3 the fact displaced the quote")
        XCTAssertTrue(start.showsMotivation)

        let rescue = CoachRescueContext(
            level: .lost, signal: .derailer(name: "YouTube", minutes: 22), spanLabel: "today",
            ask: CoachRescueLadder.ask(level: .lost, target: CoachStartTarget(minutes: 50, name: nil), starterMinutes: 5)!
        )
        let lost = compose(.rescue(rescue), facts: facts, picked: .houseLine("Discipline is choosing what you want most over what you want now."))
        XCTAssertNotNil(lost.motivation, "L2 used to show only the fixed 1% line")

        let data = compose(.startNudge, style: .data, facts: facts, picked: .quote(quote))
        XCTAssertNil(data.motivation, "Data style stays numbers-only")

        let fact = compose(.startNudge, facts: facts)
        XCTAssertTrue(fact.motivation != nil, "Without a picked item the seeded rotation still supplies one")
    }

    func testPlannedCueCopy() {
        var facts = CoachFacts()
        facts.goalMinutes = 120
        let cue = CoachPlannedCueContext(timeLabel: "22:00", minutes: 50, priorityName: "Book draft")
        let message = compose(.plannedStart(cue), facts: facts)
        XCTAssertEqual(message.hook, "22:00. You said you'd start now.")
        XCTAssertEqual(message.primaryTitle, "Start 50m on Book draft")
        XCTAssertEqual(message.detail, .fact("0m of 120m today."))
        XCTAssertNotNil(message.motivation)

        var pushed = cue
        pushed.pushes = 2
        XCTAssertEqual(compose(.plannedStart(pushed)).hook, "Pushed 2 times. Start small. Start now.")
        var missed = cue
        missed.missedYesterday = true
        XCTAssertEqual(compose(.plannedStart(missed)).hook, "22:00. Missed yesterday. Never miss twice.")
        XCTAssertEqual(compose(.plannedStart(cue), style: .gentle).hook, "It's 22:00, your planned block.")

        let invite = compose(.dailyPlan(goalMinutes: 120, firstSuggestion: "21:00"))
        XCTAssertEqual(invite.hook, "When is today's 2h? Decide now.")
        XCTAssertEqual(invite.primaryTitle, "")
    }

    func testTodaysLineIsStableForADayAndRotates() {
        let day = date(19, 10)
        let first = CoachQuoteLibrary.dailyLine(style: .challenger, on: day, calendar: calendar)
        XCTAssertEqual(first, CoachQuoteLibrary.dailyLine(style: .challenger, on: date(19, 23), calendar: calendar))
        XCTAssertNotEqual(first, CoachQuoteLibrary.dailyLine(style: .challenger, on: date(20, 10), calendar: calendar))
        XCTAssertNotEqual(first, CoachQuoteLibrary.dailyLine(style: .challenger, on: day, offset: 1, calendar: calendar))
        XCTAssertFalse(CoachQuoteLibrary.lines(for: .gentle).contains { $0.isHouseLine })
        // Over a month every day has a line, and lines vary.
        let month = Set((1...28).compactMap { CoachQuoteLibrary.dailyLine(style: .challenger, on: date($0, 10), calendar: calendar)?.id })
        XCTAssertGreaterThan(month.count, 10)
    }

    // MARK: Insights and advice

    func testChainMarksGoalPartialMissedAndOpen() {
        let now = date(19, 20)
        let sessions = [
            CoachInsights.SessionInput(start: date(18, 22), seconds: 130 * 60, outcome: nil),
            CoachInsights.SessionInput(start: date(17, 22), seconds: 25 * 60, outcome: nil),
        ]
        let chain = CoachInsights.chainDays(now: now, goalMinutes: 120, sessions: sessions, calendar: calendar)
        XCTAssertEqual(chain.count, 14)
        XCTAssertEqual(chain.last?.mark, .open)
        XCTAssertEqual(chain[chain.count - 2].mark, .goal)
        XCTAssertEqual(chain[chain.count - 3].mark, .partial)
        XCTAssertEqual(chain[chain.count - 4].mark, .missed)
    }

    func testAdviceComesFromTheUsersDataWithACitation() {
        let now = date(19, 20) // a Monday
        let sessions = [CoachInsights.SessionInput(start: date(17, 22), seconds: 25 * 60, outcome: .busywork)]
        let summary = CoachInsights.summary(now: now, goalMinutes: 120, sessions: sessions, plans: [], prompts: [], model: .empty, starterMinutes: 5, calendar: calendar)
        let kinds = summary.advice.map(\.kind)
        XCTAssertEqual(kinds.first, .neverMissTwice, "Missed yesterday and nothing today")
        XCTAssertTrue(kinds.contains(.decideWhen))
        XCTAssertLessThanOrEqual(summary.advice.count, 3)
        XCTAssertTrue(summary.advice.allSatisfy { !$0.citation.isEmpty && !$0.reference.isEmpty })
        XCTAssertTrue(summary.advice.first?.body.contains("5 minutes") == true)
    }

    func testPlanKeptStatsAndPlannedDayStartRate() {
        let now = date(19, 20)
        var plans: [CoachInsights.PlanInput] = []
        var sessions: [CoachInsights.SessionInput] = []
        for offset in 1...6 {
            let day = calendar.startOfDay(for: now.addingTimeInterval(TimeInterval(-offset * 86_400)))
            if offset <= 3 {
                plans.append(.init(day: day, startAt: day.addingTimeInterval(22 * 3600), status: offset == 3 ? .missed : .started, pushes: 0))
                if offset < 3 { sessions.append(.init(start: day.addingTimeInterval(22 * 3600), seconds: 3000, outcome: nil)) }
            }
        }
        let summary = CoachInsights.summary(now: now, goalMinutes: 120, sessions: sessions, plans: plans, prompts: [], model: .empty, starterMinutes: 5, calendar: calendar)
        XCTAssertEqual(summary.plansMade, 3)
        XCTAssertEqual(summary.plansKept, 2)
        XCTAssertEqual(summary.startRatePlannedDays ?? -1, 2.0 / 3.0, accuracy: 0.001)
        XCTAssertEqual(summary.startRateUnplannedDays ?? -1, 0, accuracy: 0.001)
        XCTAssertTrue(summary.advice.contains { $0.kind == .plansWork })
    }

    func testUnseenAndPlannedPromptsDoNotCountAsSeen() {
        let now = date(19, 20)
        let prompts = [
            CoachInsights.PromptInput(deliveredAt: now.addingTimeInterval(-3600), outcome: .unseen, reward: nil, isPlanned: false),
            CoachInsights.PromptInput(deliveredAt: now.addingTimeInterval(-3600), outcome: .improved, reward: 1, isPlanned: true),
            CoachInsights.PromptInput(deliveredAt: now.addingTimeInterval(-3600), outcome: .improved, reward: 1, isPlanned: false),
            CoachInsights.PromptInput(deliveredAt: now.addingTimeInterval(-3600), outcome: .ignored, reward: 0, isPlanned: false),
        ]
        let summary = CoachInsights.summary(now: now, goalMinutes: 120, sessions: [], plans: [], prompts: prompts, model: .empty, starterMinutes: 5, calendar: calendar)
        XCTAssertEqual(summary.promptsSeen, 2)
        XCTAssertEqual(summary.promptsLedToStart, 1)
    }
}
