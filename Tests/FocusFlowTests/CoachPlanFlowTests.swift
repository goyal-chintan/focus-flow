import XCTest
import SwiftData
@testable import FocusFlow

/// Coach v3 end to end on a SwiftData store: the plan card, committing a time, the on-screen
/// cue at that time, starting from it, pushing, skipping and the never-replaced sticky panel.
@MainActor
final class CoachPlanFlowTests: XCTestCase {
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
    private func at(_ hour: Int, _ minute: Int = 0) -> Date { today.addingTimeInterval(TimeInterval(hour * 3600 + minute * 60)) }

    private func plans(_ vm: TimerViewModel) -> [PlannedBlock] {
        vm.plannedBlocks(from: today.addingTimeInterval(-86_400), to: today.addingTimeInterval(2 * 86_400))
    }

    // MARK: Plan card

    func testPlanCardShowsOnceAtABreakpointAndAChipCommitsAPlan() throws {
        let vm = try makeViewModel()
        let now = at(9, 40)
        XCTAssertTrue(vm.evaluateDailyPlanInvite(now: now))
        let card = try XCTUnwrap(vm.coachPanel)
        XCTAssertEqual(card.kind, .dailyPlan)
        XCTAssertNil(card.autoHideSeconds, "Stays until answered")
        XCTAssertFalse(card.planSlots.isEmpty)
        XCTAssertNotNil(card.message.motivation, "Challenger card carries a quote")
        let attempt = try XCTUnwrap(vm.coachEngine.store.attempt(id: try XCTUnwrap(card.attemptID)))
        XCTAssertEqual(attempt.contextKey, CoachPlannedCue.inviteContextKey)

        let slot = card.planSlots[0]
        let block = try XCTUnwrap(vm.commitDailyPlan(slot, now: now))
        XCTAssertEqual(block.startAt, slot.start)
        XCTAssertEqual(block.minutes, 15, "v4: a plan is the ladder's size (15 with no history), not 50")
        XCTAssertEqual(vm.coachPanel?.kind, .notice)
        XCTAssertEqual(attempt.outcome, .improved)
        XCTAssertTrue(vm.hasPlanForToday(now: now))

        vm.hideCoachPanel()
        XCTAssertFalse(vm.evaluateDailyPlanInvite(now: now.addingTimeInterval(3 * 3600)), "Planned: no more cards today")
    }

    func testCloseOnThePlanCardMeansLaterAndNotTodayIsRespected() throws {
        let vm = try makeViewModel()
        XCTAssertTrue(vm.evaluateDailyPlanInvite(now: at(9)))
        vm.dismissCoachInterventionWindow()
        XCTAssertNil(vm.coachPanel)
        XCTAssertFalse(vm.evaluateDailyPlanInvite(now: at(10)), "Asks again only after 2 hours")
        XCTAssertTrue(vm.evaluateDailyPlanInvite(now: at(11, 30)))
        vm.performCoachPanelSecondary(.notToday, now: at(11, 30))
        XCTAssertFalse(vm.evaluateDailyPlanInvite(now: at(15)))
    }

    func testNoPlanCardWhileAway() throws {
        let vm = try makeViewModel()
        vm.systemIdleSecondsProvider = { 900 }
        XCTAssertFalse(vm.evaluateDailyPlanInvite(now: at(9)))
    }

    // MARK: The cue

