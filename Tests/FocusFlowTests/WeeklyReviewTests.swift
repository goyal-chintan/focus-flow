import XCTest
import SwiftUI
import SwiftData
@testable import FocusFlow

/// Coach v8 phase 4: the weekly review and "Plan today?" (docs/plans/2026-11-06-coach-v8-life-coach.md §3.5).
final class WeeklyReviewTests: XCTestCase {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return c
    }

    /// November 2026: the 8th is a Sunday, the 9th a Monday.
    private func date(_ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    func testTheReviewIsDueSundayEveningUntilMondayNoon() {
        XCTAssertNil(WeeklyReviewPolicy.window(containing: date(8, 18, 59), calendar: calendar))
        XCTAssertEqual(WeeklyReviewPolicy.window(containing: date(8, 19, 30), calendar: calendar)?.start, date(8, 19))
        XCTAssertEqual(WeeklyReviewPolicy.window(containing: date(9, 11), calendar: calendar)?.end, date(9, 12))
        XCTAssertNil(WeeklyReviewPolicy.window(containing: date(9, 12, 1), calendar: calendar))
        XCTAssertNil(WeeklyReviewPolicy.window(containing: date(7, 20), calendar: calendar), "Saturday is not review night")

        XCTAssertTrue(WeeklyReviewPolicy.isDue(now: date(8, 19, 30), lastDone: date(1, 20), lastOffered: nil, calendar: calendar))
        XCTAssertFalse(WeeklyReviewPolicy.isDue(now: date(8, 21), lastDone: date(8, 19, 45), lastOffered: nil, calendar: calendar), "Done this week")
        XCTAssertFalse(WeeklyReviewPolicy.isDue(now: date(8, 21), lastDone: nil, lastOffered: date(8, 19, 30), calendar: calendar), "Later waits 3 h")
        XCTAssertTrue(WeeklyReviewPolicy.isDue(now: date(9, 9), lastDone: nil, lastOffered: date(8, 19, 30), calendar: calendar), "Monday morning asks again")
    }

    func testTheWeekReviewedAndTheDaysPlanned() {
        XCTAssertEqual(WeeklyReviewPolicy.reviewedWeekStart(date(8, 20), calendar: calendar), date(2), "Sunday reviews Mon 2 – Sun 8")
        XCTAssertEqual(WeeklyReviewPolicy.reviewedWeekStart(date(9, 9), calendar: calendar), date(2), "Monday morning reviews the same week")
        XCTAssertEqual(WeeklyReviewPolicy.planDays(date(8, 20), calendar: calendar).first, date(9), "On Sunday the plan starts tomorrow")
        XCTAssertEqual(WeeklyReviewPolicy.planDays(date(9, 9), calendar: calendar).first, date(9), "On Monday it starts today")
        XCTAssertEqual(WeeklyReviewPolicy.planDays(date(8, 20), calendar: calendar).count, 7)
        let workdays = (9...13).map { date($0) }
        XCTAssertEqual(WeeklyReviewPolicy.anchorDays(workdays, calendar: calendar), [date(10), date(12)], "Tuesday and Thursday")
        XCTAssertEqual(WeeklyReviewPolicy.anchorDays([date(9), date(11), date(13)], calendar: calendar), [date(9), date(11)])
    }

    func testPlanTodayAsksOnAnUnplannedDayOffMorning() {
        XCTAssertTrue(PlanTodayPolicy.shouldAsk(type: .weekend, now: date(7, 9), hasPlanToday: false, ownMinutesToday: 0, plannedDaysLastWeek: 0, calendar: calendar))
        XCTAssertFalse(PlanTodayPolicy.shouldAsk(type: .workday, now: date(6, 9), hasPlanToday: false, ownMinutesToday: 0, plannedDaysLastWeek: 0, calendar: calendar))
        XCTAssertFalse(PlanTodayPolicy.shouldAsk(type: .weekend, now: date(7, 14), hasPlanToday: false, ownMinutesToday: 0, plannedDaysLastWeek: 0, calendar: calendar), "Mornings only")
        XCTAssertFalse(PlanTodayPolicy.shouldAsk(type: .leave, now: date(6, 9), hasPlanToday: true, ownMinutesToday: 0, plannedDaysLastWeek: 0, calendar: calendar))
        XCTAssertFalse(PlanTodayPolicy.shouldAsk(type: .weekend, now: date(7, 9), hasPlanToday: false, ownMinutesToday: 30, plannedDaysLastWeek: 0, calendar: calendar), "Already working")
        XCTAssertFalse(PlanTodayPolicy.shouldAsk(type: .weekend, now: date(7, 9), hasPlanToday: false, ownMinutesToday: 0, plannedDaysLastWeek: 2, calendar: calendar), "You plan already")
        XCTAssertEqual(PlanTodayPolicy.times(now: date(7, 9, 50), usualHour: 10, calendar: calendar), [date(7, 14), date(7, 18)], "10:00 is only 10 min away")
        XCTAssertEqual(PlanTodayPolicy.times(now: date(7, 8), usualHour: 10, calendar: calendar), [date(7, 10), date(7, 14), date(7, 18)])
    }

    func testPlanTodayQuestionHasTimesAndAResting() {
        let q = CoachQuestion.planToday(day: date(7), times: [date(7, 10), date(7, 14)])
        XCTAssertEqual(q.choices.map(\.title), [CoachQuestion.clock(date(7, 10)), CoachQuestion.clock(date(7, 14)), "Resting today"])
        XCTAssertTrue(q.id.hasPrefix("plan_today."))
    }

    func testStoreKeepsOneReviewPerWeek() {
        let defaults = cleanDefaults("weeklyreview")
        let store = WeeklyReviewStore(defaults: defaults)
        store.append(WeeklyReviewRecord(weekStart: date(2), completedAt: date(8, 20), pickID: nil, pickTitle: nil, plannedBlocks: 3, obstacle: "Calls"))
        store.append(WeeklyReviewRecord(weekStart: date(2), completedAt: date(8, 21), pickID: "x", pickTitle: "X", plannedBlocks: 4, obstacle: "Calls late"))
        XCTAssertEqual(store.records().count, 1, "A second review of the same week replaces the first")
        XCTAssertEqual(store.last?.obstacle, "Calls late")
        defaults.set(Data("junk".utf8), forKey: WeeklyReviewStore.recordsKey)
        XCTAssertTrue(store.records().isEmpty, "Unreadable data is ignored, never a crash")
    }
}

