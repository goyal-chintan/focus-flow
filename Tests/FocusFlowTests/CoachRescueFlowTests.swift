import XCTest
import SwiftData
@testable import FocusFlow

/// End-to-end rescue loop on a SwiftData store: drift → ladder panel → ignore raises the level →
/// pause screen; starter → keep going; momentum ramp; the ⌃⌥Space shortcut; analytics.
@MainActor
final class CoachRescueFlowTests: XCTestCase {
    private var container: ModelContainer!
    /// Every container made in a test stays alive until tearDown (view models hold their contexts).
    private var containers: [ModelContainer] = []
    private var defaultsSuite = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaultsSuite = "FocusFlowTests.\(UUID())"
        defaults = UserDefaults(suiteName: defaultsSuite)!
    }

    override func tearDown() {
        AppUsageTracker.shared.stop()
        TestDefaults.remove(defaultsSuite)
        container = nil
        containers.removeAll()
        super.tearDown()
    }

    /// 14:00 today: not late night, inside the (no-data) all-day window.
    private var afternoon: Date { Calendar.current.startOfDay(for: Date()).addingTimeInterval(14 * 3600) }

    private let youtube = TimerViewModel.DriftFrontmost(
        bundleIdentifier: "com.apple.Safari", appName: "Safari", browserHost: "youtube.com",
        displayName: "YouTube", category: .distracting
    )

    /// Feeds `minutes` of `frontmost`, one sample per minute, ending at `end`.
    private func feed(_ vm: TimerViewModel, _ frontmost: TimerViewModel.DriftFrontmost, minutes: Int, endingAt end: Date) {
        for minute in stride(from: minutes - 1, through: 0, by: -1) {
            vm.recordDriftSample(frontmost, seconds: 60, now: end.addingTimeInterval(TimeInterval(-minute * 60)))
        }
    }

    // MARK: Ladder and escalation

    func testDriftRaisesARescuePanelWithTheLadderAskAndTheMenuBarCounter() throws {
        let vm = try makeViewModel()
        let now = afternoon
        feed(vm, youtube, minutes: 12, endingAt: now)

        XCTAssertTrue(vm.evaluateRescueLoop(now: now))
        XCTAssertEqual(vm.currentDrift?.level, .drifting)
        XCTAssertEqual(vm.driftMenuBarText, "YouTube 12m")
        let panel = try XCTUnwrap(vm.coachPanel)
        XCTAssertEqual(panel.kind, .rescue)
        XCTAssertEqual(panel.level, .drifting)
        XCTAssertEqual(panel.message.hook, "12m on YouTube today.")
        XCTAssertEqual(panel.message.primaryTitle, "Start 50m focus", "N from pacing: 120m owed → 50m")
        XCTAssertEqual(panel.footerHint, CoachStarterBlock.hotkeyHint)
        let attempt = try XCTUnwrap(vm.coachEngine.store.attempt(id: try XCTUnwrap(panel.attemptID)))
        XCTAssertTrue(attempt.contextKey?.hasSuffix("|lvl:1|surf:panel") == true)
        XCTAssertEqual(attempt.surfaceRawValue, "panel")

        // Settings off: no counter.
        vm.settings?.coachShowDriftInMenuBar = false
        XCTAssertNil(vm.driftMenuBarText)
    }

    func testWorkToolsNeverRaiseARescue() throws {
        let vm = try makeViewModel()
        let now = afternoon
        let slack = TimerViewModel.DriftFrontmost(bundleIdentifier: "com.tinyspeck.slackmacgap", appName: "Slack", displayName: "Slack", category: .distracting)
        feed(vm, slack, minutes: 50, endingAt: now)
        XCTAssertFalse(vm.evaluateRescueLoop(now: now))
        XCTAssertEqual(vm.currentDrift?.derailerWindowMinutes, 0)
        XCTAssertNil(vm.coachPanel)
    }

    func testIgnoringARescueRaisesTheLevelAndShrinksTheAsk() throws {
        let vm = try makeViewModel()
        let now = afternoon
        feed(vm, youtube, minutes: 12, endingAt: now)
        XCTAssertTrue(vm.evaluateRescueLoop(now: now))
        let first = try XCTUnwrap(vm.coachPanel)
        vm.coachPanelTimedOut(id: first.id)

        // v3 R2: the ignore alone never raises a second panel at once (live: 30 s apart).
        let soon = now.addingTimeInterval(60)
        feed(vm, youtube, minutes: 1, endingAt: soon)
        XCTAssertFalse(vm.evaluateRescueLoop(now: soon))
        XCTAssertNil(vm.coachPanel)

        let later = now.addingTimeInterval(20 * 60)
        feed(vm, youtube, minutes: 1, endingAt: later)
        XCTAssertTrue(vm.evaluateRescueLoop(now: later))
        XCTAssertEqual(vm.currentDrift?.baseLevel, .drifting)
        XCTAssertEqual(vm.currentDrift?.level, .lost, "One ignored rescue: L1 → L2")
        let second = try XCTUnwrap(vm.coachPanel)
        XCTAssertEqual(second.message.primaryTitle, "Just 10 minutes")
        XCTAssertEqual(second.ask?.minutes, 10)

        // Starting from it gives a 10-minute block that gets the momentum ramp once.
        XCTAssertTrue(vm.performCoachPanelPrimary())
        XCTAssertEqual(vm.state, .focusing)
        XCTAssertEqual(vm.totalSeconds, 600)
        XCTAssertNil(vm.driftMenuBarText, "A session clears the counter")
        XCTAssertNotNil(vm.rescueStartedSessionID)
        XCTAssertFalse(vm.checkMomentumRamp(), "Not before 5 minutes")
        vm.remainingSeconds = vm.totalSeconds - 300
        XCTAssertTrue(vm.checkMomentumRamp())
        XCTAssertEqual(vm.coachPanel?.kind, .momentum)
        XCTAssertEqual(vm.coachPanel?.message.hook, "You're in. Make it 25?")
        XCTAssertTrue(vm.performCoachPanelPrimary())
        XCTAssertEqual(vm.totalSeconds, 1500)
        XCTAssertNil(vm.coachPanel)
        XCTAssertFalse(vm.checkMomentumRamp(), "Offered once")
    }

    func testSpiralShowsThePauseScreenOncePerWindow() throws {
        let vm = try makeViewModel()
        let host = RecordingPauseHost()
        vm.pauseScreenHost = host
        vm.coachArmOverride = CoachArm(surface: .strongWindow, style: .challenger)
        let now = afternoon
        feed(vm, youtube, minutes: 41, endingAt: now)

        XCTAssertTrue(vm.evaluateRescueLoop(now: now))
        XCTAssertEqual(vm.currentDrift?.level, .spiral)
        let screen = try XCTUnwrap(vm.pauseScreen)
        XCTAssertEqual(host.shown.count, 1)
        XCTAssertEqual(screen.primaryTitle, "Start 5 minutes")
        XCTAssertEqual(screen.fact, "41 minutes on YouTube today")
        if case .why = screen.headline { XCTFail("No why lines are configured") }
        let attempt = try XCTUnwrap(vm.coachEngine.store.attempt(id: try XCTUnwrap(screen.attemptID)))
        XCTAssertEqual(attempt.surfaceRawValue, "strongWindow")
        XCTAssertTrue(attempt.contextKey?.hasSuffix("|lvl:3|surf:pauseScreen") == true)

        XCTAssertTrue(vm.performPauseScreenExit(.escape))
        XCTAssertNil(vm.pauseScreen)
        XCTAssertEqual(host.hideCount, 1)
        XCTAssertEqual(attempt.outcome, .dismissed)

        // Same window, 20 minutes on: the pause screen is not shown again.
        let later = now.addingTimeInterval(20 * 60)
        feed(vm, youtube, minutes: 20, endingAt: later)
        vm.evaluateRescueLoop(now: later)
        XCTAssertNil(vm.pauseScreen)
        XCTAssertEqual(host.shown.count, 1)
    }

    func testPauseScreenNeverShowsDuringCalendarBusyOrWhenDisabled() throws {
        let vm = try makeViewModel()
        vm.coachArmOverride = CoachArm(surface: .strongWindow, style: .challenger)
        vm.calendarAvailabilityProvider = { _ in CalendarAvailability(isBusyNow: true, minutesUntilNextEvent: nil) }
        let now = afternoon
        feed(vm, youtube, minutes: 45, endingAt: now)
        XCTAssertFalse(vm.evaluateRescueLoop(now: now))
        XCTAssertNil(vm.pauseScreen)
        XCTAssertEqual(vm.driftMenuBarText, "YouTube 45m", "The ambient counter is not a prompt")

        vm.calendarAvailabilityProvider = { _ in .unknown }
        vm.settings?.coachPauseScreenEnabled = false
        XCTAssertTrue(vm.evaluateRescueLoop(now: now.addingTimeInterval(30)))
        XCTAssertNil(vm.pauseScreen)
        XCTAssertEqual(vm.coachPanel?.message.primaryTitle, "5 minutes. Plan the next step.", "L3 via the panel instead")
    }

    func testPauseScreenStartRunsAStarterBlockAndCreditsTheRescue() throws {
        let vm = try makeViewModel()
        vm.coachArmOverride = CoachArm(surface: .strongWindow, style: .challenger)
        let now = Date()
        feed(vm, youtube, minutes: 41, endingAt: now)
        XCTAssertTrue(vm.evaluateRescueLoop(now: now))
        let attemptID = try XCTUnwrap(vm.pauseScreen?.attemptID)

        XCTAssertTrue(vm.performPauseScreenExit(.startStarter))
        XCTAssertEqual(vm.state, .focusing)
        XCTAssertTrue(vm.isStarterBlock)
        XCTAssertEqual(vm.totalSeconds, 300)
        let attempt = try XCTUnwrap(vm.coachEngine.store.attempt(id: attemptID))
        XCTAssertEqual(attempt.reward, 1)
        XCTAssertEqual(attempt.outcome, .improved)
    }

    func testDoneForTodayFromThePauseScreenReleasesTheCoach() throws {
        let vm = try makeViewModel()
        vm.coachArmOverride = CoachArm(surface: .strongWindow, style: .challenger)
        let now = afternoon
        feed(vm, youtube, minutes: 41, endingAt: now)
        XCTAssertTrue(vm.evaluateRescueLoop(now: now))
        XCTAssertTrue(vm.performPauseScreenExit(.doneForToday, now: now))
        XCTAssertTrue(vm.isInReleaseWindow)
        XCTAssertNotNil(vm.coachQuietUntil)
        XCTAssertFalse(vm.evaluateRescueLoop(now: now.addingTimeInterval(25 * 60)))
    }

    // MARK: Starter block and keep going

    func testStarterBlockThenKeepGoingContinuesWithTheStep() async throws {
        let vm = try makeViewModel()
        let project = Project(name: "Side App", color: "mint", icon: "hammer.fill")
        container.mainContext.insert(project)
        vm.selectedProject = project

        XCTAssertTrue(vm.startStarterBlock())
        XCTAssertTrue(vm.isStarterBlock)
        XCTAssertNil(vm.selectedProject, "A starter needs no project")
        XCTAssertEqual(vm.totalSeconds, 300)
        vm.starterStepText = "Sketch the empty state"

        await vm.testingCompleteCurrentBlock()

        XCTAssertEqual(vm.state, .idle)
        XCTAssertFalse(vm.isOvertime)
        XCTAssertFalse(vm.showSessionComplete, "No session-complete window for a starter")
        XCTAssertFalse(vm.isStarterBlock)
        XCTAssertEqual(vm.selectedProject?.id, project.id, "Selection restored")
        let panel = try XCTUnwrap(vm.coachPanel)
        XCTAssertEqual(panel.kind, .keepGoing)
        XCTAssertEqual(panel.message.hook, "Keep going: 20m on Sketch the empty state?")
        let starter = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<FocusSession>()).first)
        XCTAssertTrue(starter.completed)
        XCTAssertEqual(starter.customLabel, CoachStarterBlock.label)
        XCTAssertNil(starter.project)
        XCTAssertEqual(starter.intentText, "Sketch the empty state")

        XCTAssertTrue(vm.performCoachPanelPrimary())
        XCTAssertEqual(vm.state, .focusing)
        XCTAssertEqual(vm.totalSeconds, 1200)
        let sessions = try container.mainContext.fetch(FetchDescriptor<FocusSession>(sortBy: [SortDescriptor(\.startedAt)]))
        XCTAssertEqual(sessions.count, 2)
        let next = try XCTUnwrap(sessions.first { !$0.completed })
        XCTAssertEqual(next.intentText, "Sketch the empty state")
        XCTAssertNotEqual(next.customLabel, CoachStarterBlock.label)
    }

    func testDecliningKeepGoingStillCountsTheStarter() async throws {
        let vm = try makeViewModel()
        vm.settings?.coachStarterBlockMinutes = 2
        XCTAssertTrue(vm.startStarterBlock())
        XCTAssertEqual(vm.totalSeconds, 120, "The 2-minute setting is honoured below the usual 5-minute floor")
        await vm.testingCompleteCurrentBlock()
        XCTAssertEqual(vm.coachPanel?.message.hook, "Keep going: 20 more minutes?")

        vm.performCoachPanelSecondary(.finishStarter)
        XCTAssertNil(vm.coachPanel)
        XCTAssertEqual(vm.state, .idle)
        let starter = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<FocusSession>()).first)
        XCTAssertTrue(starter.completed)
        let reader = CoachHistoryReader(modelContext: container.mainContext)
        XCTAssertEqual(reader.focusSessions(since: Calendar.current.startOfDay(for: Date())).count, 1,
                       "A completed 2-minute starter counts toward today and the streak")
    }

    // MARK: Global shortcut

    func testHotkeyStartsAStarterAndIsANoOpDuringASession() throws {
        let vm = try makeViewModel()
        vm.settings?.coachStarterBlockMinutes = 2
        let registrar = FakeHotkey()
        vm.hotkeyRegistrar = registrar
        vm.syncGlobalHotkey()
        XCTAssertTrue(registrar.isRegistered)

        registrar.onPress?()
        XCTAssertEqual(vm.state, .focusing)
        XCTAssertTrue(vm.isStarterBlock)
        XCTAssertEqual(vm.coachPanel?.kind, .notice)
        XCTAssertEqual(vm.coachPanel?.message.hook, "Starter block started · 2 min")
        let sessionsBefore = try container.mainContext.fetch(FetchDescriptor<FocusSession>()).count

        XCTAssertFalse(vm.startStarterFromHotkey(), "Does nothing while a session runs")
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<FocusSession>()).count, sessionsBefore)
        XCTAssertEqual(vm.totalSeconds, 120)

        vm.settings?.coachGlobalHotkeyEnabled = false
        vm.syncGlobalHotkey()
        XCTAssertFalse(registrar.isRegistered)
        XCTAssertEqual(registrar.unregisterCount, 1)
    }

    func testTwoMinuteSettingReachesPanelFooterAndPauseScreen() throws {
        let vm = try makeViewModel()
        vm.settings?.coachStarterBlockMinutes = 2
        vm.coachArmOverride = CoachArm(surface: .strongWindow, style: .challenger)
        let now = afternoon
        feed(vm, youtube, minutes: 41, endingAt: now)
        XCTAssertTrue(vm.evaluateRescueLoop(now: now))
        XCTAssertEqual(vm.pauseScreen?.primaryTitle, "Start 2 minutes")
        vm.performPauseScreenExit(.realBreak, now: now)

        let other = try makeViewModel()
        other.settings?.coachStarterBlockMinutes = 2
        feed(other, youtube, minutes: 12, endingAt: now)
        XCTAssertTrue(other.evaluateRescueLoop(now: now))
        XCTAssertEqual(other.coachPanel?.footerHint, CoachStarterBlock.hotkeyHint)
    }

    // MARK: Analytics

    func testRescuesByLevelAndStartersThatKeptGoing() throws {
        let analytics = FocusAnalytics(calendar: .current)
        let start = afternoon
        let rescues = [
            RescueSample(deliveredAt: start, level: .drifting, surface: .panel),
            RescueSample(deliveredAt: start.addingTimeInterval(3600), level: .spiral, surface: .pauseScreen),
            RescueSample(deliveredAt: start.addingTimeInterval(7200), level: .spiral, surface: .pauseScreen),
        ]
        XCTAssertNil(RescueSample(contextKey: "avail:high|idle:30-90|front:work|today:0", deliveredAt: start))
        XCTAssertEqual(RescueSample(contextKey: "avail:high|idle:30-90|front:work|today:0|lvl:2|surf:panel", deliveredAt: start)?.level, .lost)

        let starterStart = start.addingTimeInterval(3600 + 120)
        let sessions = [
            FocusSample(start: starterStart, activeSeconds: 300, project: .label(CoachStarterBlock.label)),
            FocusSample(start: starterStart.addingTimeInterval(330), activeSeconds: 1250),
            FocusSample(start: start.addingTimeInterval(7200 + 60), activeSeconds: 300, project: .label(CoachStarterBlock.label)),
        ]
        let result = analytics.rescueEffectiveness(rescues: rescues, sessions: sessions, in: DateInterval(start: start.addingTimeInterval(-60), duration: 86_400))
        XCTAssertEqual(result.byLevel.map(\.key), ["L1", "L3"])
        XCTAssertEqual(result.byLevel.first { $0.key == "L3" }?.prompts, 2)
        XCTAssertEqual(result.byLevel.first { $0.key == "L3" }?.starts, 2)
        XCTAssertEqual(result.byLevel.first { $0.key == "L1" }?.starts, 0)
        XCTAssertEqual(result.bySurface.map(\.key), ["panel", "pauseScreen"])
        XCTAssertEqual(result.starterBlocks, 2)
        XCTAssertEqual(result.startersKeptGoing, 1)
        XCTAssertEqual(result.keptGoingRate ?? 0, 0.5, accuracy: 0.001)
        XCTAssertEqual(FocusAnalytics.surfaceLabel(.strongWindow), "Pause screen")
    }

    // MARK: Helpers

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Project.self, FocusSession.self, AppSettings.self, TimeSplit.self, BlockProfile.self,
            AppUsageRecord.self, AppUsageEntry.self, TaskIntent.self, CoachInterruption.self,
            InterventionAttempt.self, BreakLearningEvent.self, IdleDistractionItem.self, WeeklyPriority.self, PlannedBlock.self, ProjectGoal.self, GoalKeyResult.self, GoalProgressEntry.self, DailyTask.self,
        ])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        self.container = container
        containers.append(container)
        return container
    }

    private func makeViewModel() throws -> TimerViewModel {
        let container = try makeContainer()
        let vm = TimerViewModel(defaults: defaults)
        vm.systemIdleSecondsProvider = { 0 } // at the desk (v4 presence gate)
        vm.coachExploreSizes = false
        vm.configure(modelContext: container.mainContext)
        vm.calendarAvailabilityProvider = { _ in .unknown }
        vm.systemIdleSecondsProvider = { 0 }
        let settings = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<AppSettings>()).first)
        settings.antiProcrastinationEnabled = true
        settings.coachIdleStarterEnabled = true
        settings.coachSuppressPopupsDuringScreenShare = false
        settings.coachQuietStartMinute = 0
        settings.coachQuietEndMinute = 0
        settings.coachStyle = .challenger
        settings.coachCollectRawDomains = true
        try container.mainContext.save()
        vm.availabilityModelOverride = .empty
        vm.refreshCoachModelsIfNeeded(force: true)
        vm.coachArmOverride = CoachArm(surface: .panel, style: .challenger)
        defaults.set(WeeklyPriority.weekStart(for: Date()).timeIntervalSince1970, forKey: TimerViewModel.weeklyInviteDefaultsKey)
        return vm
    }
}

@MainActor
final class RecordingPauseHost: CoachPauseScreenHosting {
    private(set) var shown: [CoachPauseScreenPresentation] = []
    private(set) var hideCount = 0
    func showPauseScreen(_ presentation: CoachPauseScreenPresentation) { shown.append(presentation) }
    func hidePauseScreen() { hideCount += 1 }
}

@MainActor
final class FakeHotkey: CoachHotkeyRegistering {
    private(set) var isRegistered = false
    private(set) var unregisterCount = 0
    var onPress: (() -> Void)?
    func register() -> Bool { isRegistered = true; return true }
    func unregister() { isRegistered = false; unregisterCount += 1 }
}