    func testCueShowsAtThePlannedTimeAndStartingKeepsThePlan() throws {
        let vm = try makeViewModel()
        // The session start uses the real clock, so the plan is for "now".
        let planned = Date().addingTimeInterval(-30)
        let label = TimerViewModel.clockLabel(planned)
        let block = try XCTUnwrap(vm.commitDailyPlan(CoachPlanSlot(start: planned, reason: .soon), now: planned.addingTimeInterval(-3600)))
        vm.hideCoachPanel()

        XCTAssertFalse(vm.evaluatePlannedCue(now: planned.addingTimeInterval(-60)))
        XCTAssertTrue(vm.evaluatePlannedCue(now: planned))
        let cue = try XCTUnwrap(vm.coachPanel)
        XCTAssertEqual(cue.kind, .plannedStart)
        XCTAssertEqual(cue.plannedBlockID, block.id)
        XCTAssertNil(cue.autoHideSeconds)
        XCTAssertEqual(cue.message.hook, "\(label). You said you'd start now.")
        XCTAssertEqual(cue.message.primaryTitle, "Start 15m focus")
        XCTAssertNotNil(cue.message.motivation)
        let attempt = try XCTUnwrap(vm.coachEngine.store.attempt(id: try XCTUnwrap(cue.attemptID)))
        XCTAssertTrue(CoachPlannedCue.isPlannedContextKey(attempt.contextKey ?? ""))
        XCTAssertFalse(CoachGuardrails.Delivery(attempt: attempt).countsTowardCap, "Requested by the user")

        // A rescue never replaces the cue.
        XCTAssertTrue(vm.evaluatePlannedCue(now: planned.addingTimeInterval(20)), "Still showing")
        XCTAssertFalse(vm.evaluateRescueLoop(now: planned.addingTimeInterval(20)))
        XCTAssertEqual(vm.coachPanel?.kind, .plannedStart)

        XCTAssertTrue(vm.performCoachPanelPrimary())
        XCTAssertEqual(vm.state, .focusing)
        XCTAssertEqual(block.status, .started)
        XCTAssertNotNil(block.sessionID)
    }

    func testCloseAndPushMoveThePlanAndThirdPushMissesIt() throws {
        let vm = try makeViewModel()
        let block = try XCTUnwrap(vm.commitDailyPlan(CoachPlanSlot(start: at(21), reason: .evening), now: at(9)))
        vm.hideCoachPanel()

        XCTAssertTrue(vm.evaluatePlannedCue(now: at(21)))
        vm.performCoachPanelSecondary(.push15, now: at(21))
        XCTAssertNil(vm.coachPanel)
        XCTAssertEqual(block.startAt, at(21, 15))
        XCTAssertEqual(block.pushes, 1)

        XCTAssertTrue(vm.evaluatePlannedCue(now: at(21, 15)))
        XCTAssertEqual(vm.coachPanel?.message.hook, "21:15. No more pushing. Begin.")
        vm.performCoachPanelSecondary(.push60, now: at(21, 15))
        XCTAssertEqual(block.startAt, at(22, 15))

        XCTAssertTrue(vm.evaluatePlannedCue(now: at(22, 15)))
        XCTAssertEqual(vm.coachPanel?.message.hook, "Pushed 2 times. Start small. Start now.")
        vm.performCoachPanelSecondary(.push15, now: at(22, 15))
        XCTAssertEqual(block.pushes, 3)
        XCTAssertTrue(vm.evaluatePlannedCue(now: at(22, 30)))
        vm.performCoachPanelSecondary(.push15, now: at(22, 30))
        XCTAssertEqual(block.status, .missed, "Past three pushes the plan is missed")
    }

    func testCloseOnACueMeansPushNotIgnored() throws {
        let vm = try makeViewModel()
        let planned = Date().addingTimeInterval(-60)
        let block = try XCTUnwrap(vm.commitDailyPlan(CoachPlanSlot(start: planned, reason: .soon), now: planned.addingTimeInterval(-3600)))
        vm.hideCoachPanel()
        XCTAssertTrue(vm.evaluatePlannedCue(now: planned))
        let attemptID = try XCTUnwrap(vm.coachPanel?.attemptID)
        vm.dismissCoachInterventionWindow()
        XCTAssertNil(vm.coachPanel)
        XCTAssertEqual(block.pushes, 1)
        XCTAssertGreaterThan(block.startAt, Date().addingTimeInterval(14 * 60))
        XCTAssertEqual(vm.coachEngine.store.attempt(id: attemptID)?.outcome, .snoozed)
    }

