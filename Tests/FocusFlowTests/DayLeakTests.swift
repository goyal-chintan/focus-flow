import XCTest
import SwiftData
@testable import FocusFlow

/// 6 Nov 2026: where the day went, why, and how you sit.
final class DayLeakTests: XCTestCase {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return c
    }

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private func row(_ hour: Int, _ key: String, _ label: String, _ minutes: Int, inBlock: Bool = false) -> DayAccount.Row {
        DayAccount.Row(hourStart: at(6, hour), key: key, label: label, inBlock: inBlock, seconds: minutes * 60)
    }

    /// The live 6 Nov: blocks at 12:56 (22 min paused), 14:36, 18:09, 18:28; away most of 16–18.
    private func liveDay() -> DayAccount {
        let blocks = [
            DayAccount.Block(start: at(6, 12, 56), end: at(6, 13, 56), own: true, pausedSeconds: 22 * 60),
            DayAccount.Block(start: at(6, 14, 36), end: at(6, 15, 10), own: true),
            DayAccount.Block(start: at(6, 18, 9), end: at(6, 18, 23), own: true),
            DayAccount.Block(start: at(6, 18, 28), end: at(6, 18, 53), own: true),
        ]
        let rows = [row(16, "away", "Away", 30), row(16, "app:com.anthropic.claudefordesktop", "Claude", 6), row(16, "app:company.thebrowser.Browser", "Arc", 7),
                    row(17, "away", "Away", 50), row(17, "domain:youtube.com", "youtube.com", 6)]
        return DayAccount.build(day: at(6, 12), now: at(6, 20), rows: rows, blocks: blocks, breaks: [DateInterval(start: at(6, 15, 10), end: at(6, 15, 21))],
                                category: { key, label, _ in
                                    if key.contains("youtube") { return .pull }
                                    return SideWorkTools.isSide(key: key, label: label) ? .side : .other
                                }, reasons: [DayAccount.reasonKey(at(6, 15, 10), calendar: calendar): .family], calendar: calendar)
    }

    func testPausesAreBreaksNotFocus() {
        let day = liveDay()
        XCTAssertEqual(day.minutes[.own] ?? 0, 38 + 34 + 14 + 25, accuracy: 0.5, "The 22 paused minutes are not own work")
        XCTAssertEqual(day.minutes[.rest] ?? 0, 22 + 11, accuracy: 0.5)
    }

    func testGapsBetweenSittingsCarryWhatFilledThemAndYourReason() {
        let day = liveDay()
        let big = day.gaps.first { $0.start == at(6, 15, 10) }
        XCTAssertNotNil(big)
        XCTAssertEqual(big?.minutes ?? 0, 179, accuracy: 0.5)
        XCTAssertEqual(big?.dominant, .away, "Nothing recorded 15:10–16:00 plus 80 min away")
        XCTAssertEqual(big?.filled[.rest] ?? 0, 11, accuracy: 0.5, "The break session sits inside the gap")
        XCTAssertEqual(big?.filled[.side] ?? 0, 6, accuracy: 0.5)
        XCTAssertEqual(big?.reason, .family)
        XCTAssertEqual(day.gaps.first { $0.start == at(6, 13, 56) }?.minutes ?? 0, 40, accuracy: 0.5)
        XCTAssertNil(day.gaps.first { $0.start == at(6, 18, 23) }, "5 min is not a gap")
        XCTAssertEqual(day.gaps.last?.end, at(6, 20), "Today: the time since the last sitting counts until now")
        let total = (big?.filled.values.reduce(0, +)) ?? 0
        XCTAssertEqual(total, 179, accuracy: 0.5, "A gap's parts add up to its length")
    }

    func testFineTimeIsNotALeak() {
        let day = liveDay()
        let withoutReason = DayAccount(day: day.day, span: day.span, minutes: day.minutes,
                                       gaps: day.gaps.map { var g = $0; g.reason = nil; return g }, hasRollup: true)
        XCTAssertLessThan(day.leakMinutes, withoutReason.leakMinutes, "Family time is not counted against you")
    }

    func testSideWorkTools() {
        XCTAssertTrue(SideWorkTools.isSide(key: "app:com.todesktop.230313mzl4w4u92", label: "Cursor"))
        XCTAssertTrue(SideWorkTools.isSide(key: "app:com.anthropic.claudefordesktop", label: "Claude"))
        XCTAssertFalse(SideWorkTools.isSide(key: "domain:scaler.com", label: "scaler.com"))
        XCTAssertFalse(SideWorkTools.isSide(key: "app:md.obsidian", label: "Obsidian"))
    }

    func testReasonStoreRoundTripsToTheMinute() {
        let defaults = cleanDefaults("gapreasons")
        let store = GapReasonStore(defaults: defaults)
        let start = Date().addingTimeInterval(-3600.7)
        store.set(.tired, for: start)
        XCTAssertEqual(store.all()[DayAccount.reasonKey(start)], .tired)
        store.set(nil, for: start)
        XCTAssertTrue(store.all().isEmpty)
        XCTAssertTrue(GapReason.family.isFine)
        XCTAssertFalse(GapReason.procrastinating.isFine)
    }

    // MARK: Rhythm

    private func block(_ day: Int, _ h: Int, _ m: Int, minutes: Double) -> FocusRhythm.Block {
        FocusRhythm.Block(start: at(day, h, m), end: at(day, h, m).addingTimeInterval(minutes * 60), focusedMinutes: minutes)
    }

    private func entry(_ day: Int, own: Double, target: Int = 120) -> DayEntry {
        DayEntry(day: calendar.startOfDay(for: at(day, 12)), classification: DayClassification(type: .workday, source: .inferred, confidence: 0.9, reason: ""),
                 planned: false, ownMinutes: own, officeMinutes: 0, callMinutes: nil, awayMinutes: nil, derailMinutes: 0, targetMinutes: target,
                 verdict: DayVerdict.of(planned: false, ownMinutes: own, targetMinutes: target, isPast: true))
    }

    func testSittingsChainBlocksAndGoodDaysSitLonger() {
        // Good days (1, 2): two 50-min blocks chained. Other days (3–6): single 25s, 2 h apart.
        var blocks = [block(1, 10, 0, minutes: 50), block(1, 11, 0, minutes: 50), block(2, 10, 0, minutes: 50), block(2, 11, 0, minutes: 50)]
        for d in 3...6 { blocks += [block(d, 10, 0, minutes: 25), block(d, 12, 30, minutes: 25), block(d, 15, 0, minutes: 25)] }
        let ledger = [entry(1, own: 130), entry(2, own: 125)] + (3...6).map { entry($0, own: 75) }
        let r = FocusRhythm.compute(blocks: blocks, ledger: ledger, gaps: [], calendar: calendar)
        XCTAssertEqual(r.sittings.count, 2 + 12, "10:50 → 11:00 is one sitting")
        XCTAssertEqual(r.goodDays, 2)
        XCTAssertEqual(r.goodDayLongest ?? 0, 100, accuracy: 0.01)
        XCTAssertEqual(r.otherDayLongest ?? 0, 25, accuracy: 0.01)
        XCTAssertEqual(r.returnAfterShort ?? 0, 125, accuracy: 0.01)
        let ids = r.findings.map(\.id)
        XCTAssertTrue(ids.contains("goodDays"))
        XCTAssertTrue(ids.contains("restart"), "125 min after a 25-min sitting: the restart, not tiredness")
    }

    func testSlowerReturnsAfterLongSittingsReadAsFatigue() {
        var blocks: [FocusRhythm.Block] = []
        for d in 1...4 { blocks += [block(d, 9, 0, minutes: 60), block(d, 13, 0, minutes: 20), block(d, 13, 40, minutes: 20)] }
        // After the 60-min sitting: 180 min. After the 20-min one: 20 → chained (< 20? 13:20 → 13:40 = 20 min, not chained).
        let r = FocusRhythm.compute(blocks: blocks, ledger: [], gaps: [], calendar: calendar)
        XCTAssertEqual(r.returnAfterLong ?? 0, 180, accuracy: 0.01)
        XCTAssertEqual(r.returnAfterShort ?? 0, 20, accuracy: 0.01)
        XCTAssertTrue(r.findings.map(\.id).contains("fatigue"))
    }

    func testReasonFindingsAndRules() {
        let gap: (GapReason?, Double) -> DayAccount.Gap = { reason, minutes in
            DayAccount.Gap(start: Date(timeIntervalSince1970: minutes), end: Date(timeIntervalSince1970: minutes * 61), filled: [:], reason: reason)
        }
        let gaps = [gap(.tired, 60), gap(.tired, 70), gap(.tired, 80), gap(.procrastinating, 90), gap(.procrastinating, 100), gap(.family, 110), gap(nil, 120), gap(nil, 130)]
        let r = FocusRhythm.compute(blocks: [], ledger: [], gaps: gaps, calendar: calendar)
        XCTAssertEqual(r.reasons[.tired]?.count, 3)
        XCTAssertEqual(r.unlabeledGaps, 2)
        XCTAssertTrue(r.findings.contains { $0.id == "unlabeled" })
        var input = LifeRecInput(now: at(6, 15), entries: [], cycle: CoachCycleStats.compute([]), regularMinutes: 25, naturalLength: nil,
                                 breaks: nil, windowFit: nil, appPull: nil, derailer: nil, targets: [:], goalMinutes: 150, freeDayHour: 10,
                                 unplannedWeekend: [], todaySlot: at(6, 18), hasPlanToday: false, calendar: calendar)
        input.rhythm = r
        XCTAssertEqual(LifeRecommendations.fatigueBreak(input)?.action, .longBreak(minutes: 20, after: 2))
        XCTAssertEqual(LifeRecommendations.procrastination(input)?.action, .planBlocks([at(6, 18)]))
        input.sideMinutes14 = 600; input.ownMinutes14 = 900
        XCTAssertEqual(LifeRecommendations.sideWorkFirst(input)?.kind, .sideWorkFirst)
        input.ownMinutes14 = 1500
        XCTAssertNil(LifeRecommendations.sideWorkFirst(input), "Side work under half your own work is fine")
    }

    func testSessionShapeNeedsShortSittingsAndAReason() {
        var blocks = [block(1, 10, 0, minutes: 50), block(1, 11, 0, minutes: 50), block(2, 10, 0, minutes: 50), block(2, 11, 0, minutes: 50)]
        for d in 3...6 { blocks += [block(d, 10, 0, minutes: 25), block(d, 12, 30, minutes: 25), block(d, 15, 0, minutes: 25)] }
        let ledger = [entry(1, own: 130), entry(2, own: 125)] + (3...6).map { entry($0, own: 75) }
        var input = LifeRecInput(now: at(6, 15), entries: [], cycle: CoachCycleStats.compute([]), regularMinutes: 25, naturalLength: nil,
                                 breaks: nil, windowFit: nil, appPull: nil, derailer: nil, targets: [:], goalMinutes: 150, freeDayHour: 10,
                                 unplannedWeekend: [], todaySlot: nil, hasPlanToday: false, calendar: calendar)
        input.rhythm = FocusRhythm.compute(blocks: blocks, ledger: ledger, gaps: [], calendar: calendar)
        let rec = LifeRecommendations.sessionShape(input)
        XCTAssertEqual(rec?.action, .blockLength(50))
        XCTAssertTrue(rec?.evidence.contains("Days you met your target had a 1h 40m sitting; the rest, 25m.") == true, rec?.evidence ?? "")
        input.regularMinutes = 50
        XCTAssertNil(LifeRecommendations.sessionShape(input), "Already 50")
    }
}

