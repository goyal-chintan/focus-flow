import XCTest
import SwiftData
@testable import FocusFlow

/// Coach v8 phase 1 (docs/plans/2026-11-06-coach-v8-life-coach.md): see the day.
final class DayLedgerTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        c.locale = Locale(identifier: "en_IN")
        return c
    }()

    private func date(_ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    // MARK: Day types

    func testSaturdayAndSundayAreTheWeekendEvenUnderEnIN() {
        XCTAssertTrue(DayType.isWeekend(date(7), calendar: calendar), "Saturday")
        XCTAssertTrue(DayType.isWeekend(date(8), calendar: calendar), "Sunday")
        XCTAssertFalse(DayType.isWeekend(date(6), calendar: calendar), "Friday")
        XCTAssertFalse(calendar.isDateInWeekend(date(7)), "en_IN alone would call Saturday a weekday")
    }

    private func signals(_ day: Int, office: Double, active: Double, label: DayType? = nil, mark: CalendarDayMark? = nil) -> DaySignals {
        DaySignals(day: date(day), userLabel: label, calendarMark: mark, officeMinutes: office, activeMinutes: active)
    }

    func testAQuietWeekdayWithActivityIsLikelyLeave() {
        let c = DayClassifier.classify(signals(4, office: 0, active: 300), now: date(10, 12), calendar: calendar)
        XCTAssertEqual(c.type, .leave)
        XCTAssertLessThan(c.confidence, DayClassification.askBelow, "Likely, so the coach asks")
    }

    func testOfficeActivityMakesAWorkday() {
        XCTAssertEqual(DayClassifier.classify(signals(3, office: 246, active: 500), now: date(10), calendar: calendar).type, .workday)
    }

    func testTodayBefore13IsTooEarlyToCallLeave() {
        let c = DayClassifier.classify(signals(6, office: 0, active: 120), now: date(6, 11), calendar: calendar)
        XCTAssertEqual(c.type, .workday)
        XCTAssertEqual(c.reason, "Too early to tell.")
        XCTAssertEqual(DayClassifier.classify(signals(6, office: 0, active: 120), now: date(6, 15), calendar: calendar).type, .leave)
    }

    func testNoActivityIsNotCalledLeave() {
        XCTAssertEqual(DayClassifier.classify(signals(2, office: 0, active: 5), now: date(10), calendar: calendar).type, .workday)
    }

    func testUserAndCalendarLabelsWin() {
        XCTAssertEqual(DayClassifier.classify(signals(3, office: 300, active: 400, label: .sick), now: date(10), calendar: calendar).type, .sick)
        let ooo = DayClassifier.classify(signals(3, office: 300, active: 400, mark: .leave), now: date(10), calendar: calendar)
        XCTAssertEqual(ooo.type, .leave)
        XCTAssertEqual(ooo.source, .calendar)
        XCTAssertEqual(DayClassifier.classify(signals(3, office: 0, active: 200, mark: .holiday), now: date(10), calendar: calendar).type, .holiday)
        XCTAssertEqual(DayClassifier.classify(signals(3, office: 200, active: 300, mark: .holiday), now: date(10), calendar: calendar).type, .workday,
                       "A public holiday you worked through is a workday")
    }

    func testCalendarMarks() {
        XCTAssertEqual(CalendarDayMark.mark(title: "Focus", isAllDay: false, outOfOffice: true, coversHours: 9, holidayCalendar: false), .leave)
        XCTAssertNil(CalendarDayMark.mark(title: "Dentist", isAllDay: false, outOfOffice: true, coversHours: 1, holidayCalendar: false))
        XCTAssertEqual(CalendarDayMark.mark(title: "Chintan on leave", isAllDay: true, outOfOffice: false, coversHours: 24, holidayCalendar: false), .leave)
        XCTAssertEqual(CalendarDayMark.mark(title: "Diwali", isAllDay: true, outOfOffice: false, coversHours: 24, holidayCalendar: true), .holiday)
        XCTAssertNil(CalendarDayMark.mark(title: "Mom's birthday", isAllDay: true, outOfOffice: false, coversHours: 24, holidayCalendar: false))
    }

    // MARK: Verdicts

    func testThePlanTimesOutcomeGrid() {
        XCTAssertEqual(DayVerdict.of(planned: true, ownMinutes: 100, targetMinutes: 120, isPast: true), .plannedDone)
        XCTAssertEqual(DayVerdict.of(planned: true, ownMinutes: 10, targetMinutes: 120, isPast: true), .plannedMissed)
        XCTAssertEqual(DayVerdict.of(planned: false, ownMinutes: 90, targetMinutes: 120, isPast: true), .unplannedDid)
        XCTAssertEqual(DayVerdict.of(planned: false, ownMinutes: 0, targetMinutes: 120, isPast: true), .unplannedLost)
        XCTAssertEqual(DayVerdict.of(planned: false, ownMinutes: 0, targetMinutes: 120, isPast: false), .open, "Today is not lost yet")
        XCTAssertEqual(DayVerdict.of(planned: false, ownMinutes: 0, targetMinutes: 0, isPast: true), .rest, "A sick day is rest")
    }

    func testSummaryNamesUnplannedDaysOff() {
        func entry(_ day: Int, _ type: DayType, planned: Bool, own: Double) -> DayEntry {
            let target = type.defaultTargetMinutes
            return DayEntry(day: date(day), classification: DayClassification(type: type, source: .inferred, confidence: 0.9, reason: ""),
                            planned: planned, ownMinutes: own, officeMinutes: 0, callMinutes: nil, awayMinutes: nil, derailMinutes: 0,
                            targetMinutes: target, verdict: DayVerdict.of(planned: planned, ownMinutes: own, targetMinutes: target, isPast: true))
        }
        let days = [entry(1, .weekend, planned: false, own: 0), entry(2, .workday, planned: false, own: 60), entry(3, .workday, planned: false, own: 70),
                    entry(4, .leave, planned: false, own: 66), entry(5, .leave, planned: true, own: 191), entry(7, .weekend, planned: false, own: 0)]
        XCTAssertEqual(DayLedgerSummary.sentence(days),
                       "Last 6 days: 2 workdays, 2 leave days, 2 weekend days. Of 4 days off, 1 had a plan and 3 went unplanned with little own work.")
    }

    // MARK: Hourly rollup

    func testActivityPriority() {
        XCTAssertEqual(ActivityRollup.activity(frontmostBundleID: "com.tinyspeck.slackmacgap", frontmostName: "Slack", domain: nil, idleSeconds: 900, inCall: true), .call)
        XCTAssertEqual(ActivityRollup.activity(frontmostBundleID: "com.tinyspeck.slackmacgap", frontmostName: "Slack", domain: nil, idleSeconds: 900, inCall: false), .away)
        XCTAssertEqual(ActivityRollup.activity(frontmostBundleID: "company.thebrowser.Browser", frontmostName: "Arc", domain: "scaler.com", idleSeconds: 3, inCall: false), .domain(host: "scaler.com"),
                       "A domain replaces its browser, so browser time is not counted twice")
    }

    func testSleepGapsGoToAwayAndHoursSplit() {
        var rollup = ActivityRollup()
        rollup.record(.app(bundleID: "md.obsidian", name: "Obsidian"), seconds: 600, now: date(5, 10, 0, ), projectID: nil, inBlock: false, calendar: calendar)
        let rows = rollup.drain()
        let obsidian = rows.filter { $0.key.key == "app:md.obsidian" }.map(\.value.seconds).reduce(0, +)
        let away = rows.filter { $0.key.key == "away" }.map(\.value.seconds).reduce(0, +)
        XCTAssertEqual(obsidian, ActivityRollup.maxCreditedSecondsPerTick)
        XCTAssertEqual(away, 600 - ActivityRollup.maxCreditedSecondsPerTick)
        XCTAssertEqual(Set(rows.keys.map(\.hourStart)), [date(5, 9)], "Ends at 10:00 sharp: all of it is 9–10")

        var straddle = ActivityRollup()
        straddle.record(.app(bundleID: "md.obsidian", name: "Obsidian"), seconds: 20, now: date(5, 10, 0).addingTimeInterval(8), projectID: nil, inBlock: false, calendar: calendar)
        let split = straddle.drain()
        XCTAssertEqual(split[.init(hourStart: date(5, 10), key: "app:md.obsidian", projectID: nil, inBlock: false)]?.seconds, 8)
        XCTAssertEqual(split[.init(hourStart: date(5, 9), key: "app:md.obsidian", projectID: nil, inBlock: false)]?.seconds, 12)
    }

    func testSwitchesCountMovesBetweenAppsNotComingBack() {
        var rollup = ActivityRollup()
        let t = date(5, 11, 30)
        rollup.record(.app(bundleID: "a", name: "A"), seconds: 5, now: t, projectID: nil, inBlock: true, calendar: calendar)
        rollup.record(.domain(host: "x.com"), seconds: 5, now: t.addingTimeInterval(5), projectID: nil, inBlock: true, calendar: calendar)
        rollup.record(.away, seconds: 5, now: t.addingTimeInterval(10), projectID: nil, inBlock: true, calendar: calendar)
        rollup.record(.app(bundleID: "a", name: "A"), seconds: 5, now: t.addingTimeInterval(15), projectID: nil, inBlock: true, calendar: calendar)
        let rows = rollup.drain()
        XCTAssertEqual(rows.values.map(\.switches).reduce(0, +), 1, "Only A → x.com; returning from away is not a switch")
    }

    func testCallRule() {
        XCTAssertTrue(CallRule.inCall(cameraInUse: true, micInUse: false, runningBundleIDs: [], frontmostDomain: nil))
        XCTAssertTrue(CallRule.inCall(cameraInUse: false, micInUse: true, runningBundleIDs: ["us.zoom.xos"], frontmostDomain: nil))
        XCTAssertTrue(CallRule.inCall(cameraInUse: false, micInUse: true, runningBundleIDs: [], frontmostDomain: "meet.google.com"))
        XCTAssertFalse(CallRule.inCall(cameraInUse: false, micInUse: true, runningBundleIDs: ["com.tinyspeck.slackmacgap", "com.prakashjoshipax.VoiceInk"], frontmostDomain: nil),
                       "Dictation with Slack open is not a call")
    }
}

