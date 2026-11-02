import XCTest
import SwiftData
@testable import FocusFlow

/// Coach audit 2026-10-30, second part: block starts recorded apart from the sessions table,
/// declared own-work windows with one guaranteed prompt each and a cap of 3, a structured
/// coach journal with a multi-day log, and the evening "plan tomorrow" check-in.
@MainActor
final class CoachAuditEventsTests: XCTestCase {
    private var containers: [ModelContainer] = []
    private var defaultsSuite = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaultsSuite = "FocusFlowTests-\(UUID())"
        defaults = UserDefaults(suiteName: defaultsSuite)!
    }

    override func tearDown() {
        AppUsageTracker.shared.stop()
        defaults.removePersistentDomain(forName: defaultsSuite)
        containers.removeAll()
        super.tearDown()
    }

    private var today: Date { Calendar.current.startOfDay(for: Date()) }
    private func at(_ hour: Int, _ minute: Int = 0, dayOffset: Int = 0) -> Date {
        today.addingTimeInterval(TimeInterval(dayOffset * 86_400 + hour * 3600 + minute * 60))
    }

    private let morning = CoachOwnWorkWindow(startMinute: 7 * 60, endMinute: 9 * 60)
    private let evening = CoachOwnWorkWindow(startMinute: 20 * 60, endMinute: 22 * 60)

    // MARK: 1. Block starts outlive the 5-minute purge

    func testMergeKeepsShortStartsAndAddsSessionsWithoutARecord() {
        let id = UUID()
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let starts = [CoachDecisionReward.Block(start: t0, seconds: 120, plannedMinutes: 5, sessionID: id)]
        let sessions = [
            CoachDecisionReward.Block(start: t0, seconds: 125, plannedMinutes: 5, sessionID: id),
            CoachDecisionReward.Block(start: t0.addingTimeInterval(-3600), seconds: 1500, plannedMinutes: 25, sessionID: UUID()),
        ]
        let merged = CoachDecisionReward.merge(starts: starts, sessions: sessions)
        XCTAssertEqual(merged.count, 2, "A session with a start record is not counted twice")
        XCTAssertEqual(merged.last?.seconds, 120, "The start record wins")
        XCTAssertTrue(CoachDecisionReward.outcome(decidedAt: t0.addingTimeInterval(-60), blocks: merged).started)
    }

    func testAShortBlockKeepsItsStartAndStillCountsForThePromptThatAskedForIt() throws {
        let (vm, context) = try makeViewModel()
        vm.coachArmOverride = CoachArm(surface: .panel, style: .challenger)
        vm.evaluateIdleStarterIntervention(idleSeconds: 30 * 60, frontmostCategory: .neutral)
        let attemptID = try XCTUnwrap(vm.coachPanel?.attemptID)

        XCTAssertTrue(vm.performCoachPanelPrimary())
        vm.stop() // seconds later: under 5 minutes, so the session is purged
        XCTAssertTrue(try context.fetch(FetchDescriptor<FocusSession>()).isEmpty, "History still drops blocks under 5 minutes")

        let starts = try context.fetch(FetchDescriptor<BlockStartEvent>())
        XCTAssertEqual(starts.count, 1, "The start survives the purge")
        XCTAssertEqual(starts.first?.promptAttemptID, attemptID)
        XCTAssertNotNil(starts.first?.focusedSeconds, "Its seconds were written before the delete")

        let attempt = try XCTUnwrap(vm.coachEngine.store.attempt(id: attemptID))
        let later = attempt.deliveredAt.addingTimeInterval(61 * 60)
        let size = vm.sizeLearningObservations(now: later)
        XCTAssertEqual(size.count, 1)
        XCTAssertGreaterThanOrEqual(size.first?.reward ?? 0, 1, "A start within 20 minutes scores 1 even though the session is gone")

        // The same holds for the prompt learner once the attempt is a randomised decision.
        attempt.decisionRaw = CoachPromptPolicy.decisionKey
        attempt.treated = true
        attempt.propensity = 0.7
        attempt.featuresRaw = CoachPromptFeatures.encode([Double](repeating: 0, count: CoachPromptFeatures.count))
        XCTAssertEqual(vm.promptLearningObservations(now: later).first?.reward ?? 0, 1, accuracy: 0.01)
    }

    func testAStartOnYourOwnHasNoPrompt() throws {
        let (vm, context) = try makeViewModel()
        XCTAssertTrue(vm.startFocus())
        vm.abandonSession()
        let starts = try context.fetch(FetchDescriptor<BlockStartEvent>())
        XCTAssertEqual(starts.count, 1, "Even a discarded block was a start")
        XCTAssertNil(starts.first?.promptAttemptID)
        XCTAssertEqual(vm.coachJournal.recent.last { $0.kind == .started }?.code, .onYourOwn)
    }

    // MARK: 2. Declared own-work windows

    func testWindowsParseSortDropOverlapsAndRoundTrip() {
        let windows = CoachOwnWorkWindows.parse("1200-1320, 420-540,480-600,junk")
        XCTAssertEqual(windows, [morning, evening], "Sorted, the overlapping 08:00–10:00 dropped")
        XCTAssertEqual(CoachOwnWorkWindows.encode(windows), "420-540,1200-1320")
        XCTAssertNil(CoachOwnWorkWindows.encode([]))
        XCTAssertEqual(morning.label, "07:00–09:00")
        XCTAssertTrue(morning.contains(at(7)))
        XCTAssertFalse(morning.contains(at(9)), "The end is exclusive")
        XCTAssertEqual(CoachOwnWorkWindows.current([morning, evening], now: at(20, 30))?.start, at(20))
        XCTAssertNil(CoachOwnWorkWindows.current([morning, evening], now: at(12)))
    }

    func testRescuesGoOnScreenOnlyInsideADeclaredWindow() {
        XCTAssertTrue(CoachRescueWindowPolicy.allowsOnScreen(tier: .low, modelHasData: true, declaredWindowOpen: true))
        XCTAssertFalse(CoachRescueWindowPolicy.allowsOnScreen(tier: .high, modelHasData: true, declaredWindowOpen: false))
        XCTAssertTrue(CoachRescueWindowPolicy.allowsOnScreen(tier: .high, modelHasData: true), "No windows declared: the learned model decides")
    }

    func testOutsideDeclaredWindowsThereIsNoDecisionPoint() throws {
        let (vm, _) = try makeViewModel(windows: [morning, evening])
        vm.evaluateIdleStarterIntervention(idleSeconds: 60 * 60, frontmostCategory: .neutral, now: at(12))
        XCTAssertTrue(vm.coachEngine.store.attempts(deliveredSince: today).isEmpty, "Nothing logged, nothing shown")
        XCTAssertNil(vm.coachPanel)
        XCTAssertEqual(vm.lastIdleStarterSuppressionReason, .outsideOwnWorkWindow)
        XCTAssertEqual(vm.coachJournal.recent.last?.code, .outsideOwnWindow)
        XCTAssertFalse(vm.isInOwnWorkWindow(at(12)))

        vm.evaluateIdleStarterIntervention(idleSeconds: 60 * 60, frontmostCategory: .neutral, now: at(7, 30))
        XCTAssertEqual(vm.coachEngine.store.attempts(deliveredSince: today).filter { $0.decisionRaw == CoachPromptPolicy.decisionKey }.count, 1,
                       "Inside a window the coach decides (prompted or quiet, the moment is logged)")
    }

    private let youtube = TimerViewModel.DriftFrontmost(
        bundleIdentifier: "com.apple.Safari", appName: "Safari", browserHost: "youtube.com",
        displayName: "YouTube", category: .distracting
    )

    private func feedDrift(_ vm: TimerViewModel, minutes: Int, endingAt end: Date) {
        vm.settings?.coachCollectRawDomains = true
        if vm.coachArmOverride == nil { vm.coachArmOverride = CoachArm(surface: .panel, style: .challenger) }
        for minute in stride(from: minutes - 1, through: 0, by: -1) {
            vm.recordDriftSample(youtube, seconds: 60, now: end.addingTimeInterval(TimeInterval(-minute * 60)))
        }
    }

    func testRescuesOutsideDeclaredWindowsAreNoDecisionAndSayWhy() throws {
        let (vm, _) = try makeViewModel(windows: [morning])
        // Behind pace with an hour of learned window left: a drift episode is active at 14:00.
        let yesterday = at(13, 30, dayOffset: -1)
        vm.availabilityModelOverride = CoachAvailabilityModel(sessions: [.init(start: yesterday, end: yesterday.addingTimeInterval(1500))], activeDays: [])
        vm.refreshCoachModelsIfNeeded(force: true)
        feedDrift(vm, minutes: 12, endingAt: at(14))
        XCTAssertFalse(vm.evaluateRescueLoop(now: at(14)))
        XCTAssertEqual(vm.currentDrift?.isActive, true, "The drift is real; it just isn't a moment to interrupt")
        XCTAssertTrue(vm.coachEngine.store.attempts(deliveredSince: today).isEmpty)
        XCTAssertEqual(vm.coachJournal.recent.last?.code, .outsideOwnWindow)
    }

    func testRescueInsideAWindowShowsAndAmbientOrHeldRescuesAreJournaled() throws {
        let (vm, _) = try makeViewModel(windows: [morning])
        feedDrift(vm, minutes: 12, endingAt: at(8))
        XCTAssertTrue(vm.evaluateRescueLoop(now: at(8)))
        XCTAssertEqual(vm.coachPanel?.kind, .rescue)
        let shown = try XCTUnwrap(vm.coachJournal.recent.last)
        XCTAssertEqual(shown.code, .rescue)
        XCTAssertEqual(shown.attemptID, vm.coachPanel?.attemptID)
        XCTAssertEqual(shown.hook, vm.coachPanel?.message.hook)

        let (ambientVM, _) = try makeViewModel(windows: [morning])
        ambientVM.coachArmOverride = CoachArm(surface: .silent, style: nil)
        feedDrift(ambientVM, minutes: 12, endingAt: at(8))
        XCTAssertFalse(ambientVM.evaluateRescueLoop(now: at(8)))
        let ambient = try XCTUnwrap(ambientVM.coachJournal.recent.last)
        XCTAssertEqual(ambient.code, .rescueAmbient)
        XCTAssertNotNil(ambient.attemptID)

        let (heldVM, _) = try makeViewModel(windows: [morning])
        heldVM.settings?.coachQuietStartMinute = 0
        heldVM.settings?.coachQuietEndMinute = 24 * 60 - 1
        feedDrift(heldVM, minutes: 12, endingAt: at(8))
        XCTAssertFalse(heldVM.evaluateRescueLoop(now: at(8)))
        XCTAssertEqual(heldVM.coachJournal.recent.last?.code, .quietHours)
    }

    // MARK: 3. One guaranteed prompt per window, at most 3 a day

    func testCapIsThreeAndHoldsASlotForEachWindowStillToCome() {
        XCTAssertEqual(CoachOwnWorkWindows.cap(setting: 6, windows: [], now: at(10), guaranteed: false), 3)
        XCTAssertEqual(CoachOwnWorkWindows.cap(setting: 2, windows: [], now: at(10), guaranteed: false), 2)
        XCTAssertEqual(CoachOwnWorkWindows.cap(setting: 3, windows: [morning, evening], now: at(7, 30), guaranteed: false), 2, "One slot kept for tonight")
        XCTAssertEqual(CoachOwnWorkWindows.cap(setting: 3, windows: [morning, evening], now: at(7, 30), guaranteed: true), 3)
        XCTAssertEqual(CoachOwnWorkWindows.cap(setting: 3, windows: [morning, evening], now: at(20, 30), guaranteed: false), 3)
    }

    func testLastCallIsTheFinalHalfHour() {
        let window = morning.interval(on: at(8))
        XCTAssertFalse(CoachOwnWorkWindows.isLastCall(window, now: at(8, 29)))
        XCTAssertTrue(CoachOwnWorkWindows.isLastCall(window, now: at(8, 30)))
        XCTAssertFalse(CoachOwnWorkWindows.isLastCall(window, now: at(9)))
        let short = CoachOwnWorkWindow(startMinute: 7 * 60, endMinute: 7 * 60 + 40).interval(on: at(7))
        XCTAssertTrue(CoachOwnWorkWindows.isLastCall(short, now: at(7, 20)), "A 40-minute window: its last 20 minutes")
        XCTAssertFalse(CoachOwnWorkWindows.owesPrompt(window: window, now: at(8, 40), startedInWindow: true, promptsInWindow: 0, goalMet: false))
        XCTAssertFalse(CoachOwnWorkWindows.owesPrompt(window: window, now: at(8, 40), startedInWindow: false, promptsInWindow: 1, goalMet: false))
        XCTAssertFalse(CoachOwnWorkWindows.owesPrompt(window: window, now: at(8, 40), startedInWindow: false, promptsInWindow: 0, goalMet: true))
        XCTAssertTrue(CoachOwnWorkWindows.owesPrompt(window: window, now: at(8, 40), startedInWindow: false, promptsInWindow: 0, goalMet: false))
    }

    func testAWindowHeldQuietGetsItsGuaranteedPromptAtLastCall() throws {
        let (vm, _) = try makeViewModel(windows: [morning, evening])
        // The 30% control: the coach held back at 07:20.
        vm.coachArmOverride = CoachArm(surface: .silent, style: nil)
        vm.evaluateIdleStarterIntervention(idleSeconds: 30 * 60, frontmostCategory: .neutral, now: at(7, 20))
        XCTAssertNil(vm.coachPanel)
        vm.coachArmOverride = nil
        vm.testingResetIdleCooldown()

        XCTAssertFalse(vm.evaluateOwnWorkWindowPrompt(now: at(8, 10)), "Not before the last half hour")
        XCTAssertTrue(vm.evaluateOwnWorkWindowPrompt(now: at(8, 35)))
        let panel = try XCTUnwrap(vm.coachPanel)
        XCTAssertEqual(panel.kind, .startNudge)
        let attempt = try XCTUnwrap(vm.coachEngine.store.attempt(id: try XCTUnwrap(panel.attemptID)))
        XCTAssertEqual(attempt.decisionRaw, CoachPromptPolicy.guaranteedDecisionKey, "Kept out of the prompt learner's data")
        XCTAssertEqual(attempt.propensity, 1)
        let line = try XCTUnwrap(vm.coachJournal.recent.last { $0.kind == .shown })
        XCTAssertEqual(line.code, .guaranteed)
        XCTAssertEqual(line.attemptID, attempt.id)
        XCTAssertEqual(line.hook, panel.message.hook)

        vm.hideCoachPanel()
        vm.testingResetIdleCooldown()
        XCTAssertFalse(vm.evaluateOwnWorkWindowPrompt(now: at(8, 50)), "One per window")
    }

    func testNoGuaranteedPromptOnceABlockStartedInTheWindow() throws {
        let (vm, context) = try makeViewModel(windows: [morning])
        context.insert(BlockStartEvent(sessionID: UUID(), startedAt: at(7, 10), plannedMinutes: 5, projectID: nil, ownWorkAtStart: true))
        try context.save()
        XCTAssertFalse(vm.owesOwnWorkWindowPrompt(now: at(8, 40)), "A 5-minute start counts, even though its session is gone")
    }

    // MARK: 4. Structured journal and the multi-day log

    func testJournalLinesCarryStructureAndOldLinesStillLoad() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("coach-journal-\(UUID()).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        let legacy = #"{"at":"2026-10-20T08:00:00Z","kind":"quiet","text":"Quiet: Daily prompt cap reached."}"# + "\n"
        try Data(legacy.utf8).write(to: url)

        let journal = CoachJournal(fileURL: url)
        XCTAssertEqual(journal.recent.count, 1)
        XCTAssertNil(journal.recent.first?.code)
        let id = UUID()
        journal.record(.shown, "Start nudge", code: .prompted, attemptID: id, propensity: 0.7, hook: "Start 15m.", at: at(8))
        let reloaded = CoachJournal.load(from: url)
        XCTAssertEqual(reloaded.count, 2)
        XCTAssertEqual(reloaded.last, CoachJournal.Entry(at: at(8), kind: .shown, text: "Start nudge", code: .prompted, attemptID: id, propensity: 0.7, hook: "Start 15m."))
    }

    func testRepeatedQuietReasonsCollapseButEveryDecisionIsWritten() {
        let journal = CoachJournal(fileURL: nil)
        journal.record(.quiet, "Quiet: away.", code: .away, at: at(8))
        journal.record(.quiet, "Quiet: away.", code: .away, at: at(8, 1))
        XCTAssertEqual(journal.recent.count, 1)
        journal.record(.quiet, "Held back", code: .control, attemptID: UUID(), at: at(8, 2))
        journal.record(.quiet, "Held back", code: .control, attemptID: UUID(), at: at(8, 5))
        XCTAssertEqual(journal.recent.count, 3, "Each held-back decision is its own line")
    }

    func testSilentExitPathsAreJournaled() throws {
        let (vm, _) = try makeViewModel()
        vm.coachArmOverride = CoachArm(surface: .panel, style: .challenger)
        vm.evaluateIdleStarterIntervention(idleSeconds: 30 * 60, frontmostCategory: .neutral)
        XCTAssertEqual(vm.coachPanel?.kind, .startNudge)
        vm.hideCoachPanel()

        vm.evaluateIdleStarterIntervention(idleSeconds: 30 * 60, frontmostCategory: .neutral)
        XCTAssertEqual(vm.coachJournal.recent.last?.code, .cooldown)

        XCTAssertTrue(vm.evaluateDailyPlanInvite(now: Date()))
        vm.testingResetIdleCooldown()
        vm.evaluateIdleStarterIntervention(idleSeconds: 30 * 60, frontmostCategory: .neutral)
        XCTAssertEqual(vm.coachJournal.recent.last?.code, .stickyPanel)

        XCTAssertFalse(vm.handleArrival(now: Date()))
        XCTAssertEqual(vm.coachJournal.recent.last?.code, .stickyPanel, "The arrival guard says why it stayed quiet")
    }

    func testDaySummaryCountsMomentsReasonsStartsAndOwnWork() {
        let a = UUID(), b = UUID()
        let entries: [CoachJournal.Entry] = [
            .init(at: at(7, 10), kind: .quiet, text: "Held back", code: .control, attemptID: a, propensity: 0.7),
            .init(at: at(7, 40), kind: .shown, text: "Start nudge", code: .prompted, attemptID: b, propensity: 0.7, hook: "Start."),
            .init(at: at(7, 41), kind: .shown, text: "Counter-offer", code: .counterOffer, attemptID: b),
            .init(at: at(8, 0), kind: .quiet, text: "Quiet: cap", code: .dailyCap),
            .init(at: at(12, 0), kind: .quiet, text: "Quiet: outside", code: .outsideOwnWindow),
            .init(at: at(9, 0, dayOffset: -1), kind: .started, text: "Started 15m, 3m after the start nudge."),
            .init(at: at(10, 0, dayOffset: -1), kind: .started, text: "Started 5m on your own."),
        ]
        let starts = [CoachLogSummary.Start(at: at(7, 45), afterPrompt: true), CoachLogSummary.Start(at: at(10), afterPrompt: false)]
        let days = CoachLogSummary.days(
            entries: entries, starts: starts,
            ownWorkMinutes: { Calendar.current.isDate($0, inSameDayAs: self.today) ? 45 : 20 },
            goalMinutes: 120, now: at(13), count: 3
        )
        XCTAssertEqual(days.count, 3)
        let todayRow = days[0]
        XCTAssertEqual(todayRow.shown, 1, "A counter-offer answers the same moment")
        XCTAssertEqual(todayRow.heldBack, [.init(code: .control, count: 1), .init(code: .dailyCap, count: 1)].sorted { $0.code.rawValue < $1.code.rawValue })
        XCTAssertEqual(todayRow.decisionMoments, 3, "Outside your windows was not a moment")
        XCTAssertEqual(todayRow.startsAfterPrompt, 1)
        XCTAssertEqual(todayRow.startsOnYourOwn, 1)
        XCTAssertEqual(todayRow.ownWorkMinutes, 45)
        XCTAssertEqual(todayRow.goalMinutes, 120)
        let yesterday = days[1]
        XCTAssertEqual(yesterday.startsAfterPrompt, 1, "Before start records: read from the journal's start lines")
        XCTAssertEqual(yesterday.startsOnYourOwn, 1)
        XCTAssertEqual(CoachLogDayRow.momentsText(todayRow), "3 moments · 1 shown · 2 held back")
        XCTAssertEqual(CoachLogDayRow.startsText(todayRow), "1 after a prompt · 1 on your own")
    }

    func testCoachLogDaysReadsWithoutChangingObservedState() throws {
        let (vm, _) = try makeViewModel()
        _ = vm.coachLogDays(now: Date(), goalSamples: [])
        final class Flag: @unchecked Sendable { var raised = false }
        let invalidated = Flag()
        withObservationTracking {
            _ = vm.state
            _ = vm.coachLogDays(now: Date(), goalSamples: [])
        } onChange: {
            invalidated.raised = true
        }
        XCTAssertFalse(invalidated.raised)
    }

    // MARK: 5. Plan tomorrow

    func testPlanTomorrowAsksOnceAfterTheLastWindow() {
        var input = CoachPlanTomorrow.Input(
            now: at(21, 30), enabled: true, plannedTomorrow: 0, askedToday: false, sessionActive: false,
            quietHours: false, screenShare: false, panelShowing: false, userIdleSeconds: 5, lastWindowEndMinute: 22 * 60
        )
        XCTAssertFalse(CoachPlanTomorrow.shouldAsk(input), "Not while tonight's window is still open")
        input.now = at(22, 5)
        XCTAssertTrue(CoachPlanTomorrow.shouldAsk(input))
        input.askedToday = true
        XCTAssertFalse(CoachPlanTomorrow.shouldAsk(input))
        input.askedToday = false
        input.plannedTomorrow = 2
        XCTAssertFalse(CoachPlanTomorrow.shouldAsk(input), "Already planned")
        input.plannedTomorrow = 0
        input.lastWindowEndMinute = nil
        input.now = at(18, 30)
        XCTAssertFalse(CoachPlanTomorrow.shouldAsk(input), "Not before 19:00")
    }

    func testPlanTomorrowOffersYourWindowsElseMorningAndEvening() {
        let withWindows = CoachPlanTomorrow.slots(now: at(22), windows: [morning, evening], model: .empty, quietStartMinute: 30, quietEndMinute: 420)
        XCTAssertEqual(withWindows.map(\.start), [at(7, dayOffset: 1), at(20, dayOffset: 1)])
        XCTAssertEqual(withWindows.first?.caption, "Your window")
        let none = CoachPlanTomorrow.slots(now: at(22), windows: [], model: .empty, quietStartMinute: 30, quietEndMinute: 420)
        XCTAssertEqual(none.map(\.start), [at(7, 30, dayOffset: 1), at(21, dayOffset: 1)])
        let oneTaken = CoachPlanTomorrow.slots(
            now: at(22), windows: [morning, evening], model: .empty, quietStartMinute: 30, quietEndMinute: 420, planned: [at(7, dayOffset: 1)]
        )
        XCTAssertEqual(oneTaken.map(\.start), [at(20, dayOffset: 1)], "A planned time isn't offered again")
    }

    func testPlanTomorrowCheckInPlansTwoBlocksAndTheCueComesAtThatTime() throws {
        let (vm, _) = try makeViewModel(windows: [morning, evening])
        vm.coachArmOverride = nil
        XCTAssertTrue(vm.evaluatePlanTomorrowCheckIn(now: at(22, 10)))
        let panel = try XCTUnwrap(vm.coachPanel)
        XCTAssertEqual(panel.kind, .planTomorrow)
        XCTAssertEqual(panel.message.hook, "When are tomorrow's 2 blocks?")
        XCTAssertNil(panel.autoHideSeconds)
        XCTAssertEqual(panel.planSlots.map { $0.label() }, ["07:00", "20:00"])
        let attempt = try XCTUnwrap(vm.coachEngine.store.attempt(id: try XCTUnwrap(panel.attemptID)))
        XCTAssertFalse(CoachGuardrails.Delivery(attempt: attempt).countsTowardCap, "Asked for in Settings: not a start prompt")

        let first = try XCTUnwrap(vm.commitTomorrowSlot(panel.planSlots[0], now: at(22, 11)))
        XCTAssertEqual(first.startAt, at(7, dayOffset: 1))
        let second = try XCTUnwrap(vm.coachPanel)
        XCTAssertEqual(second.kind, .planTomorrow)
        XCTAssertEqual(second.message.hook, "07:00 is set. When's the second?")
        XCTAssertEqual(second.planSlots.map { $0.label() }, ["20:00"])
        XCTAssertNotNil(vm.commitTomorrowSlot(second.planSlots[0], now: at(22, 12)))
        XCTAssertEqual(vm.coachPanel?.kind, .notice)
        XCTAssertEqual(vm.coachPanel?.message.hook, "Tomorrow: 07:00 and 20:00.")
        XCTAssertEqual(vm.tomorrowPlans(now: at(22, 12)).count, 2)
        XCTAssertEqual(attempt.outcome, .improved)

        vm.hideCoachPanel()
        XCTAssertFalse(vm.evaluatePlanTomorrowCheckIn(now: at(22, 40)), "Once a night")
        // Tomorrow at 07:00 the existing planned-start cue shows up.
        XCTAssertTrue(vm.evaluatePlannedCue(now: at(7, 0, dayOffset: 1)))
        XCTAssertEqual(vm.coachPanel?.kind, .plannedStart)
        XCTAssertEqual(vm.coachPanel?.plannedBlockID, first.id)
    }

    func testNotTonightClosesTheCheckIn() throws {
        let (vm, _) = try makeViewModel()
        XCTAssertTrue(vm.evaluatePlanTomorrowCheckIn(now: at(21)))
        vm.dismissCoachInterventionWindow()
        XCTAssertNil(vm.coachPanel)
        XCTAssertTrue(vm.tomorrowPlans(now: at(21)).isEmpty)
        XCTAssertFalse(vm.evaluatePlanTomorrowCheckIn(now: at(21, 30)))
    }

    func testStartCardCountsTowardTheCapAndStaysInsideDeclaredWindows() throws {
        let (vm, _) = try makeViewModel(windows: [morning])
        XCTAssertFalse(vm.evaluateDailyPlanInvite(now: at(12)), "Outside your windows: no start card")
        XCTAssertTrue(vm.evaluateDailyPlanInvite(now: at(7, 30)))
        let attempt = try XCTUnwrap(vm.coachEngine.store.attempt(id: try XCTUnwrap(vm.coachPanel?.attemptID)))
        XCTAssertTrue(CoachGuardrails.Delivery(attempt: attempt).countsTowardCap, "The coach's own ask counts toward 3 a day")
    }

    // MARK: Helpers

    private func makeViewModel(windows: [CoachOwnWorkWindow] = []) throws -> (TimerViewModel, ModelContext) {
        let schema = Schema([
            Project.self, FocusSession.self, AppSettings.self, TimeSplit.self, BlockProfile.self,
            AppUsageRecord.self, AppUsageEntry.self, TaskIntent.self, CoachInterruption.self,
            InterventionAttempt.self, BreakLearningEvent.self, IdleDistractionItem.self, WeeklyPriority.self, PlannedBlock.self,
            ProjectGoal.self, GoalKeyResult.self, GoalProgressEntry.self, DailyTask.self, BlockStartEvent.self,
        ])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        containers.append(container)
        let vm = TimerViewModel(defaults: defaults)
        vm.configure(modelContext: container.mainContext)
        vm.calendarAvailabilityProvider = { _ in .unknown }
        vm.systemIdleSecondsProvider = { 0 }
        vm.coachExploreSizes = false
        let settings = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<AppSettings>()).first)
        settings.antiProcrastinationEnabled = true
        settings.coachIdleStarterEnabled = true
        settings.coachSuppressPopupsDuringScreenShare = false
        settings.coachQuietStartMinute = 0
        settings.coachQuietEndMinute = 0
        settings.coachStyle = .challenger
        settings.coachOwnWorkWindows = windows
        try container.mainContext.save()
        vm.availabilityModelOverride = .empty
        vm.refreshCoachModelsIfNeeded(force: true)
        defaults.set(WeeklyPriority.weekStart(for: Date()).timeIntervalSince1970, forKey: TimerViewModel.weeklyInviteDefaultsKey)
        return (vm, container.mainContext)
    }
}
