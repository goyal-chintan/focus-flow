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

    func testStrongPromptWindowShowsEvenWhenPopoverAutoOpenIsDisabled() throws {
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

        vm.evaluateIdleStarterIntervention(
            idleSeconds: 10 * 60,
            escalationLevel: 2,
            frontmostCategory: .productive
        )

        XCTAssertTrue(vm.showCoachInterventionWindow)
        XCTAssertEqual(vm.activeCoachInterventionDecision?.kind, .strongPrompt)
        XCTAssertNil(vm.currentIdleStarterDecision)
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
        vm.requestPopoverClose = {
            closeRequests += 1
        }

        vm.startFocus()

        XCTAssertEqual(vm.state, .focusing)
        XCTAssertEqual(closeRequests, 1)
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

        var closeRequests = 0
        var coachWindowOpenRequests = 0
        var appActivationRequests = 0
        vm.requestPopoverClose = {
            closeRequests += 1
        }
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

        XCTAssertTrue(vm.showCoachInterventionWindow)
        XCTAssertEqual(coachWindowOpenRequests, 1)
        XCTAssertEqual(closeRequests, 1)
        XCTAssertEqual(appActivationRequests, 1)
        XCTAssertNil(vm.currentIdleStarterDecision)
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

    func testConfigurePurgesExistingFocusSessionsUnderElevenMinutes() throws {
        let container = try makeInMemoryContainer()
        let now = Date()

        let shortFocus = FocusSession(type: .focus, duration: 10 * 60)
        shortFocus.startedAt = now.addingTimeInterval(-10 * 60)
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
        XCTAssertGreaterThanOrEqual(focusSessions.first?.actualDuration ?? 0, 11 * 60)
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
            InterventionAttempt.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: config)
    }
}
