import XCTest
import SwiftData
@testable import FocusFlow

/// Coach v8 §3.4–3.5: day-type targets and the day timeline.
final class DayTargetsTests: XCTestCase {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return c
    }

    private func date(_ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    func testUnsetTypesFollowTheGoalAndASickDayRests() {
        XCTAssertEqual(DayTargets.minutes(type: .weekend, yours: nil, goalMinutes: 150), 150)
        XCTAssertEqual(DayTargets.minutes(type: .leave, yours: 180, goalMinutes: 150), 180)
        XCTAssertEqual(DayTargets.minutes(type: .sick, yours: nil, goalMinutes: 150), 0)
        XCTAssertEqual(DayTargets.minutes(type: .sick, yours: 30, goalMinutes: 150), 30)
    }

    func testStoreClampsAndAWorkdayAlwaysFollowsGoals() {
        let defaults = cleanDefaults("daytargets")
        let store = DayTargetStore(defaults: defaults)
        store.set(900, for: .leave)
        store.set(120, for: .workday)
        XCTAssertEqual(store.minutes(for: .leave), 600)
        XCTAssertNil(store.minutes(for: .workday), "A workday's target is the Goals tab's daily goal")
        store.set(nil, for: .leave)
        XCTAssertNil(store.minutes(for: .leave))
        store.set(0, for: .weekend)
        XCTAssertEqual(store.minutes(for: .weekend), 0, "Zero is a real answer (rest), not unset")
    }

    func testOnlyASettledDayTypeChangesTheGoal() {
        XCTAssertFalse(DayTargets.isSettled(DayClassification(type: .leave, source: .inferred, confidence: 0.6, reason: "")))
        XCTAssertTrue(DayTargets.isSettled(DayClassification(type: .weekend, source: .inferred, confidence: 0.95, reason: "")))
        XCTAssertTrue(DayTargets.isSettled(DayClassification(type: .leave, source: .calendar, confidence: 0.9, reason: "")))
        XCTAssertTrue(DayTargets.isSettled(DayClassification(type: .leave, source: .user, confidence: 1, reason: "")))
    }

    func testSizedGoalKeepsTheStretchDistance() {
        let base = DailyGoal.resolve(scope: .allFocus, targetMinutes: [150], fixedSeconds: 7200, stretchSeconds: 9000, followsTargets: true)
        let leave = base.sized(minutes: 180, for: .leave)
        XCTAssertEqual(leave.seconds, 10_800)
        XCTAssertEqual(leave.stretchSeconds - leave.seconds, base.stretchSeconds - base.seconds)
        XCTAssertEqual(leave.source, .dayType(.leave))
        XCTAssertEqual(base.sized(minutes: 0, for: .sick).seconds, 60, "Never a zero goal: rings and pacing divide by it")
    }

    // MARK: Timeline

    func testTimelineSplitsBlocksAcrossHoursAndCapsAnHour() {
        let blocks = [DayTimeline.Block(start: date(6, 22, 30), end: date(6, 23, 20), own: true),
                      DayTimeline.Block(start: date(6, 11, 0), end: date(6, 11, 40), own: false)]
        let rows = [
            DayTimeline.Row(hourStart: date(6, 22), key: "app:md.obsidian", label: "Obsidian", inBlock: true, seconds: 1800),
            DayTimeline.Row(hourStart: date(6, 22), key: "domain:youtube.com", label: "youtube.com", inBlock: false, seconds: 1500),
            DayTimeline.Row(hourStart: date(6, 22), key: "away", label: "Away", inBlock: false, seconds: 900),
            DayTimeline.Row(hourStart: date(6, 11), key: "call", label: "Call", inBlock: false, seconds: 1200),
            DayTimeline.Row(hourStart: date(5, 11), key: "call", label: "Call", inBlock: false, seconds: 1200),
        ]
        let timeline = DayTimeline.build(day: date(6, 15), rows: rows, blocks: blocks, isPull: { key, _, _ in key.contains("youtube") }, calendar: calendar)
        XCTAssertEqual(timeline.hours[22].own, 30, accuracy: 0.01)
        XCTAssertEqual(timeline.hours[23].own, 20, accuracy: 0.01)
        XCTAssertEqual(timeline.hours[11].work, 40, accuracy: 0.01)
        XCTAssertEqual(timeline.hours[11].call, 20, accuracy: 0.01, "Yesterday's call row is not today's")
        XCTAssertEqual(timeline.hours[22].total, 60, accuracy: 0.01, "30 block + 15 away leaves 15 of the 25 pull minutes")
        XCTAssertEqual(timeline.hours[22].pull, 15, accuracy: 0.01)
        XCTAssertTrue(timeline.hasRollup)
        XCTAssertEqual(timeline.activeRange, 11...23)
    }

    func testTimelineBeforeTheRollupHasBlocksOnly() {
        let timeline = DayTimeline.build(day: date(1), rows: [], blocks: [DayTimeline.Block(start: date(1, 9), end: date(1, 9, 25), own: true)],
                                         isPull: { _, _, _ in false }, calendar: calendar)
        XCTAssertFalse(timeline.hasRollup)
        XCTAssertEqual(timeline.ownMinutes, 25, accuracy: 0.01)
    }
}

