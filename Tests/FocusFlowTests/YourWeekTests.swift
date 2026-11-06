import XCTest
import SwiftData
@testable import FocusFlow

/// Coach v8 phase 3: Your week (docs/plans/2026-11-06-coach-v8-life-coach.md §3.4).
final class YourWeekTests: XCTestCase {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return c
    }

    /// 6 Nov 2026 is a Friday.
    private func date(_ day: Int, _ hour: Int = 0) -> Date {
        calendar.date(byAdding: .day, value: day - 6, to: calendar.date(from: DateComponents(year: 2026, month: 11, day: 6, hour: hour))!)!
    }

    private func entry(_ day: Int, _ type: DayType, own: Double, planned: Bool = false, target: Int = 120, open: Bool = false) -> DayEntry {
        DayEntry(day: calendar.startOfDay(for: date(day)), classification: DayClassification(type: type, source: .inferred, confidence: 0.9, reason: ""),
                 planned: planned, ownMinutes: own, officeMinutes: 0, callMinutes: nil, awayMinutes: nil, derailMinutes: 0, targetMinutes: target,
                 verdict: DayVerdict.of(planned: planned, ownMinutes: own, targetMinutes: target, isPast: !open))
    }

    /// 35 days ending day 6 (today): 4 baseline weeks at `base` per workday and `baseFree` per weekend day, then this week.
    private func ledger(base: Double, baseFree: Double, week: [Double]) -> [DayEntry] {
        var out: [DayEntry] = []
        for day in -28...(-1) {
            let d = date(day)
            let weekend = DayType.isWeekend(d, calendar: calendar)
            out.append(entry(day, weekend ? .weekend : .workday, own: weekend ? baseFree : base))
        }
        for (i, own) in week.enumerated() {
            let day = i
            let d = date(day)
            out.append(entry(day, DayType.isWeekend(d, calendar: calendar) ? .weekend : .workday, own: own, open: day == 6))
        }
        return out
    }

    // MARK: Week

    func testWeekOverWeekDeltasOnAFixture() {
        // Baseline: 60 min a workday, 0 on weekends → 300 min a week. This week: 7 × 60 = 420.
        let entries = ledger(base: 60, baseFree: 0, week: [60, 60, 60, 60, 60, 60, 60])
        let week = YourWeek.build(entries: entries, firstDay: date(-28), thisCycle: nil, baselineCycle: nil,
                                  thisSwitches: nil, baselineSwitches: nil, calendar: calendar)
        XCTAssertEqual(week.this.ownMinutes, 420)
        XCTAssertEqual(week.baseline?.ownMinutes ?? 0, 300, accuracy: 0.01)
        let own = week.trends.first { $0.id == "own" }!
        XCTAssertEqual(own.delta, "+40%")
        XCTAssertEqual(own.direction, .better)
        XCTAssertEqual(own.baseline, "avg 5h")
        let days = week.trends.first { $0.id == "consistency" }!
        XCTAssertEqual(days.value, "7/7", "60 min is half of a 120 target: on track")
        XCTAssertEqual(days.direction, .better, "7 days against an average of 5")
        let lost = week.trends.first { $0.id == "lost" }!
        XCTAssertEqual(lost.value, "0")
        XCTAssertEqual(lost.direction, .better, "Baseline lost 2 weekend days a week")
        XCTAssertEqual(week.verdict, .better, "Weekend days compared with weekend days: 60 against 0")
        XCTAssertTrue(week.line.hasPrefix("7h own work (avg 5h)"))
    }

    func testAVerdictComparesLikeDayTypes() {
        // Same totals as the baseline on workdays, but this week has 2 leave days with 200 min each against a 60 workday norm:
        // leave has no baseline days of its own, so the overall mean is the yardstick.
        var entries = ledger(base: 60, baseFree: 60, week: [60, 60, 60, 60, 60, 60, 60])
        let w = YourWeek.build(entries: entries, firstDay: date(-28), thisCycle: nil, baselineCycle: nil, thisSwitches: nil, baselineSwitches: nil, calendar: calendar)
        XCTAssertEqual(w.verdict, .same)
        entries[entries.count - 3] = entry(4, .leave, own: 10)
        entries[entries.count - 2] = entry(5, .leave, own: 10)
        let worse = YourWeek.build(entries: entries, firstDay: date(-28), thisCycle: nil, baselineCycle: nil, thisSwitches: nil, baselineSwitches: nil, calendar: calendar)
        XCTAssertEqual(worse.verdict, .worse)
        XCTAssertEqual(worse.headline, "Below your last 4 weeks.")
    }

    func testTodayInProgressIsNotJudgedAndAShortHistoryHasNoBaseline() {
        let entries = ledger(base: 60, baseFree: 60, week: [60, 60, 60, 60, 60, 60, 0])
        let week = YourWeek.build(entries: entries, firstDay: date(-28), thisCycle: nil, baselineCycle: nil, thisSwitches: nil, baselineSwitches: nil, calendar: calendar)
        XCTAssertEqual(week.verdict, .same, "Today at 0 min is open, not a loss")
        let fresh = YourWeek.build(entries: entries, firstDay: date(-3), thisCycle: nil, baselineCycle: nil, thisSwitches: nil, baselineSwitches: nil, calendar: calendar)
        XCTAssertEqual(fresh.verdict, .firstWeek, "3 days of history is not a baseline")
        XCTAssertNil(fresh.baseline)
        XCTAssertTrue(fresh.trends.allSatisfy { $0.direction == .unknown })
    }

    func testRatesAndSwitchesTrendsSayBetterWhenLower() {
        let this = WeekMeasures(days: 7, ownMinutes: 300, activeDays: 5, targetDays: 7, goalMetDays: 3, lostDays: 1,
                                switchesPerHour: 20, stretchRate: 0.3, medianReturnMinutes: 15)
        let base = WeekMeasures(days: 7, ownMinutes: 300, activeDays: 5, targetDays: 7, goalMetDays: 3, lostDays: 1,
                                switchesPerHour: 31, stretchRate: 0.48, medianReturnMinutes: 24)
        let trends = YourWeek.trends(this: this, base: base)
        XCTAssertEqual(trends.first { $0.id == "switches" }?.direction, .better)
        XCTAssertEqual(trends.first { $0.id == "stretch" }?.delta, "−18 pts")
        XCTAssertEqual(trends.first { $0.id == "stretch" }?.direction, .better)
        XCTAssertEqual(trends.first { $0.id == "return" }?.direction, .better)
        XCTAssertEqual(trends.first { $0.id == "own" }?.direction, .same)
    }

    func testMeasuresCountBlocksAndSwitches() {
        let cycle = CoachCycleStats(gaps: [10, 20, 30], onTimeGaps: [10], stretchedGaps: [20, 30], blocks: 10, stretchedBlocks: 4)
        let m = WeekMeasures.of([], cycle: cycle, switches: (count: 62, blockHours: 2))
        XCTAssertEqual(m.stretchRate, 0.4)
        XCTAssertEqual(m.medianReturnMinutes, 20)
        XCTAssertEqual(m.switchesPerHour, 31)
        XCTAssertNil(WeekMeasures.of([], cycle: nil, switches: (count: 5, blockHours: 0.5)).switchesPerHour, "Under an hour of blocks says nothing")
    }

    // MARK: Recommendations

    private func input(_ entries: [DayEntry], now: Date? = nil) -> LifeRecInput {
        LifeRecInput(now: now ?? date(6, 15), entries: entries, cycle: CoachCycleStats.compute([]), regularMinutes: 25, naturalLength: nil,
                     breaks: nil, windowFit: nil, appPull: nil, derailer: nil, targets: [:], goalMinutes: 150, freeDayHour: 10,
                     unplannedWeekend: [calendar.startOfDay(for: date(7)), calendar.startOfDay(for: date(8))],
                     todaySlot: date(6, 18), hasPlanToday: false, calendar: calendar)
    }

    func testWeekendPlanQuotesLostDaysAndPlansSaturdayAndSunday() {
        let entries = ledger(base: 90, baseFree: 0, week: [90, 90, 90, 90, 90, 90, 90])
        let rec = LifeRecommendations.weekendPlan(input(entries))
        XCTAssertNotNil(rec)
        XCTAssertEqual(rec?.actionTitle, "Plan Sat + Sun at 10:00")
        XCTAssertEqual(rec?.action, .planBlocks([date(7, 10), date(8, 10)]))
        XCTAssertTrue(rec?.evidence.contains("of your last") == true)
        var noWeekend = input(entries); noWeekend.unplannedWeekend = []
        XCTAssertNil(LifeRecommendations.weekendPlan(noWeekend), "Already planned: nothing to apply")
    }

    func testLeaveTargetAimsHigherThanTheGoalAndStopsOnceSet() {
        var entries = ledger(base: 90, baseFree: 90, week: [90, 90, 90, 90, 90, 90, 90])
        entries[entries.count - 2] = entry(5, .leave, own: 110, target: 150)
        entries[entries.count - 3] = entry(4, .leave, own: 110, target: 150)
        let rec = LifeRecommendations.leaveTarget(input(entries))
        XCTAssertEqual(rec?.action, .setTarget(.leave, 180))
        XCTAssertEqual(rec?.actionTitle, "Set leave to 3h")
        var set = input(entries); set.targets = [.leave: 200]
        XCTAssertNil(LifeRecommendations.leaveTarget(set))
    }

    func testTargetMissOffersATargetYouCanHit() {
        let entries = ledger(base: 0, baseFree: 30, week: [0, 0, 30, 30, 0, 0, 0])
        let rec = LifeRecommendations.targetMiss(input(entries))
        XCTAssertEqual(rec?.kind, .targetMiss)
        if case .setTarget(let type, let minutes)? = rec?.action {
            XCTAssertEqual(type, .weekend)
            XCTAssertEqual(minutes, 60, "Half of 120, rounded to 15")
        } else if rec?.action != .openGoals {
            XCTFail("Expected a target change")
        }
    }

    func testNeverMissTwiceNeedsAMissYesterdayAndNoPlanToday() {
        var entries = ledger(base: 60, baseFree: 60, week: [60, 60, 60, 60, 60, 0, 0])
        XCTAssertEqual(LifeRecommendations.neverMissTwice(input(entries))?.action, .planBlocks([date(6, 18)]))
        var planned = input(entries); planned.hasPlanToday = true
        XCTAssertNil(LifeRecommendations.neverMissTwice(planned))
        entries[entries.count - 2] = entry(5, .workday, own: 60)
        XCTAssertNil(LifeRecommendations.neverMissTwice(input(entries)))
    }

    func testLandOnTimeAndBreaksNeedEvidence() {
        var i = input([])
        i.cycle = CoachCycleStats(gaps: [], onTimeGaps: [20, 24, 30], stretchedGaps: [80, 86, 90], blocks: 20, stretchedBlocks: 10)
        XCTAssertNil(LifeRecommendations.landOnTime(i), "No natural length: nothing to apply")
        i.naturalLength = 35
        let land = LifeRecommendations.landOnTime(i)
        XCTAssertEqual(land?.action, .blockLength(35))
        XCTAssertEqual(land?.evidence, "50% of your blocks ran 5+ min over. The next block came 86 min later, against 24 after one that ended on time.")
        i.breaks = (actual: 21, suggested: 8, count: 12)
        XCTAssertEqual(LifeRecommendations.breakLanding(i)?.action, .breakLength(15))
        i.breaks = (actual: 9, suggested: 8, count: 12)
        XCTAssertNil(LifeRecommendations.breakLanding(i))
    }

    func testDerailerHourCountsItOrPlansTheHour() {
        var i = input([])
        i.derailer = (key: "youtube.com", name: "YouTube", minutes: 250, fromHour: 22, toHour: 25, isYourRule: false)
        let rec = LifeRecommendations.derailerHour(i)
        XCTAssertEqual(rec?.title, "YouTube around 22:00–01:00")
        XCTAssertEqual(rec?.action, .markPull(key: "youtube.com", name: "YouTube"))
        i.derailer?.isYourRule = true
        XCTAssertEqual(LifeRecommendations.derailerHour(i)?.action, .planBlocks([date(7, 22)]))
    }

    func testRankingShowsThreeAndRespectsAppliedAndNotNow() {
        let now = date(6, 15)
        let recs = (0..<5).map { n in
            LifeRecommendation(id: "r\(n)", kind: .windowsFit, title: "", evidence: "", impact: "", actionTitle: "", action: .useObservedWindows,
                               weight: 1 - Double(n) * 0.1, confidence: 1)
        }
        XCTAssertEqual(LifeRecommendations.ranked(recs, records: [:], now: now).map(\.id), ["r0", "r1", "r2"])
        let records = [
            "r0": LifeRecRecord(id: "r0", kindRaw: "windowsFit", title: "", appliedAt: now.addingTimeInterval(-86_400)),
            "r1": LifeRecRecord(id: "r1", kindRaw: "windowsFit", title: "", dismissedAt: now.addingTimeInterval(-86_400)),
        ]
        XCTAssertEqual(LifeRecommendations.ranked(recs, records: records, now: now).map(\.id), ["r2", "r3", "r4"])
    }

    func testComingWeekend() {
        XCTAssertEqual(LifeRecommendations.comingWeekend(now: date(6, 15), calendar: calendar), [calendar.startOfDay(for: date(7)), calendar.startOfDay(for: date(8))])
        XCTAssertEqual(LifeRecommendations.comingWeekend(now: date(7, 19), calendar: calendar), [calendar.startOfDay(for: date(8))], "Saturday evening: just Sunday")
        XCTAssertEqual(LifeRecommendations.comingWeekend(now: date(8, 9), calendar: calendar), [calendar.startOfDay(for: date(8))])
    }

    // MARK: Follow-up

    func testOutcomeAWeekLater() {
        let applied = date(-8, 12)
        var record = LifeRecRecord(id: "weekendPlan", kindRaw: "weekendPlan", title: "Plan your weekend", firstShownAt: applied, appliedAt: applied, baseline: 0.25)
        XCTAssertEqual(LifeRecMetric.outcome(record, current: 0.67, now: date(6, 12)), .worked("25% → 67%"))
        XCTAssertEqual(LifeRecMetric.outcome(record, current: 0.3, now: date(6, 12)), .didnt("25% → 30%"))
        XCTAssertEqual(LifeRecMetric.outcome(record, current: 0.67, now: date(-4, 12)), .tooEarly)
        record.kindRaw = "windowsFit"
        XCTAssertEqual(LifeRecMetric.outcome(record, current: nil, now: date(6, 12)), .applied)
        let shown = LifeRecRecord(id: "leaveTarget", kindRaw: "leaveTarget", title: "", firstShownAt: date(-8))
        XCTAssertEqual(LifeRecMetric.outcome(shown, current: nil, now: date(6)), .notTried)
        let target = LifeRecRecord(id: "targetMiss.weekend", kindRaw: "targetMiss.weekend", title: "", appliedAt: applied, baseline: 0.1)
        XCTAssertEqual(target.kind, .targetMiss)
    }

    func testMetricsFollowTheirDirection() {
        let entries = [entry(1, .weekend, own: 0), entry(2, .weekend, own: 60), entry(3, .workday, own: 0), entry(4, .workday, own: 0), entry(5, .workday, own: 60)]
        XCTAssertEqual(LifeRecMetric.value(kind: .weekendPlan, id: "weekendPlan", entries: entries, cycle: nil), 0.5)
        XCTAssertEqual(LifeRecMetric.value(kind: .neverMissTwice, id: "neverMissTwice", entries: entries, cycle: nil) ?? -1, 1.0 / 3.0, accuracy: 0.001, "Of 3 misses, only day 3 ran into a second")
        XCTAssertNil(LifeRecMetric.value(kind: .leaveTarget, id: "leaveTarget", entries: entries, cycle: nil))
    }

    func testStoreRecordsShownAppliedAndNotNow() {
        let defaults = cleanDefaults("liferecs")
        let store = LifeRecStore(defaults: defaults)
        let rec = LifeRecommendation(id: "weekendPlan", kind: .weekendPlan, title: "Plan your weekend", evidence: "", impact: "", actionTitle: "",
                                     action: .planBlocks([]), weight: 1, confidence: 1)
        store.markShown([rec], now: date(1))
        store.markShown([rec], now: date(3))
        XCTAssertEqual(store.load()["weekendPlan"]?.firstShownAt, date(1), "The first showing counts")
        store.markApplied(rec, baseline: 0.2, picked: true, now: date(4))
        XCTAssertEqual(store.load()["weekendPlan"]?.baseline, 0.2)
        XCTAssertEqual(store.load()["weekendPlan"]?.pickedAt, date(4))
        store.markShown([rec], now: date(30))
        XCTAssertNil(store.load()["weekendPlan"]?.appliedAt, "Shown again 26 days after it was applied: a new round")
        defaults.set(Data("garbage".utf8), forKey: LifeRecStore.key)
        XCTAssertTrue(store.load().isEmpty, "Unreadable data is ignored, never a crash")
    }
}

