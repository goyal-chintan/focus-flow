import XCTest
import SwiftData
@testable import FocusFlow

/// End-to-end coach v2 flows on a SwiftData store: reward attribution by attempt id, the panel's
/// actions, intent and outcome capture, the pseudo-productivity guard and the priorities invite.
@MainActor
final class CoachV2FlowTests: XCTestCase {
    private var container: ModelContainer!
    /// Isolated defaults suite per test: the bandit cache, pseudo-work log and weekly invite never
    /// touch the real `UserDefaults.standard`.
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
        container = nil
        super.tearDown()
    }

    // MARK: Reward ledger (resolved by attempt id)

    func testStartRewardLandsOnThePromptByIdNotNewestOrOldest() throws {
        let store = SwiftDataCoachStore(modelContext: try makeContainer().mainContext)
        let engine = FocusCoachEngine(store: store)
        let now = Date()
        engine.recordDeliveredIntervention(kind: .quickPrompt, now: now.addingTimeInterval(-3600), surface: .badge, style: .data, contextKey: "a")
        let target = engine.recordDeliveredIntervention(kind: .strongPrompt, now: now.addingTimeInterval(-300), surface: .panel, style: .challenger, contextKey: "b")
        engine.recordDeliveredIntervention(kind: .quickPrompt, now: now.addingTimeInterval(-60), surface: .badge, style: .gentle)

        let ledger = CoachRewardLedger(store: store)
        let sessionID = UUID()
        XCTAssertTrue(ledger.creditStart(attemptID: target.id, sessionID: sessionID, at: now))

        let rows = try ModelContext(container).fetch(FetchDescriptor<InterventionAttempt>(sortBy: [SortDescriptor(\.deliveredAt)]))
        XCTAssertNil(rows[0].reward)
        XCTAssertEqual(rows[1].reward, 1)
        XCTAssertEqual(rows[1].sessionId, sessionID)
        XCTAssertEqual(rows[1].outcome, .improved)
        XCTAssertNil(rows[2].reward)
    }

    func testRewardWindowCompletionAndRatings() throws {
        let store = SwiftDataCoachStore(modelContext: try makeContainer().mainContext)
        let engine = FocusCoachEngine(store: store)
        let ledger = CoachRewardLedger(store: store)
        let now = Date()

        let stale = engine.recordDeliveredIntervention(kind: .strongPrompt, now: now.addingTimeInterval(-11 * 60), surface: .panel, style: .data, contextKey: "k")
        XCTAssertFalse(ledger.creditStart(attemptID: stale.id, sessionID: UUID(), at: now), "Starts after 10 minutes are not credited")

        let fresh = engine.recordDeliveredIntervention(kind: .strongPrompt, now: now.addingTimeInterval(-120), surface: .panel, style: .data, contextKey: "k")
        let sessionID = UUID()
        XCTAssertTrue(ledger.creditStart(attemptID: fresh.id, sessionID: sessionID, at: now))
        XCTAssertTrue(ledger.creditCompletion(sessionID: sessionID))
        XCTAssertFalse(ledger.creditCompletion(sessionID: sessionID), "Completion counts once")
        XCTAssertEqual(fresh.reward, 1.5)
        XCTAssertTrue(ledger.creditOutcome(sessionID: sessionID, outcome: .busywork, previous: nil))
        XCTAssertEqual(fresh.reward, 1.0)
        XCTAssertTrue(ledger.creditOutcome(sessionID: sessionID, outcome: .shipped, previous: .busywork))
        XCTAssertEqual(fresh.reward, 2.0, "Re-rating replaces the earlier rating")

        XCTAssertEqual(ledger.resolveExpired(now: now), 1)
        XCTAssertEqual(stale.reward, 0)
        XCTAssertEqual(stale.outcome, .ignored)
        XCTAssertEqual(ledger.rewardRecords().count, 2)
    }

    // MARK: Panel actions

    func testPanelPrimaryStartsTheBlockClosesThePanelAndRewardsThePrompt() throws {
        let vm = try makeViewModel()
        let host = RecordingPanelHost()
        vm.coachPanelHost = host

        vm.evaluateIdleStarterIntervention(idleSeconds: 30 * 60, frontmostCategory: .neutral)
        let panel = try XCTUnwrap(vm.coachPanel)
        let attemptID = try XCTUnwrap(panel.attemptID)
        XCTAssertEqual(vm.pendingCoachAttemptID, attemptID)

        XCTAssertTrue(vm.performCoachPanelPrimary())

        XCTAssertEqual(vm.state, .focusing)
        XCTAssertNil(vm.coachPanel)
        XCTAssertEqual(host.hideCount, 1)
        XCTAssertEqual(vm.totalSeconds, TimeInterval(panel.plan!.minutes * 60))
        let attempt = try XCTUnwrap(vm.coachEngine.store.attempt(id: attemptID))
        XCTAssertEqual(attempt.reward, 1)
        XCTAssertEqual(attempt.surfaceRawValue, "panel")
        XCTAssertEqual(attempt.styleRawValue, "challenger")
        XCTAssertNotNil(attempt.contextKey)
        XCTAssertEqual(vm.banditModel.evidence(context: attempt.contextKey!, arm: CoachArm(surface: .panel, style: .challenger)).pulls, 1)
    }

    func testPanelShowsStartErrorAndStaysOpen() throws {
        let vm = try makeViewModel()
        vm.evaluateIdleStarterIntervention(idleSeconds: 30 * 60, frontmostCategory: .neutral)
        XCTAssertNotNil(vm.coachPanel)
        vm.isOvertime = true

        XCTAssertFalse(vm.performCoachPanelPrimary())

        XCTAssertNotNil(vm.coachPanel, "The panel stays so the user sees why")
        XCTAssertEqual(vm.coachPanelError, "Complete the current session first.")
        XCTAssertEqual(vm.state, .idle)
    }

    func testAutoHideCountsAsIgnoredAndPulsesTheMenuBarIcon() throws {
        let vm = try makeViewModel()
        vm.evaluateIdleStarterIntervention(idleSeconds: 30 * 60, frontmostCategory: .neutral)
        let panel = try XCTUnwrap(vm.coachPanel)

        vm.coachPanelTimedOut(id: panel.id)

        XCTAssertNil(vm.coachPanel)
        XCTAssertTrue(vm.coachMenuBarPulse)
        XCTAssertNotNil(vm.currentIdleStarterDecision, "The popover keeps the prompt card")
        XCTAssertEqual(vm.coachEngine.store.attempt(id: panel.attemptID!)?.outcome, .ignored)

        vm.noteCoachPopoverOpened()
        XCTAssertFalse(vm.coachMenuBarPulse)
    }

    func testNotNowAndDoneForTodayQuietTheIdleCoach() throws {
        let vm = try makeViewModel()
        vm.evaluateIdleStarterIntervention(idleSeconds: 30 * 60, frontmostCategory: .neutral)
        vm.performCoachPanelSecondary(.snooze15)
        XCTAssertNil(vm.coachPanel)
        let quiet = try XCTUnwrap(vm.coachQuietUntil)
        XCTAssertEqual(quiet.timeIntervalSinceNow, 15 * 60, accuracy: 5)

        vm.testingResetIdleCooldown()
        vm.evaluateIdleStarterIntervention(idleSeconds: 40 * 60, frontmostCategory: .neutral)
        XCTAssertEqual(vm.lastIdleStarterSuppressionReason, .snoozed)

        vm.presentCoachPanel(CoachPanelPresentation(kind: .startNudge, message: CoachMessageComposer.neutralFallback(isInSession: false)))
        vm.performCoachPanelSecondary(.doneForToday)
        XCTAssertTrue(vm.isInReleaseWindow)
        XCTAssertGreaterThan(vm.coachQuietUntil ?? .distantPast, Calendar.current.startOfDay(for: Date()))
    }

    func testIdlePromptsStaySilentOutsideLearnedWindowsAndWhenOnTrack() throws {
        let vm = try makeViewModel()
        // Learned windows that exclude the current hour.
        let hour = Calendar.current.component(.hour, from: Date())
        let otherHour = (hour + 12) % 24
        let sessions = (1...10).map { offset -> CoachAvailabilityModel.Session in
            let day = Calendar.current.date(byAdding: .day, value: -offset, to: Calendar.current.startOfDay(for: Date()))!
            let start = Calendar.current.date(byAdding: .hour, value: otherHour, to: day)!
            return .init(start: start, end: start.addingTimeInterval(1800))
        }
        vm.availabilityModelOverride = CoachAvailabilityModel(sessions: sessions, activeDays: [])
        vm.evaluateIdleStarterIntervention(idleSeconds: 30 * 60, frontmostCategory: .neutral)
        XCTAssertEqual(vm.lastIdleStarterSuppressionReason, .outsideFocusWindow)
        XCTAssertNil(vm.coachPanel)

        vm.availabilityModelOverride = .empty
        vm.todayFocusTime = 2 * 3600
        vm.evaluateIdleStarterIntervention(idleSeconds: 30 * 60, frontmostCategory: .neutral)
        XCTAssertEqual(vm.lastIdleStarterSuppressionReason, .onTrack, "Goal met: stay quiet")
    }

    func testRewardGoesToThePendingPromptEvenWhenAnotherAttemptIsNewer() throws {
        let vm = try makeViewModel()
        vm.evaluateIdleStarterIntervention(idleSeconds: 30 * 60, frontmostCategory: .neutral)
        let promptID = try XCTUnwrap(vm.pendingCoachAttemptID)
        let other = vm.coachEngine.recordDeliveredIntervention(kind: .quickPrompt, surface: .badge, style: .data)

        XCTAssertTrue(vm.startFocus())

        XCTAssertEqual(vm.coachEngine.store.attempt(id: promptID)?.reward, 1)
        XCTAssertNil(other.reward)
        XCTAssertNil(vm.pendingCoachAttemptID)
    }

    // MARK: Intent and outcome

    func testIntentAndPriorityAreSavedOnTheSessionAndPrefillNextTime() throws {
        let vm = try makeViewModel()
        let context = container.mainContext
        let project = Project(name: "Side App", color: "mint", icon: "hammer.fill")
        context.insert(project)
        let priority = WeeklyPriority(title: "Ship v1", weekStart: WeeklyPriority.weekStart(for: Date()), order: 0, projectID: project.id)
        context.insert(priority)
        try context.save()
        vm.reloadWeeklyPriorities()

        vm.selectedProject = project
        vm.pendingIntentText = "  Onboarding empty states  "
        vm.pendingPriorityID = priority.id
        XCTAssertTrue(vm.startFocus())

        let session = try XCTUnwrap(context.fetch(FetchDescriptor<FocusSession>()).first)
        XCTAssertEqual(session.intentText, "Onboarding empty states")
        XCTAssertEqual(session.priorityID, priority.id)
        XCTAssertEqual(vm.pendingIntentText, "")

        session.startedAt = Date().addingTimeInterval(-10 * 60)
        try context.save()
        vm.stop()
        vm.prefillIntentForSelectedProject()
        XCTAssertEqual(vm.pendingIntentText, "Onboarding empty states")
    }

    func testOutcomeRatingIsSavedAndFeedsTheReward() throws {
        let vm = try makeViewModel()
        vm.evaluateIdleStarterIntervention(idleSeconds: 30 * 60, frontmostCategory: .neutral)
        let promptID = try XCTUnwrap(vm.pendingCoachAttemptID)
        XCTAssertTrue(vm.performCoachPanelPrimary())
        let session = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<FocusSession>()).first)
        session.startedAt = Date().addingTimeInterval(-30 * 60)
        try container.mainContext.save()
        vm.stopForReflection()

        vm.recordSessionOutcome(.shipped)

        XCTAssertEqual(session.outcome, .shipped)
        XCTAssertEqual(vm.coachEngine.store.attempt(id: promptID)?.reward, 1.5)
        vm.recordSessionOutcome(.busywork)
        XCTAssertEqual(vm.coachEngine.store.attempt(id: promptID)?.reward, 0.5)
    }

    // MARK: Pseudo-productivity and weekly priorities

    func testPseudoProductivityGuardAsksOnceAndStartsATaggedBlock() throws {
        let vm = try makeViewModel()
        let priority = WeeklyPriority(title: "Ship v1", weekStart: WeeklyPriority.weekStart(for: Date()), order: 0)
        container.mainContext.insert(priority)
        try container.mainContext.save()
        let start = Date().addingTimeInterval(-25 * 60)

        XCTAssertFalse(vm.evaluatePseudoProductivityGuard(now: start, frontmostCategory: .productive, contextName: "Cursor"))
        XCTAssertTrue(vm.evaluatePseudoProductivityGuard(now: Date(), frontmostCategory: .neutral, contextName: "Claude"))
        let panel = try XCTUnwrap(vm.coachPanel)
        XCTAssertEqual(panel.kind, .pseudoProductivity)
        XCTAssertEqual(panel.message.hook, "Is this Ship v1, or does it just feel productive?")
        XCTAssertEqual(panel.message.primaryTitle, "It's Ship v1: start a block")
        XCTAssertEqual(panel.contextName, "Claude")

        XCTAssertTrue(vm.performCoachPanelPrimary())
        let session = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<FocusSession>()).first)
        XCTAssertEqual(session.priorityID, priority.id)
        XCTAssertEqual(CoachPseudoWorkLog(defaults: defaults).entries.last?.answer, .isPriority)

        vm.stop()
        XCTAssertFalse(vm.evaluatePseudoProductivityGuard(now: Date(), frontmostCategory: .neutral, contextName: "Claude"),
                       "Asked once per window")
    }

    func testPlannedAnswerLeavesTheUserAloneForAnHour() throws {
        let vm = try makeViewModel()
        container.mainContext.insert(WeeklyPriority(title: "Finish chapter 3", weekStart: WeeklyPriority.weekStart(for: Date()), order: 0))
        try container.mainContext.save()
        _ = vm.evaluatePseudoProductivityGuard(now: Date().addingTimeInterval(-21 * 60), frontmostCategory: .productive, contextName: "Arc")
        XCTAssertTrue(vm.evaluatePseudoProductivityGuard(now: Date(), frontmostCategory: .productive, contextName: "Arc"))

        vm.performCoachPanelSecondary(.planned)

        XCTAssertNil(vm.coachPanel)
        XCTAssertEqual(vm.coachQuietUntil?.timeIntervalSinceNow ?? 0, 60 * 60, accuracy: 5)
        XCTAssertEqual(CoachPseudoWorkLog(defaults: defaults).entries.last?.answer, .planned)
        XCTAssertEqual(vm.state, .idle)
    }

    func testFirstPromptOfAWeekWithoutPrioritiesInvitesSettingThem() throws {
        let vm = try makeViewModel()
        defaults.removeObject(forKey: TimerViewModel.weeklyInviteDefaultsKey)
        var openedSettings = 0
        vm.openSettingsScene = { openedSettings += 1 }

        vm.evaluateIdleStarterIntervention(idleSeconds: 30 * 60, frontmostCategory: .neutral)
        XCTAssertEqual(vm.coachPanel?.kind, .weeklyPriorities)
        XCTAssertEqual(vm.coachPanel?.message.primaryTitle, "Set priorities")

        XCTAssertTrue(vm.performCoachPanelPrimary())
        XCTAssertEqual(openedSettings, 1)
        XCTAssertFalse(vm.shouldInviteWeeklyPriorities(now: Date()), "Only once per week")
    }

    // MARK: Helpers

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Project.self, FocusSession.self, AppSettings.self, TimeSplit.self, BlockProfile.self,
            AppUsageRecord.self, AppUsageEntry.self, TaskIntent.self, CoachInterruption.self,
            InterventionAttempt.self, BreakLearningEvent.self, IdleDistractionItem.self, WeeklyPriority.self,
        ])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        self.container = container
        return container
    }

    /// A configured view model with the idle coach on, quiet hours off, no learned windows,
    /// the priorities invite already handled this week and the bandit forced to panel × challenger.
    private func makeViewModel() throws -> TimerViewModel {
        let container = try makeContainer()
        let vm = TimerViewModel(defaults: defaults)
        vm.configure(modelContext: container.mainContext)
        vm.calendarAvailabilityProvider = { _ in .unknown }
        let settings = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<AppSettings>()).first)
        settings.antiProcrastinationEnabled = true
        settings.coachIdleStarterEnabled = true
        settings.coachSuppressPopupsDuringScreenShare = false
        settings.coachQuietStartMinute = 0
        settings.coachQuietEndMinute = 0
        settings.coachStyle = .challenger
        try container.mainContext.save()
        vm.availabilityModelOverride = .empty
        vm.coachArmOverride = CoachArm(surface: .panel, style: .challenger)
        defaults.set(WeeklyPriority.weekStart(for: Date()).timeIntervalSince1970, forKey: TimerViewModel.weeklyInviteDefaultsKey)
        return vm
    }
}