@MainActor
final class WeeklyReviewStoreTests: XCTestCase {
    private var container: ModelContainer!
    private var vm: TimerViewModel!
    private var defaults: UserDefaults!

    private static let schema = Schema([
        Project.self, FocusSession.self, AppSettings.self, TimeSplit.self, BlockProfile.self, AppUsageRecord.self, AppUsageEntry.self,
        TaskIntent.self, CoachInterruption.self, InterventionAttempt.self, BreakLearningEvent.self, IdleDistractionItem.self,
        WeeklyPriority.self, PlannedBlock.self, ProjectGoal.self, GoalKeyResult.self, GoalProgressEntry.self, DailyTask.self,
        BlockStartEvent.self, ActivityHour.self, DayLabel.self, AppRoleRuleRecord.self,
    ])

    override func setUp() async throws {
        try await super.setUp()
        container = try ModelContainer(for: Self.schema, configurations: ModelConfiguration(schema: Self.schema, isStoredInMemoryOnly: true))
        defaults = cleanDefaults("weeklyreview.vm")
        let settings = AppSettings()
        settings.coachQuietStartMinute = 0
        settings.coachQuietEndMinute = 0
        container.mainContext.insert(settings)
        try container.mainContext.save()
        vm = TimerViewModel(defaults: defaults)
        vm.systemIdleSecondsProvider = { 0 }
        vm.configureForEvidence(modelContext: container.mainContext, settings: settings)
    }

    override func tearDown() async throws {
        AppUsageTracker.shared.stop()
        vm = nil; container = nil
        try await super.tearDown()
    }

    /// The next Sunday at `hour`, local time.
    private func sunday(_ hour: Int) -> Date {
        let cal = Calendar.current
        var day = cal.startOfDay(for: Date().addingTimeInterval(86_400))
        while cal.component(.weekday, from: day) != 1 { day = cal.date(byAdding: .day, value: 1, to: day)! }
        return cal.date(bySettingHour: hour, minute: 30, second: 0, of: day)!
    }