@MainActor
final class YourWeekStoreTests: XCTestCase {
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

    private func makeVM(defaults: UserDefaults) throws -> TimerViewModel {
        let context = container.mainContext
        let settings = try context.fetch(FetchDescriptor<AppSettings>()).first ?? { let s = AppSettings(); context.insert(s); return s }()
        let vm = TimerViewModel(defaults: defaults)
        vm.configureForEvidence(modelContext: context, settings: settings)
        return vm
    }

    func testApplyPlansBlocksSetsTargetsAndRecordsTheBaseline() throws {
        container = try ModelContainer(for: Self.schema, configurations: ModelConfiguration(schema: Self.schema, isStoredInMemoryOnly: true))
        let defaults = cleanDefaults("yourweek.vm")
        vm = try makeVM(defaults: defaults)
        let now = Date()
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now))!.addingTimeInterval(10 * 3600)
        let plan = LifeRecommendation(id: "weekendPlan", kind: .weekendPlan, title: "Plan your weekend", evidence: "", impact: "",
                                      actionTitle: "Plan", action: .planBlocks([tomorrow, now.addingTimeInterval(-3600)]), weight: 1, confidence: 1)
        vm.applyLifeRecommendation(plan, now: now)
        let plans = try container.mainContext.fetch(FetchDescriptor<PlannedBlock>())
        XCTAssertEqual(plans.map(\.startAt), [tomorrow], "A time already past is skipped")
        XCTAssertNotNil(LifeRecStore(defaults: defaults).load()["weekendPlan"]?.appliedAt)

        let leave = LifeRecommendation(id: "leaveTarget", kind: .leaveTarget, title: "", evidence: "", impact: "", actionTitle: "",
                                       action: .setTarget(.leave, 180), weight: 1, confidence: 1)
        let revision = vm.lifeRevision
        vm.applyLifeRecommendation(leave, now: now)
        XCTAssertEqual(vm.dayTargets()[.leave], 180)
        XCTAssertEqual(vm.lifeRevision, revision + 1)
        XCTAssertTrue(vm.lifeRecommendations(now: now).allSatisfy { $0.id != "leaveTarget" && $0.id != "weekendPlan" }, "Applied ones wait 3 weeks")
    }

    func testTheWeekBuildsOnAnEmptyStore() throws {
        container = try ModelContainer(for: Self.schema, configurations: ModelConfiguration(schema: Self.schema, isStoredInMemoryOnly: true))
        vm = try makeVM(defaults: cleanDefaults("yourweek.empty"))
        let week = vm.yourWeek()
        XCTAssertEqual(week.days.count, 7)
        XCTAssertEqual(week.verdict, .firstWeek)
        XCTAssertTrue(vm.lifeRecOutcomes().isEmpty)
        _ = vm.coachHelping()
    }

    /// FOCUSFLOW_LIVE_STORE_COPY=<copy>: prints the week, the recommendations and the coach line.
    func testYourWeekOnALiveStoreCopy() throws {
        guard let path = ProcessInfo.processInfo.environment["FOCUSFLOW_LIVE_STORE_COPY"] else { throw XCTSkip("Set FOCUSFLOW_LIVE_STORE_COPY") }
        container = try ModelContainer(for: Self.schema, configurations: ModelConfiguration(schema: Self.schema, url: URL(fileURLWithPath: path)))
        vm = try makeVM(defaults: cleanDefaults("yourweek.live"))
        let week = vm.yourWeek()
        print("WEEK \(week.span) | \(week.headline) | \(week.line)")
        for t in week.trends { print("WEEK TREND \(t.title): \(t.value) \(t.delta ?? "") \(t.direction.rawValue) (\(t.baseline ?? "-"))") }
        for d in week.days { print("WEEK DAY \(d.day) \(d.type.rawValue) \(d.verdict.rawValue) own=\(Int(d.ownMinutes)) target=\(d.targetMinutes)") }
        for r in vm.allLifeRecommendations() { print("WEEK REC [\(String(format: "%.2f", r.score))] \(r.title) | \(r.evidence) | \(r.actionTitle)") }
        for goal in vm.historyReaderActiveGoals() {
            let counts = GoalDataBuilder.todayCounts(goal, now: Date())
            for kr in goal.sortedKeyResults { print("GOAL TODAY \(goal.title) / \(kr.title): \(counts[kr.id]?.label ?? "-") (total \(Int(kr.done)) of \(Int(kr.target)))") }
        }
        for lever in vm.todayLevers() { print("GOAL LEVER \(lever.action) | block title: \(lever.intentTitle)") }
        let help = vm.coachHelping()
        print("WEEK HELP prompt=\(String(describing: help.promptLift)) return=\(String(describing: help.returnLift))")
    }
}