/// The ledger on an in-memory store, and (opt-in) on a copy of the live store.
@MainActor
final class DayLedgerStoreTests: XCTestCase {
    private var container: ModelContainer!
    private var vm: TimerViewModel!

    private static let schema = Schema([
        Project.self, FocusSession.self, AppSettings.self, TimeSplit.self, BlockProfile.self, AppUsageRecord.self, AppUsageEntry.self,
        TaskIntent.self, CoachInterruption.self, InterventionAttempt.self, BreakLearningEvent.self, IdleDistractionItem.self,
        WeeklyPriority.self, PlannedBlock.self, ProjectGoal.self, GoalKeyResult.self, GoalProgressEntry.self, DailyTask.self,
        BlockStartEvent.self, ActivityHour.self, DayLabel.self,
    ])

    override func tearDown() async throws {
        AppUsageTracker.shared.stop()
        vm = nil; container = nil
        try await super.tearDown()
    }

    private func makeVM(_ container: ModelContainer) throws -> TimerViewModel {
        let context = container.mainContext
        let settings = try context.fetch(FetchDescriptor<AppSettings>()).first ?? { let s = AppSettings(); context.insert(s); return s }()
        let vm = TimerViewModel()
        vm.configureForEvidence(modelContext: context, settings: settings)
        return vm
    }