@MainActor
final class DayTargetsStoreTests: XCTestCase {
    private var container: ModelContainer!
    private var vm: TimerViewModel!

    private static let schema = Schema([
        Project.self, FocusSession.self, AppSettings.self, TimeSplit.self, BlockProfile.self, AppUsageRecord.self, AppUsageEntry.self,
        TaskIntent.self, CoachInterruption.self, InterventionAttempt.self, BreakLearningEvent.self, IdleDistractionItem.self,
        WeeklyPriority.self, PlannedBlock.self, ProjectGoal.self, GoalKeyResult.self, GoalProgressEntry.self, DailyTask.self,
        BlockStartEvent.self, ActivityHour.self, DayLabel.self, AppRoleRuleRecord.self,
    ])

    override func tearDown() async throws {
        AppUsageTracker.shared.stop()
        vm = nil; container = nil
        try await super.tearDown()
    }

    func testYourLeaveTargetSizesTodaysGoalOnlyOnceYouSayLeave() throws {
        container = try ModelContainer(for: Self.schema, configurations: ModelConfiguration(schema: Self.schema, isStoredInMemoryOnly: true))
        let context = container.mainContext
        let settings = AppSettings(); settings.dailyFocusGoal = 7200
        context.insert(settings)
        try context.save()
        let defaults = cleanDefaults("daytargets.vm")
        vm = TimerViewModel(defaults: defaults)
        vm.configureForEvidence(modelContext: context, settings: settings)
        // A weekday at 15:00.
        var noon = Calendar.current.date(bySettingHour: 15, minute: 0, second: 0, of: Date())!
        while DayType.isWeekend(noon) { noon = noon.addingTimeInterval(86_400) }

        XCTAssertEqual(vm.dailyGoal(now: noon).seconds, 7200)
        vm.setDayTarget(180, for: .leave)
        XCTAssertEqual(vm.dailyGoal(now: noon).seconds, 7200, "Not leave yet: the workday goal stays")
        vm.setDayType(noon, type: .leave)
        XCTAssertEqual(vm.dailyGoal(now: noon).seconds, 10_800)
        XCTAssertEqual(vm.dayLedger(days: 1, now: noon).last?.targetMinutes, 180, "The ledger judges the day by the same target")
        vm.setDayTarget(nil, for: .leave)
        XCTAssertEqual(vm.dailyGoal(now: noon).seconds, 7200, "Cleared: leave follows the goal again")
        vm.setDayType(noon, type: .sick)
        XCTAssertEqual(vm.dailyGoal(now: noon).seconds, 60, "A sick day rests")
        XCTAssertEqual(vm.dayLedger(days: 1, now: noon).last?.verdict, .rest)
    }
}

@MainActor
final class DayTimelineStoreTests: XCTestCase {
    func testABlockAcrossMidnightShowsOnBothDays() throws {
        let schema = FocusFlowSchema.schema
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        let settings = AppSettings(); container.mainContext.insert(settings)
        let today = Calendar.current.startOfDay(for: Date())
        let block = FocusSession(type: .focus, duration: 3600, project: nil)
        block.startedAt = today.addingTimeInterval(-30 * 60); block.endedAt = today.addingTimeInterval(30 * 60); block.completed = true
        container.mainContext.insert(block)
        try container.mainContext.save()
        let vm = TimerViewModel(defaults: cleanDefaults("timeline"))
        vm.configureForEvidence(modelContext: container.mainContext, settings: settings)
        defer { AppUsageTracker.shared.stop() }
        XCTAssertEqual(vm.dayTimeline(today).hours[0].own, 30, accuracy: 0.01, "Its part after midnight")
        XCTAssertEqual(vm.dayTimeline(today.addingTimeInterval(-3600)).hours[23].own, 30, accuracy: 0.01, "Its part before midnight")
    }
}