@MainActor
final class YourWeekReadPathTests: XCTestCase {
    /// Crash 2026-10-28 rule: Your week, its questions and the review only read while drawing.
    /// (Your week once reached `dailyPlanSuggestions`, which refreshes the coach model and saves
    /// calendar day labels.)
    func testYourWeekReadsNeverChangeObservedState() throws {
        let schema = FocusFlowSchema.schema
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        let settings = AppSettings(); container.mainContext.insert(settings)
        let project = Project(name: "Learning"); project.area = .personal; container.mainContext.insert(project)
        for i in 0..<12 {
            let s = FocusSession(type: .focus, duration: 1500, project: project)
            s.startedAt = Date().addingTimeInterval(-Double(i) * 50_000 - 3600); s.endedAt = s.startedAt.addingTimeInterval(2100); s.completed = true
            container.mainContext.insert(s)
        }
        try container.mainContext.save()
        let vm = TimerViewModel(defaults: cleanDefaults("yourweek.reads"))
        vm.systemIdleSecondsProvider = { 0 }
        vm.configureForEvidence(modelContext: container.mainContext, settings: settings)
        // With an override, any model refresh swaps it in (checked at the end): observation alone
        // can't see it, since the first write lands inside the tracked pass and later ones are equal.
        vm.availabilityModelOverride = CoachAvailabilityModel(
            sessions: (0..<6).map { CoachAvailabilityModel.Session(start: Date().addingTimeInterval(-Double($0 + 1) * 86_400), end: Date().addingTimeInterval(-Double($0 + 1) * 86_400 + 1800)) },
            activeDays: [])
        defer { AppUsageTracker.shared.stop() }
        let now = Date()

        final class Flag: @unchecked Sendable { var raised = false }
        let invalidated = Flag()
        withObservationTracking {
            _ = (vm.state, vm.availabilityModel, vm.lifeRevision, vm.dayTargetsRevision, vm.weeklyReviewRequested)
            _ = vm.yourWeek(now: now)
            _ = vm.lifeRecommendations(now: now)
            _ = vm.allLifeRecommendations(now: now)
            _ = vm.coachHelping(now: now)
            _ = vm.lifeRecOutcomes(now: now)
            _ = vm.planTodayQuestion(now: now)
            _ = vm.appRoleQuestion(now: now)
            _ = vm.dayTypeQuestion(now: now)
            _ = vm.weeklyPlanDays(now: now)
            _ = vm.weeklyPlanHours(now: now)
            _ = vm.dayTimeline(now, now: now)
            _ = vm.dayAccount(now, now: now)
            _ = vm.focusRhythm(now: now)
            _ = vm.gapReasonQuestion(now: now)
        } onChange: {
            invalidated.raised = true
        }
        // Past every cache window, so the caches refresh: a refresh must not count as a change.
        _ = vm.yourWeek(now: now.addingTimeInterval(120))
        _ = vm.coachHelping(now: now.addingTimeInterval(120))
        _ = vm.weeklyPlanHours(now: now.addingTimeInterval(4000))
        XCTAssertFalse(invalidated.raised, "A read made while drawing changed observed state")
        // A refresh would have swapped in the override; a page read must never refresh the model.
        XCTAssertEqual(vm.availabilityModel, .empty, "Your week refreshed the coach model while drawing")
    }
}