    func testAQuietWeekdayIsLeaveAndTheAnswerSticks() throws {
        container = try ModelContainer(for: Self.schema, configurations: ModelConfiguration(schema: Self.schema, isStoredInMemoryOnly: true))
        let context = container.mainContext
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        // The last weekday before today, at 15:00, so it is a past, decided day.
        var day = cal.date(byAdding: .day, value: -1, to: today)!
        while DayType.isWeekend(day) { day = cal.date(byAdding: .day, value: -1, to: day)! }
        context.insert(AppUsageEntry(date: day, appName: "Obsidian", bundleIdentifier: "md.obsidian", duringFocusSeconds: 3600, outsideFocusSeconds: 3600))
        context.insert(AppUsageEntry(date: day, appName: "Slack", bundleIdentifier: "com.tinyspeck.slackmacgap", duringFocusSeconds: 0, outsideFocusSeconds: 300))
        try context.save()
        vm = try makeVM(container)

        let days = cal.dateComponents([.day], from: day, to: today).day! + 1
        let entry = try XCTUnwrap(vm.dayLedger(days: days).first)
        XCTAssertEqual(entry.day, day)
        XCTAssertEqual(entry.type, .leave)
        XCTAssertEqual(entry.officeMinutes, 5, accuracy: 0.01)

        vm.setDayType(day, type: .workday)
        let relabelled = try XCTUnwrap(vm.dayLedger(days: days).first)
        XCTAssertEqual(relabelled.type, .workday)
        XCTAssertEqual(relabelled.classification.source, .user)
    }