    func testCompletingAReviewPlansBlocksAppliesThePickAndRecordsIt() throws {
        let now = Date()
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now))!.addingTimeInterval(10 * 3600)
        let pick = LifeRecommendation(id: "leaveTarget", kind: .leaveTarget, title: "Leave days: aim higher", evidence: "", impact: "",
                                      actionTitle: "", action: .setTarget(.leave, 180), weight: 1, confidence: 1)
        vm.weeklyReviewRequested = true
        let record = vm.completeWeeklyReview(pick: pick, blocks: [tomorrow, now.addingTimeInterval(-60)], obstacle: "  Late calls  ", now: now)
        XCTAssertEqual(record.plannedBlocks, 1, "A time already past is not planned")
        XCTAssertEqual(record.obstacle, "Late calls")
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<PlannedBlock>()).count, 1)
        XCTAssertEqual(vm.dayTargets()[.leave], 180)
        XCTAssertNotNil(LifeRecStore(defaults: defaults).load()["leaveTarget"]?.pickedAt)
        XCTAssertEqual(vm.lastWeeklyReview?.pickTitle, "Leave days: aim higher")
        XCTAssertFalse(vm.weeklyReviewRequested, "Finishing closes the sheet")
    }

    func testTheSundayInviteStartsTheReviewAndLaterWaits() throws {
        let at = sunday(19)
        XCTAssertTrue(vm.evaluateWeeklyReviewInvite(now: at))
        XCTAssertEqual(vm.coachPanel?.questionID, "weekly_review")
        vm.answerCoachQuestion(CoachQuestionChoice(id: "start", title: "Start review"), now: at)
        XCTAssertTrue(vm.weeklyReviewRequested)
        vm.weeklyReviewRequested = false
        XCTAssertNil(vm.coachPanel, "Answering closes the panel")
        XCTAssertFalse(vm.evaluateWeeklyReviewInvite(now: at.addingTimeInterval(3600)), "Offered an hour ago")
        vm.completeWeeklyReview(pick: nil, blocks: [], obstacle: "", now: at.addingTimeInterval(3600))
        XCTAssertFalse(vm.evaluateWeeklyReviewInvite(now: at.addingTimeInterval(14 * 3600)), "Done this week: Monday morning stays quiet")
    }

    func testPlanTodayOnALeaveMorningPlansTheChosenTime() throws {
        var morning = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date().addingTimeInterval(86_400))!
        while DayType.isWeekend(morning) { morning = morning.addingTimeInterval(86_400) }
        XCTAssertNil(vm.planTodayQuestion(now: morning), "A workday")
        vm.setDayType(morning, type: .leave)
        guard case .planToday(_, let times)? = vm.planTodayQuestion(now: morning) else { return XCTFail("Expected Plan today?") }
        XCTAssertFalse(times.isEmpty)
        vm.presentCoachQuestion(.planToday(day: Calendar.current.startOfDay(for: morning), times: times), now: morning)
        vm.answerCoachQuestion(CoachQuestionChoice(id: "\(Int(times[0].timeIntervalSince1970))", title: ""), now: morning)
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<PlannedBlock>()).map(\.startAt), [times[0]])
        XCTAssertNil(vm.planTodayQuestion(now: morning), "Planned: no second ask")
    }

    func testPlanDaysReadYourDayLabels() throws {
        let now = Date()
        let days = WeeklyReviewPolicy.planDays(now)
        let workday = try XCTUnwrap(days.first { !DayType.isWeekend($0) })
        vm.setDayType(workday, type: .leave)
        let plan = vm.weeklyPlanDays(now: now)
        XCTAssertEqual(plan.count, 7)
        XCTAssertEqual(plan.first { $0.day == workday }?.type, .leave)
        XCTAssertTrue(plan.filter { DayType.isWeekend($0.day) }.allSatisfy { $0.type == .weekend })
    }
}

@MainActor
final class WeeklyReviewRenderTests: XCTestCase {
    /// Draws the review sheet and Your week with real data paths (no crash, no layout loop).
    func testTheReviewSheetAndYourWeekRender() throws {
        let schema = FocusFlowSchema.schema
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        let context = container.mainContext
        let settings = AppSettings(); context.insert(settings)
        let project = Project(name: "Learning"); project.area = .personal; context.insert(project)
        for i in 0..<20 {
            let s = FocusSession(type: .focus, duration: 1500, project: project)
            s.startedAt = Date().addingTimeInterval(-Double(i) * 43_200 - 3600); s.endedAt = s.startedAt.addingTimeInterval(1800); s.completed = true
            context.insert(s)
        }
        try context.save()
        let vm = TimerViewModel(defaults: cleanDefaults("review.render"))
        vm.configureForEvidence(modelContext: context, settings: settings)
        defer { AppUsageTracker.shared.stop() }

        for view in [AnyView(WeeklyReviewView(now: Date()) {}), AnyView(InsightsView().frame(width: 900, height: 1400))] {
            let host = NSHostingView(rootView: view.environment(vm).modelContainer(container))
            host.frame = NSRect(x: 0, y: 0, width: 900, height: 1400)
            host.layoutSubtreeIfNeeded()
            XCTAssertGreaterThan(host.fittingSize.height, 100)
        }
    }
}