    func testStarterInsteadFulfilsThePlanAndSkipTodayIsRespected() throws {
        let vm = try makeViewModel()
        let block = try XCTUnwrap(vm.commitDailyPlan(CoachPlanSlot(start: at(20), reason: .evening), now: at(9)))
        vm.hideCoachPanel()
        XCTAssertTrue(vm.evaluatePlannedCue(now: at(20)))
        vm.performCoachPanelSecondary(.starterInstead, now: at(20))
        XCTAssertEqual(vm.state, .focusing)
        XCTAssertEqual(Int(vm.totalSeconds), 5 * 60)
        XCTAssertEqual(block.status, .started, "Two-minute rule: the smallest start keeps the plan")

        let vm2 = try makeViewModel()
        let other = try XCTUnwrap(vm2.commitDailyPlan(CoachPlanSlot(start: at(21), reason: .evening), now: at(9)))
        vm2.hideCoachPanel()
        XCTAssertTrue(vm2.evaluatePlannedCue(now: at(21)))
        vm2.performCoachPanelSecondary(.skipToday, now: at(21))
        XCTAssertEqual(other.status, .skipped)
        XCTAssertFalse(vm2.evaluatePlannedCue(now: at(21, 5)))
    }

    func testBusyCalendarDelaysTheCueAndAnUnansweredPlanExpires() throws {
        let vm = try makeViewModel()
        let block = try XCTUnwrap(vm.commitDailyPlan(CoachPlanSlot(start: at(18), reason: .soon), now: at(9)))
        vm.hideCoachPanel()
        vm.calendarAvailabilityProvider = { _ in CalendarAvailability(isBusyNow: true, minutesUntilNextEvent: nil) }
        XCTAssertFalse(vm.evaluatePlannedCue(now: at(18, 10)))
        vm.calendarAvailabilityProvider = { _ in .unknown }
        XCTAssertTrue(vm.evaluatePlannedCue(now: at(18, 40)), "Cue when the meeting ends")
        vm.hideCoachPanel()
        XCTAssertFalse(vm.evaluatePlannedCue(now: at(19, 31)))
        XCTAssertEqual(block.status, .missed)
    }

    func testStartingAnyBlockNearThePlanKeepsIt() throws {
        let vm = try makeViewModel()
        let block = try XCTUnwrap(vm.commitDailyPlan(CoachPlanSlot(start: Date().addingTimeInterval(20 * 60), reason: .soon), now: Date()))
        vm.hideCoachPanel()
        XCTAssertTrue(vm.startFocus())
        XCTAssertEqual(block.status, .started, "Started 20 minutes early: within the 30-minute window")
    }

    func testDoneForTodaySkipsRemainingPlans() throws {
        let vm = try makeViewModel()
        let block = try XCTUnwrap(vm.commitDailyPlan(CoachPlanSlot(start: Date().addingTimeInterval(3600), reason: .soon), now: Date()))
        vm.hideCoachPanel()
        XCTAssertTrue(vm.evaluateDailyPlanInvite(now: Date()) == false)
        // Raise a rescue-style panel and choose "Done for today".
        vm.presentCoachPanel(CoachPanelPresentation(kind: .rescue, message: CoachMessageComposer.neutralFallback(isInSession: false)))
        vm.performCoachPanelSecondary(.doneForToday)
        XCTAssertEqual(block.status, .skipped)
    }

    // MARK: Helpers

    private func makeViewModel() throws -> TimerViewModel {
        let schema = Schema([
            Project.self, FocusSession.self, AppSettings.self, TimeSplit.self, BlockProfile.self,
            AppUsageRecord.self, AppUsageEntry.self, TaskIntent.self, CoachInterruption.self,
            InterventionAttempt.self, BreakLearningEvent.self, IdleDistractionItem.self, WeeklyPriority.self, PlannedBlock.self, ProjectGoal.self, GoalKeyResult.self, GoalProgressEntry.self,
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
        try container.mainContext.save()
        vm.availabilityModelOverride = .empty
        vm.refreshCoachModelsIfNeeded(force: true)
        vm.coachArmOverride = CoachArm(surface: .panel, style: .challenger)
        defaults.set(WeeklyPriority.weekStart(for: Date()).timeIntervalSince1970, forKey: TimerViewModel.weeklyInviteDefaultsKey)
        return vm
    }
}