    /// Insights reads the ledger and the day question while drawing: no observed writes.
    func testLedgerReadsWithoutChangingObservedState() throws {
        container = try ModelContainer(for: Self.schema, configurations: ModelConfiguration(schema: Self.schema, isStoredInMemoryOnly: true))
        vm = try makeVM(container)
        _ = vm.dayLedger(days: 14)
        final class Flag: @unchecked Sendable { var raised = false }
        let invalidated = Flag()
        withObservationTracking {
            _ = vm.state
            _ = vm.dayLedger(days: 14)
            _ = vm.dayTypeQuestion()
        } onChange: {
            invalidated.raised = true
        }
        XCTAssertFalse(invalidated.raised)
    }

    /// FOCUSFLOW_LIVE_STORE_COPY=<path to a COPY of FocusFlow.store>: prints the ledger for the
    /// last 21 days and checks the leave days seen in the data on 6 Nov 2026.
    func testLedgerOnALiveStoreCopy() throws {
        guard let path = ProcessInfo.processInfo.environment["FOCUSFLOW_LIVE_STORE_COPY"] else { throw XCTSkip("Set FOCUSFLOW_LIVE_STORE_COPY") }
        container = try ModelContainer(for: Self.schema, configurations: ModelConfiguration(schema: Self.schema, url: URL(fileURLWithPath: path)))
        vm = try makeVM(container)
        let f = DateFormatter(); f.dateFormat = "EEE dd MMM"
        let ledger = vm.dayLedger(days: 21)
        for e in ledger {
            print(String(format: "LEDGER %@  %-8@ %.2f  own %4.0f  office %4.0f  planned %@  %@  — %@",
                         f.string(from: e.day), e.type.rawValue, e.classification.confidence, e.ownMinutes, e.officeMinutes,
                         e.planned ? "y" : "n", e.verdict.title, e.classification.reason))
        }
        if let summary = DayLedgerSummary.sentence(ledger) { print("LEDGER SUMMARY \(summary)") }
        let byDay = Dictionary(uniqueKeysWithValues: ledger.map { (f.string(from: $0.day), $0.type) })
        for leave in ["Wed 04 Nov", "Thu 05 Nov"] where byDay[leave] != nil {
            XCTAssertEqual(byDay[leave], .leave, leave)
        }
    }
}
