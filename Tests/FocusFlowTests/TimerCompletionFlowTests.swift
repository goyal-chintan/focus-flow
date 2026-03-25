import XCTest
import SwiftData
@testable import FocusFlow

@MainActor
final class TimerCompletionFlowTests: XCTestCase {
    func testContinueOvertimeActionKeepsOvertimeActive() throws {
        let container = try makeInMemoryContainer()
        let vm = TimerViewModel()
        vm.configure(modelContext: container.mainContext)
        defer { AppUsageTracker.shared.stop() }

        vm.state = .idle
        vm.isOvertime = true
        vm.overtimeSeconds = 42
        vm.showSessionComplete = true

        vm.continueAfterCompletion(action: .continueOvertime)

        XCTAssertTrue(vm.isOvertime)
        XCTAssertEqual(vm.overtimeSeconds, 42)
        XCTAssertEqual(vm.state, .idle)
        XCTAssertFalse(vm.showSessionComplete)
    }

    func testContinueFocusingRetainsCurrentSessionForStopLifecycle() throws {
        let container = try makeInMemoryContainer()
        let vm = TimerViewModel()
        vm.configure(modelContext: container.mainContext)
        defer { AppUsageTracker.shared.stop() }

        vm.state = .idle
        vm.isOvertime = true
        vm.showSessionComplete = true

        vm.continueAfterCompletion(action: .continueFocusing)
        vm.stop()

        let sessions = try container.mainContext.fetch(FetchDescriptor<FocusSession>())
        let unfinished = sessions.filter { $0.endedAt == nil }
        XCTAssertEqual(unfinished.count, 0)
    }