@MainActor
final class DayLeakStoreTests: XCTestCase {
    func testTheGapQuestionAsksAboutARecentLongGapAndStoresTheAnswer() throws {
        let schema = FocusFlowSchema.schema
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        let settings = AppSettings(); container.mainContext.insert(settings)
        let now = Calendar.current.date(bySettingHour: 18, minute: 30, second: 0, of: Date())!
        for (start, end) in [(-300, -270), (-120, -95)] {
            let s = FocusSession(type: .focus, duration: 1500, project: nil)
            s.startedAt = now.addingTimeInterval(Double(start) * 60); s.endedAt = now.addingTimeInterval(Double(end) * 60); s.completed = true
            container.mainContext.insert(s)
        }
        try container.mainContext.save()
        let vm = TimerViewModel(defaults: cleanDefaults("gapq"))
        vm.configureForEvidence(modelContext: container.mainContext, settings: settings)
        defer { AppUsageTracker.shared.stop() }

        guard case .gapReason(let start, let end, _)? = vm.gapReasonQuestion(now: now) else { return XCTFail("Expected a gap question") }
        XCTAssertEqual(end.timeIntervalSince(start) / 60, 150, accuracy: 1, "270 min ago to 120 min ago")
        let revision = vm.lifeRevision
        vm.presentCoachQuestion(.gapReason(start: start, end: end, summary: ""), now: now)
        vm.answerCoachQuestion(CoachQuestionChoice(id: GapReason.tired.rawValue, title: "Tired"), now: now)
        XCTAssertGreaterThan(vm.lifeRevision, revision)
        XCTAssertEqual(vm.dayAccount(now, now: now).gaps.first { $0.start == start }?.reason, .tired)
        XCTAssertNil(vm.gapReasonQuestion(now: now), "Answered: no second ask")
        XCTAssertEqual(vm.focusRhythm(now: now).reasons[.tired]?.count, 1)
    }
}