    func testContinueAfterCompletionTakeBreakKeepsLastCompletedFocusContext() throws {
        let container = try makeInMemoryContainer()
        let vm = TimerViewModel()
        vm.configure(modelContext: container.mainContext)
        defer { AppUsageTracker.shared.stop() }

        vm.startFocus()
        let active = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<FocusSession>()).first)
        active.startedAt = Date().addingTimeInterval(-6 * 60)
        try container.mainContext.save()
        vm.stopForReflection()

        XCTAssertNotNil(vm.lastCompletedSession)
        XCTAssertEqual(vm.lastCompletedSession?.type, .focus)

        vm.continueAfterCompletion(action: .takeBreak(duration: nil))

        XCTAssertEqual(vm.state, .onBreak(.shortBreak))
        XCTAssertNotNil(vm.lastCompletedSession)
        XCTAssertEqual(vm.lastCompletedSession?.type, .focus)
    }

    func testSkipBreakStartsNextFocusBlockInsteadOfEndingCycle() throws {
        let container = try makeInMemoryContainer()
        let vm = TimerViewModel()
        vm.configure(modelContext: container.mainContext)
        defer { AppUsageTracker.shared.stop() }

        vm.state = .onBreak(.shortBreak)
        vm.skipBreak()

        XCTAssertEqual(vm.state, .focusing)
        XCTAssertFalse(vm.isOvertime)
        XCTAssertGreaterThan(vm.remainingSeconds, 0)
    }

    func testExplicitSkipReasonCreatesSuppressionReleaseWindow() throws {
        let container = try makeInMemoryContainer()
        let vm = TimerViewModel()
        vm.configure(modelContext: container.mainContext)
        defer { AppUsageTracker.shared.stop() }

        vm.handleCoachAction(.skipCheck, skipReason: .doneForToday)

        XCTAssertTrue(vm.isInReleaseWindow)
        XCTAssertEqual(vm.suppressionWindow?.reason, .offDuty)
    }

    func testMarkOffDutyEntersExplicitReleaseAndClearsPrompts() throws {
        let container = try makeInMemoryContainer()
        let vm = TimerViewModel()
        vm.configure(modelContext: container.mainContext)
        defer { AppUsageTracker.shared.stop() }

        vm.currentCoachQuickPromptDecision = FocusCoachDecision(
            kind: .quickPrompt,
            suggestedActions: [.skipCheck],
            message: "quick"
        )
        vm.currentIdleStarterDecision = FocusCoachDecision(
            kind: .quickPrompt,
            suggestedActions: [.startFocusNow],
            message: "idle"
        )

        vm.handleCoachAction(.markOffDuty)

        XCTAssertTrue(vm.isInReleaseWindow)
        XCTAssertEqual(vm.suppressionWindow?.reason, .offDuty)
        XCTAssertNil(vm.currentCoachQuickPromptDecision)
        XCTAssertNil(vm.currentIdleStarterDecision)
    }

    func testIdleStarterPromptSuppressedWhenScreenShareActiveAndEnabled() throws {
        let container = try makeInMemoryContainer()
        let vm = TimerViewModel(
            screenShareGuard: ScreenShareGuard(isScreenSharingProvider: { true })
        )
        vm.configure(modelContext: container.mainContext)
        defer { AppUsageTracker.shared.stop() }

        let settings = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<AppSettings>()).first)
        settings.antiProcrastinationEnabled = true
        settings.coachIdleStarterEnabled = true
        settings.coachSuppressPopupsDuringScreenShare = true
        try container.mainContext.save()

        vm.lastProjectSelectedAt = Date()

        vm.evaluateIdleStarterIntervention(
            idleSeconds: 10 * 60,
            escalationLevel: 2,
            frontmostCategory: .productive
        )

        XCTAssertFalse(vm.showCoachInterventionWindow)
        XCTAssertNil(vm.activeCoachInterventionDecision)
        XCTAssertNil(vm.currentIdleStarterDecision)
    }

    func testIdleEscalationShowsStrongCoachWindowAtThirdNudgeForProductiveApp() throws {
        let container = try makeInMemoryContainer()
        let vm = TimerViewModel()
        vm.configure(modelContext: container.mainContext)
        defer { AppUsageTracker.shared.stop() }

        let settingsDescriptor = FetchDescriptor<AppSettings>()
        let settings = try XCTUnwrap(container.mainContext.fetch(settingsDescriptor).first)
        settings.antiProcrastinationEnabled = true
        settings.coachIdleStarterEnabled = true
        settings.coachAutoOpenPopoverOnStrongPrompt = true
        settings.coachBringAppToFrontOnStrongPrompt = false
        settings.coachAllowSkipAction = true
        settings.coachInterventionMode = .balanced
        try container.mainContext.save()

        vm.evaluateIdleStarterIntervention(
            idleSeconds: 10 * 60,
            escalationLevel: 2,
            frontmostCategory: .productive
        )

        XCTAssertTrue(vm.showCoachInterventionWindow)
        XCTAssertEqual(vm.activeCoachInterventionDecision?.kind, .strongPrompt)
    }

    func testStrongPromptWindowDoesNotAutoOpenWhenSettingIsDisabled() throws {
        let container = try makeInMemoryContainer()
        let vm = TimerViewModel()
        vm.configure(modelContext: container.mainContext)
        defer { AppUsageTracker.shared.stop() }

        let settingsDescriptor = FetchDescriptor<AppSettings>()
        let settings = try XCTUnwrap(container.mainContext.fetch(settingsDescriptor).first)
        settings.antiProcrastinationEnabled = true
        settings.coachIdleStarterEnabled = true
        settings.coachAutoOpenPopoverOnStrongPrompt = false
        settings.coachBringAppToFrontOnStrongPrompt = false
        settings.coachAllowSkipAction = true
        settings.coachInterventionMode = .balanced
        try container.mainContext.save()

        var coachWindowOpenRequests = 0
        var appActivationRequests = 0
        vm.openCoachInterventionWindow = {
            coachWindowOpenRequests += 1
        }
        vm.requestAppActivation = {
            appActivationRequests += 1
        }

        vm.evaluateIdleStarterIntervention(
            idleSeconds: 10 * 60,
            escalationLevel: 2,
            frontmostCategory: .productive
        )

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))

        XCTAssertFalse(vm.showCoachInterventionWindow)
        XCTAssertNil(vm.activeCoachInterventionDecision)
        XCTAssertEqual(vm.currentIdleStarterDecision?.kind, .strongPrompt)
        XCTAssertEqual(coachWindowOpenRequests, 0)
        XCTAssertEqual(appActivationRequests, 0)
    }

    func testStrongPromptSuppressesPopoverCardWhenEscalatingToWindow() throws {
        let container = try makeInMemoryContainer()
        let vm = TimerViewModel()
        vm.configure(modelContext: container.mainContext)
        defer { AppUsageTracker.shared.stop() }

        let settings = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<AppSettings>()).first)
        settings.antiProcrastinationEnabled = true
        settings.coachIdleStarterEnabled = true
        settings.coachAutoOpenPopoverOnStrongPrompt = true
        settings.coachBringAppToFrontOnStrongPrompt = false
        settings.coachAllowSkipAction = true
        settings.coachInterventionMode = .balanced
        try container.mainContext.save()

        vm.evaluateIdleStarterIntervention(
            idleSeconds: 10 * 60,
            escalationLevel: 2,
            frontmostCategory: .productive
        )

        XCTAssertTrue(vm.showCoachInterventionWindow)
        XCTAssertEqual(vm.activeCoachInterventionDecision?.kind, .strongPrompt)
        XCTAssertNil(vm.currentIdleStarterDecision)
    }

    func testStartFocusRequestsPopoverCloseOnCommit() throws {
        let container = try makeInMemoryContainer()
        let vm = TimerViewModel()
        vm.configure(modelContext: container.mainContext)
        defer { AppUsageTracker.shared.stop() }
        var closeRequests = 0
        vm.onPopoverCloseRequested = { closeRequests += 1 }

        vm.startFocus()

        XCTAssertEqual(vm.state, .focusing)
        XCTAssertEqual(closeRequests, 1)
    }

    func testContinueAfterCompletionEndSessionRequestsPopoverClose() throws {
        let container = try makeInMemoryContainer()
        let vm = TimerViewModel()
        vm.configure(modelContext: container.mainContext)
        defer { AppUsageTracker.shared.stop() }
        var closeRequests = 0
        vm.onPopoverCloseRequested = { closeRequests += 1 }

        vm.startFocus()
        let active = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<FocusSession>()).first)
        active.startedAt = Date().addingTimeInterval(-8 * 60)
        try container.mainContext.save()
        vm.stopForReflection()

        vm.continueAfterCompletion(action: .endSession)

        XCTAssertEqual(closeRequests, 3) // startFocus + stopForReflection + continueAfterCompletion
    }

    func testStrongPromptRequestsSingleSurfacePresentationWithForeground() throws {
        let container = try makeInMemoryContainer()
        let vm = TimerViewModel()
        vm.configure(modelContext: container.mainContext)
        defer { AppUsageTracker.shared.stop() }

        let settings = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<AppSettings>()).first)
        settings.antiProcrastinationEnabled = true
        settings.coachIdleStarterEnabled = true
        settings.coachAutoOpenPopoverOnStrongPrompt = true
        settings.coachBringAppToFrontOnStrongPrompt = true
        settings.coachAllowSkipAction = true
        settings.coachInterventionMode = .balanced
        try container.mainContext.save()

        var coachWindowOpenRequests = 0
        var appActivationRequests = 0
        vm.openCoachInterventionWindow = {
            coachWindowOpenRequests += 1
        }
        vm.requestAppActivation = {
            appActivationRequests += 1
        }

        vm.evaluateIdleStarterIntervention(
            idleSeconds: 10 * 60,
            escalationLevel: 2,
            frontmostCategory: .productive
        )

        // openCoachInterventionWindow & requestAppActivation are now dispatched async
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))

        XCTAssertTrue(vm.showCoachInterventionWindow)
        XCTAssertEqual(coachWindowOpenRequests, 1)
        XCTAssertEqual(appActivationRequests, 1)
        XCTAssertNil(vm.currentIdleStarterDecision)
    }

    func testStrongPromptDoesNotRequestActivationWhenBringToFrontSettingIsDisabled() throws {
        let container = try makeInMemoryContainer()
        let vm = TimerViewModel()
        vm.configure(modelContext: container.mainContext)
        defer { AppUsageTracker.shared.stop() }

        let settings = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<AppSettings>()).first)
        settings.antiProcrastinationEnabled = true
        settings.coachIdleStarterEnabled = true
        settings.coachAutoOpenPopoverOnStrongPrompt = true
        settings.coachBringAppToFrontOnStrongPrompt = false
        settings.coachAllowSkipAction = true
        settings.coachInterventionMode = .balanced
        try container.mainContext.save()

        var coachWindowOpenRequests = 0
        var appActivationRequests = 0
        vm.openCoachInterventionWindow = {
            coachWindowOpenRequests += 1
        }
        vm.requestAppActivation = {
            appActivationRequests += 1
        }

        vm.evaluateIdleStarterIntervention(
            idleSeconds: 10 * 60,
            escalationLevel: 2,
            frontmostCategory: .productive
        )

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))

        XCTAssertTrue(vm.showCoachInterventionWindow)
        XCTAssertEqual(coachWindowOpenRequests, 1)
        XCTAssertEqual(appActivationRequests, 0)
    }

    func testBreakOverrunReasonPromptActivatesDuringOvertime() throws {
        let container = try makeInMemoryContainer()
        let vm = TimerViewModel()
        vm.configure(modelContext: container.mainContext)
        defer { AppUsageTracker.shared.stop() }

        let settings = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<AppSettings>()).first)
        settings.coachReasonPromptsEnabled = true
        try container.mainContext.save()

        vm.overtimeSeconds = 119
        vm.showCoachReasonSheet = false

        vm.overtimeSeconds += 1
        vm.updateBreakOverrunReasonPromptIfNeeded(completedSessionType: .shortBreak)

        XCTAssertTrue(vm.showCoachReasonSheet)
        XCTAssertEqual(vm.pendingReasonKind, .breakOverrun)
    }

    func testBreakOverrunReasonPromptDoesNotLoopAfterReasonSubmitted() throws {
        let container = try makeInMemoryContainer()
        let vm = TimerViewModel()
        vm.configure(modelContext: container.mainContext)
        defer { AppUsageTracker.shared.stop() }

        let settings = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<AppSettings>()).first)
        settings.coachReasonPromptsEnabled = true
        try container.mainContext.save()

        vm.overtimeSeconds = 120
        vm.showCoachReasonSheet = false

        vm.updateBreakOverrunReasonPromptIfNeeded(completedSessionType: .shortBreak)
        XCTAssertTrue(vm.showCoachReasonSheet)
        XCTAssertEqual(vm.pendingReasonKind, .breakOverrun)

        vm.recordCoachReason(kind: .breakOverrun, reason: .meeting)
        vm.showCoachReasonSheet = false

        vm.updateBreakOverrunReasonPromptIfNeeded(completedSessionType: .shortBreak)
        XCTAssertFalse(vm.showCoachReasonSheet, "Reason prompt should not reopen repeatedly in the same overrun episode")
    }

    func testConfigurePurgesExistingFocusSessionsUnderMinimumRetained() throws {
        let container = try makeInMemoryContainer()
        let now = Date()

        let shortFocus = FocusSession(type: .focus, duration: 4 * 60)
        shortFocus.startedAt = now.addingTimeInterval(-4 * 60)
        shortFocus.endedAt = now
        shortFocus.completed = true

        let longFocus = FocusSession(type: .focus, duration: 25 * 60)
        longFocus.startedAt = now.addingTimeInterval(-25 * 60)
        longFocus.endedAt = now
        longFocus.completed = true

        container.mainContext.insert(shortFocus)
        container.mainContext.insert(longFocus)
        try container.mainContext.save()

        let vm = TimerViewModel()
        vm.configure(modelContext: container.mainContext)
        defer { AppUsageTracker.shared.stop() }

        let sessions = try container.mainContext.fetch(FetchDescriptor<FocusSession>())
        let focusSessions = sessions.filter { $0.type == .focus }

        XCTAssertEqual(focusSessions.count, 1)
        XCTAssertGreaterThanOrEqual(focusSessions.first?.actualDuration ?? 0, 5 * 60)
    }

    // MARK: - Phase 1 Spine Tests

    func testDeferBreakAndStartNextBlockEndsInFocusingNotIdle() throws {
        let container = try makeInMemoryContainer()
        let vm = TimerViewModel()
        vm.configure(modelContext: container.mainContext)
        defer { AppUsageTracker.shared.stop() }

        // Put VM in onBreak so deferBreakAndStartNextBlock guard passes
        vm.state = .onBreak(.shortBreak)
        vm.deferBreakAndStartNextBlock()

        XCTAssertEqual(vm.state, .focusing, "deferBreakAndStartNextBlock must end in .focusing, not .idle")
    }

    func testCompletedBlockContextIsNonNilAfterFocusSessionCompletes() throws {
        let container = try makeInMemoryContainer()
        let vm = TimerViewModel()
        vm.configure(modelContext: container.mainContext)
        defer { AppUsageTracker.shared.stop() }

        vm.startFocus()
        let active = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<FocusSession>()).first)
        active.startedAt = Date().addingTimeInterval(-6 * 60)
        try container.mainContext.save()
        vm.stopForReflection()

        XCTAssertNotNil(vm.completedBlockContext, "completedBlockContext must be set after a focus session completes")
    }

    func testCompletedBlockContextSurvivesDeferBreakAndStartNextBlock() throws {
        let container = try makeInMemoryContainer()
        let vm = TimerViewModel()
        vm.configure(modelContext: container.mainContext)
        defer { AppUsageTracker.shared.stop() }

        // Complete a focus session to populate completedBlockContext
        vm.startFocus()
        let active = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<FocusSession>()).first)
        active.startedAt = Date().addingTimeInterval(-6 * 60)
        try container.mainContext.save()
        vm.stopForReflection()
        vm.continueAfterCompletion(action: .takeBreak(duration: nil))

        let contextBefore = vm.completedBlockContext
        XCTAssertNotNil(contextBefore)

        // Now defer the break and start next block
        vm.deferBreakAndStartNextBlock()

        XCTAssertNotNil(vm.completedBlockContext, "completedBlockContext must survive deferBreakAndStartNextBlock()")
        XCTAssertEqual(vm.completedBlockContext?.sessionId, contextBefore?.sessionId)
    }

    func testClassifyBreakRecoveryDoneForNowActivatesSuppressionWindow() throws {
        let container = try makeInMemoryContainer()
        let vm = TimerViewModel()
        vm.configure(modelContext: container.mainContext)
        defer { AppUsageTracker.shared.stop() }

        XCTAssertFalse(vm.isInReleaseWindow, "No release window should be active before classifyBreakRecovery")

        vm.classifyBreakRecovery(.doneForNow)

        XCTAssertTrue(vm.isInReleaseWindow, "classifyBreakRecovery(.doneForNow) must activate the suppression window")
    }

    func testBlockForProjectStoresAppContextTargetInBlockedApps() throws {
        let container = try makeInMemoryContainer()
        let vm = TimerViewModel()
        vm.configure(modelContext: container.mainContext)
        defer { AppUsageTracker.shared.stop() }

        let project = Project(name: "Core Architecture")
        container.mainContext.insert(project)
        vm.selectedProject = project

        vm.currentCoachQuickPromptDecision = FocusCoachDecision(
            kind: .quickPrompt,
            suggestedActions: [.blockForProject],
            message: "Block app target",
            context: FocusCoachContext(
                idleSeconds: 0,
                frontmostAppName: "Ghostty",
                frontmostBundleIdentifier: "com.mitchellh.ghostty",
                frontmostAppCategory: .neutral,
                isInActiveSession: false,
                todayFocusSeconds: 0,
                dailyGoalSeconds: 3600,
                todaySessionCount: 0,
                selectedProjectName: project.name,
                selectedWorkMode: .deepWork,
                hourOfDay: 10,
                topDistractingAppName: nil,
                topDistractingAppMinutes: 0,
                recentLowPriorityWorkCount: 0,
                suggestedBlockTarget: "app:com.mitchellh.ghostty",
                blockRecommendationReason: "ghostty drift",
                inReleaseWindow: false
            )
        )

        vm.handleCoachAction(.blockForProject)

        XCTAssertTrue(project.blockProfile?.blockedApps.contains("com.mitchellh.ghostty") ?? false)
        XCTAssertFalse(project.blockProfile?.blockedWebsites.contains("app:com.mitchellh.ghostty") ?? true)
    }

    func testBlockForProjectKeepsDomainBehaviorInBlockedWebsites() throws {
        let container = try makeInMemoryContainer()
        let vm = TimerViewModel()
        vm.configure(modelContext: container.mainContext)
        defer { AppUsageTracker.shared.stop() }

        let project = Project(name: "Research")
        container.mainContext.insert(project)
        vm.selectedProject = project

        vm.currentCoachQuickPromptDecision = FocusCoachDecision(
            kind: .quickPrompt,
            suggestedActions: [.blockForProject],
            message: "Block domain target",
            context: FocusCoachContext(
                idleSeconds: 0,
                frontmostAppName: "Safari",
                frontmostBundleIdentifier: "com.apple.Safari",
                frontmostAppCategory: .distracting,
                isInActiveSession: false,
                todayFocusSeconds: 0,
                dailyGoalSeconds: 3600,
                todaySessionCount: 0,
                selectedProjectName: project.name,
                selectedWorkMode: .deepWork,
                hourOfDay: 10,
                topDistractingAppName: nil,
                topDistractingAppMinutes: 0,
                recentLowPriorityWorkCount: 0,
                suggestedBlockTarget: "youtube.com",
                blockRecommendationReason: "youtube drift",
                inReleaseWindow: false
            )
        )

        vm.handleCoachAction(.blockForProject)

        XCTAssertTrue(project.blockProfile?.blockedWebsites.contains("youtube.com") ?? false)
    }

    func testBlockForProjectDoesNotDuplicateTargetAcrossMultipleProfiles() throws {
        let container = try makeInMemoryContainer()
        let vm = TimerViewModel()
        vm.configure(modelContext: container.mainContext)
        defer { AppUsageTracker.shared.stop() }

        let project = Project(name: "Research")
        let profileA = BlockProfile(name: "A", websites: ["youtube.com"])
        let profileB = BlockProfile(name: "B", websites: ["reddit.com"])
        container.mainContext.insert(project)
        container.mainContext.insert(profileA)
        container.mainContext.insert(profileB)
        project.blockProfiles = [profileA, profileB]
        project.blockProfile = profileA
        vm.selectedProject = project

        vm.currentCoachQuickPromptDecision = FocusCoachDecision(
            kind: .quickPrompt,
            suggestedActions: [.blockForProject],
            message: "Block domain target",
            context: FocusCoachContext(
                idleSeconds: 0,
                frontmostAppName: "Safari",
                frontmostBundleIdentifier: "com.apple.Safari",
                frontmostAppCategory: .distracting,
                isInActiveSession: false,
                todayFocusSeconds: 0,
                dailyGoalSeconds: 3600,
                todaySessionCount: 0,
                selectedProjectName: project.name,
                selectedWorkMode: .deepWork,
                hourOfDay: 10,
                topDistractingAppName: nil,
                topDistractingAppMinutes: 0,
                recentLowPriorityWorkCount: 0,
                suggestedBlockTarget: "youtube.com",
                blockRecommendationReason: "youtube drift",
                inReleaseWindow: false
            )
        )

        vm.handleCoachAction(.blockForProject)

        XCTAssertEqual(project.effectiveBlockProfiles.count, 2)
        XCTAssertEqual(project.mergedBlockedWebsites.filter { $0 == "youtube.com" }.count, 1)
    }

    func testSuggestedEarnedBreakIsCalculatedAfterMeaningfulFocusCompletion() throws {
        let container = try makeInMemoryContainer()
        let vm = TimerViewModel()
        vm.configure(modelContext: container.mainContext)
        defer { AppUsageTracker.shared.stop() }

        vm.selectedMinutes = 55
        vm.startFocus()
        let active = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<FocusSession>()).first)
        active.startedAt = Date().addingTimeInterval(-55 * 60)
        try container.mainContext.save()

        vm.stopForReflection()

        XCTAssertEqual(vm.suggestedEarnedBreakMinutes, 15)
    }

    func testChoosingSuggestedBreakStartsBreakWithSuggestedDuration() throws {
        let container = try makeInMemoryContainer()
        let vm = TimerViewModel()
        vm.configure(modelContext: container.mainContext)
        defer { AppUsageTracker.shared.stop() }

        vm.suggestedEarnedBreakMinutes = 12
        vm.state = .idle
        vm.isOvertime = true
        vm.showSessionComplete = true

        vm.continueAfterCompletion(action: .takeBreak(duration: vm.suggestedEarnedBreakSeconds))

        XCTAssertEqual(vm.state, .onBreak(.shortBreak))
        XCTAssertEqual(vm.totalSeconds, 12 * 60)
        XCTAssertEqual(vm.remainingSeconds, 12 * 60)
    }

    func testBreakOutcomeRecordedWhenReturningToFocus() throws {
        let container = try makeInMemoryContainer()
        let vm = TimerViewModel()
        vm.configure(modelContext: container.mainContext)
        defer { AppUsageTracker.shared.stop() }

        vm.startFocus()
        let focus = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<FocusSession>()).first(where: { $0.type == .focus }))
        focus.startedAt = Date().addingTimeInterval(-25 * 60)
        try container.mainContext.save()
        vm.stopForReflection()

        vm.suggestedEarnedBreakMinutes = 8
        vm.continueAfterCompletion(action: .takeBreak(duration: vm.suggestedEarnedBreakSeconds))
        vm.continueAfterCompletion(action: .continueFocusing)

        let events = try container.mainContext.fetch(FetchDescriptor<BreakLearningEvent>())
        XCTAssertEqual(events.count, 1)
        XCTAssertTrue(events[0].returnedToFocus)
    }

    private func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([
            Project.self,
            FocusSession.self,
            AppSettings.self,
            TimeSplit.self,
            BlockProfile.self,
            AppUsageRecord.self,
            AppUsageEntry.self,
            TaskIntent.self,
            CoachInterruption.self,
            InterventionAttempt.self,
            BreakLearningEvent.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: config)
    }
}
