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

    func testIdleStarterSuppressionRecordsReasonWhenBlockedByScreenShare() throws {
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

        XCTAssertEqual(vm.lastIdleStarterSuppressionReason, .screenShareSuppressed)
    }

    func testIdleStarterSuppressionRecordsReasonWhenReleaseWindowIsActive() throws {
        let container = try makeInMemoryContainer()
        let vm = TimerViewModel()
        vm.configure(modelContext: container.mainContext)
        defer { AppUsageTracker.shared.stop() }

        let settings = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<AppSettings>()).first)
        settings.antiProcrastinationEnabled = true
        settings.coachIdleStarterEnabled = true
        try container.mainContext.save()

        vm.enterRelease(reason: .offDuty)
        vm.lastProjectSelectedAt = Date()
        vm.evaluateIdleStarterIntervention(
            idleSeconds: 10 * 60,
            escalationLevel: 2,
            frontmostCategory: .productive
        )

        XCTAssertEqual(vm.lastIdleStarterSuppressionReason, .releaseWindowActive)
    }

    func testStartFocusClearsOutsideSessionEscalationState() throws {
        let container = try makeInMemoryContainer()
        let vm = TimerViewModel()
        vm.configure(modelContext: container.mainContext)
        defer { AppUsageTracker.shared.stop() }

        vm.outsideSessionAwaitingStartFocus = true
        vm.outsideSessionNudgeAttemptCount = 3
        vm.pendingNotificationNudgeAt = Date()
        vm.outsideSessionEscalationCooldownUntil = Date().addingTimeInterval(600)

        vm.startFocus()

        XCTAssertFalse(vm.outsideSessionAwaitingStartFocus)
        XCTAssertEqual(vm.outsideSessionNudgeAttemptCount, 0)
        XCTAssertNil(vm.pendingNotificationNudgeAt)
        XCTAssertNil(vm.outsideSessionEscalationCooldownUntil)
    }

    func testNonStartActionsDoNotClearOutsideSessionEscalationState() throws {
        let container = try makeInMemoryContainer()
        let vm = TimerViewModel()
        vm.configure(modelContext: container.mainContext)
        defer { AppUsageTracker.shared.stop() }

        vm.outsideSessionAwaitingStartFocus = true
        vm.outsideSessionNudgeAttemptCount = 2
        vm.pendingNotificationNudgeAt = Date()
        vm.outsideSessionEscalationCooldownUntil = Date().addingTimeInterval(300)

        vm.evaluateIdleStarterIntervention(
            idleSeconds: 10 * 60,
            escalationLevel: 0,
            frontmostCategory: .productive
        )

        XCTAssertTrue(vm.outsideSessionAwaitingStartFocus)
        XCTAssertEqual(vm.outsideSessionNudgeAttemptCount, 2)
        XCTAssertNotNil(vm.pendingNotificationNudgeAt)
    }

    func testIdleInterventionEscalatesToStrongPromptWithoutNotificationsAfterRepeatedNudges() throws {
        let container = try makeInMemoryContainer()
        let vm = TimerViewModel()
        vm.configure(modelContext: container.mainContext)
        defer { AppUsageTracker.shared.stop() }

        let settings = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<AppSettings>()).first)
        settings.antiProcrastinationEnabled = true
        settings.coachIdleStarterEnabled = true
        settings.coachSuppressPopupsDuringScreenShare = false
        settings.coachInterventionMode = .balanced
        // Keep auto-open off so the decision lands in currentIdleStarterDecision for inspection.
        settings.coachAutoOpenPopoverOnStrongPrompt = false
        try container.mainContext.save()

        NotificationService.shared.refreshAuthorizationStatus()
        XCTAssertEqual(NotificationService.shared.authorizationState, .denied)

        vm.lastProjectSelectedAt = Date()
        vm.evaluateIdleStarterIntervention(
            idleSeconds: 10 * 60,
            escalationLevel: 2,
            frontmostCategory: .distracting
        )

        // After 2 prior nudges without notifications, the coach must escalate to a strong prompt
        // rather than silently setting popover content that the user never sees.
        XCTAssertFalse(vm.outsideSessionAwaitingStartFocus)
        XCTAssertNil(vm.pendingNotificationNudgeAt)
        XCTAssertEqual(vm.currentIdleStarterDecision?.kind, .strongPrompt)
    }

    func testMissedNotificationEscalatesToStrongPrompt() throws {
        let container = try makeInMemoryContainer()
        let vm = TimerViewModel()
        vm.configure(modelContext: container.mainContext)
        defer { AppUsageTracker.shared.stop() }

        let settings = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<AppSettings>()).first)
        settings.antiProcrastinationEnabled = true
        settings.coachIdleStarterEnabled = true
        settings.coachSuppressPopupsDuringScreenShare = false
        settings.coachInterventionMode = .balanced
        settings.coachAutoOpenPopoverOnStrongPrompt = true
        settings.coachBringAppToFrontOnStrongPrompt = false
        try container.mainContext.save()

        vm.lastProjectSelectedAt = Date()
        vm.pendingNotificationNudgeAt = Date().addingTimeInterval(-2000)
        vm.outsideSessionAwaitingStartFocus = true
        vm.outsideSessionNudgeAttemptCount = 1

        vm.evaluateIdleStarterIntervention(
            idleSeconds: 10 * 60,
            escalationLevel: 2,
            frontmostCategory: .distracting
        )

        XCTAssertTrue(vm.showCoachInterventionWindow || vm.currentIdleStarterDecision?.kind == .strongPrompt || vm.activeCoachInterventionDecision?.kind == .strongPrompt)
    }

    /// Regression test: strong prompt must fire when a notification was sent and ignored,
    /// even when all work-intent recency signals are stale AND it's outside typical work hours.
    /// Root cause: `shouldEscalateToStrongPrompt` was inside `if route.shouldPresent`, and
    /// routeIdleStarter's work-intent gate (guardian=.challenge) blocked shouldPresent=true
    /// when isWorkIntentWindow=false (hour=22, no recent project/app interaction).
    func testIdleEscalationFiringOutsideWorkHoursWhenNotificationWasIgnored() throws {
        let container = try makeInMemoryContainer()
        let vm = TimerViewModel()
        vm.configure(modelContext: container.mainContext)
        defer { AppUsageTracker.shared.stop() }

        let settings = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<AppSettings>()).first)
        settings.antiProcrastinationEnabled = true
        settings.coachIdleStarterEnabled = true
        settings.coachSuppressPopupsDuringScreenShare = false
        settings.coachInterventionMode = .balanced
        settings.coachAutoOpenPopoverOnStrongPrompt = true
        settings.coachBringAppToFrontOnStrongPrompt = false
        try container.mainContext.save()

        // Notification was sent long enough ago to exceed the escalation delay even during the
        // night-time backoff window. This keeps the test focused on the work-intent gate.
        vm.pendingNotificationNudgeAt = Date().addingTimeInterval(-(20 * 60))
        vm.outsideSessionAwaitingStartFocus = true
        vm.outsideSessionNudgeAttemptCount = 1
        // App opened and project selected a LONG time ago — no recency signals
        vm.appLaunchTime = Date().addingTimeInterval(-3600)
        vm.lastProjectSelectedAt = Date().addingTimeInterval(-3600)

        // Force hour=22 (10pm) — withinTypicalWorkHours=false → isWorkIntentWindow=false without fix
        vm.evaluateIdleStarterIntervention(
            idleSeconds: 20 * 60,
            escalationLevel: 2,
            frontmostCategory: .distracting,
            currentHourOverride: 22
        )

        XCTAssertTrue(
            vm.showCoachInterventionWindow
                || vm.currentIdleStarterDecision?.kind == .strongPrompt
                || vm.activeCoachInterventionDecision?.kind == .strongPrompt,
            "Strong prompt must fire when notification was ignored, regardless of work hours"
        )
        XCTAssertFalse(vm.outsideSessionAwaitingStartFocus, "Flag must clear after escalation")
    }

    func testScreenShareHardPassSuppressesNotificationAndPrompt() throws {
        let container = try makeInMemoryContainer()
        let vm = TimerViewModel(screenShareGuard: ScreenShareGuard(isScreenSharingProvider: { true }))
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
            escalationLevel: 1,
            frontmostCategory: .productive
        )

        XCTAssertFalse(vm.outsideSessionAwaitingStartFocus)
        XCTAssertFalse(vm.showCoachInterventionWindow)
        XCTAssertNil(vm.currentIdleStarterDecision)
        XCTAssertEqual(vm.lastIdleStarterSuppressionReason, .screenShareSuppressed)
    }

    func testOutsideSessionCooldownIncreasesAtNight() throws {
        let vm = TimerViewModel()
        let calendar = Calendar.current
        let baseDate = Date()
        let day = try XCTUnwrap(calendar.date(bySettingHour: 13, minute: 0, second: 0, of: baseDate))
        let night = try XCTUnwrap(calendar.date(bySettingHour: 23, minute: 0, second: 0, of: baseDate))
        let dayDelay = vm.outsideSessionEscalationDelaySeconds(now: day, nonResponseStreak: 0, skipStreak: 0)
        let nightDelay = vm.outsideSessionEscalationDelaySeconds(now: night, nonResponseStreak: 0, skipStreak: 0)
        XCTAssertGreaterThan(nightDelay, dayDelay)
    }

    func testOutsideSessionCooldownIncreasesWithRepeatedNonResponse() throws {
        let vm = TimerViewModel()
        let base = vm.outsideSessionEscalationDelaySeconds(now: Date(timeIntervalSince1970: 13 * 60 * 60), nonResponseStreak: 0, skipStreak: 0)
        let increased = vm.outsideSessionEscalationDelaySeconds(now: Date(timeIntervalSince1970: 13 * 60 * 60), nonResponseStreak: 3, skipStreak: 0)
        XCTAssertGreaterThan(increased, base)
    }

    func testOutsideSessionCooldownIncreasesWithRepeatedSkipOrSnooze() throws {
        let vm = TimerViewModel()
        let base = vm.outsideSessionEscalationDelaySeconds(now: Date(timeIntervalSince1970: 13 * 60 * 60), nonResponseStreak: 0, skipStreak: 0)
        let increased = vm.outsideSessionEscalationDelaySeconds(now: Date(timeIntervalSince1970: 13 * 60 * 60), nonResponseStreak: 0, skipStreak: 3)
        XCTAssertGreaterThan(increased, base)
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

    func testIdleStarterContextSuppressesPersistedDomainEntriesWhenRawDomainCaptureDisabled() throws {
        let container = try makeInMemoryContainer()
        let vm = TimerViewModel()
        vm.configure(modelContext: container.mainContext)
        defer { AppUsageTracker.shared.stop() }

        let settings = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<AppSettings>()).first)
        settings.antiProcrastinationEnabled = true
        settings.coachIdleStarterEnabled = true
        settings.coachAutoOpenPopoverOnStrongPrompt = false
        settings.coachBringAppToFrontOnStrongPrompt = false
        settings.coachInterventionMode = .balanced
        settings.coachCollectRawDomains = false

        container.mainContext.insert(
            AppUsageEntry(
                date: Calendar.current.startOfDay(for: Date()),
                appName: "YouTube",
                bundleIdentifier: "domain:youtube.com",
                duringFocusSeconds: 0,
                outsideFocusSeconds: 30 * 60
            )
        )
        try container.mainContext.save()

        vm.lastProjectSelectedAt = Date()
        vm.evaluateIdleStarterIntervention(
            idleSeconds: 10 * 60,
            escalationLevel: 2,
            frontmostCategory: .productive
        )

        let context = try XCTUnwrap(vm.currentIdleStarterDecision?.context)
        XCTAssertNil(context.suggestedBlockTarget)
        XCTAssertNil(context.blockRecommendationReason)
        XCTAssertNil(context.topDistractingAppName)
        XCTAssertFalse(vm.currentIdleStarterDecision?.message?.contains("YouTube") ?? true)
        XCTAssertFalse(vm.currentIdleStarterDecision?.message?.contains("youtube.com") ?? true)
    }

    func testIdleStarterContextUsesPersistedDomainEntriesWhenRawDomainCaptureEnabled() throws {
        let container = try makeInMemoryContainer()
        let vm = TimerViewModel()
        vm.configure(modelContext: container.mainContext)
        defer { AppUsageTracker.shared.stop() }

        let settings = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<AppSettings>()).first)
        settings.antiProcrastinationEnabled = true
        settings.coachIdleStarterEnabled = true
        settings.coachAutoOpenPopoverOnStrongPrompt = false
        settings.coachBringAppToFrontOnStrongPrompt = false
        settings.coachInterventionMode = .balanced
        settings.coachCollectRawDomains = true

        container.mainContext.insert(
            AppUsageEntry(
                date: Calendar.current.startOfDay(for: Date()),
                appName: "YouTube",
                bundleIdentifier: "domain:youtube.com",
                duringFocusSeconds: 0,
                outsideFocusSeconds: 30 * 60
            )
        )
        try container.mainContext.save()

        vm.lastProjectSelectedAt = Date()
        vm.evaluateIdleStarterIntervention(
            idleSeconds: 10 * 60,
            escalationLevel: 2,
            frontmostCategory: .productive
        )

        let context = try XCTUnwrap(vm.currentIdleStarterDecision?.context)
        XCTAssertEqual(context.suggestedBlockTarget, "youtube.com")
        XCTAssertEqual(context.topDistractingAppName, "YouTube")
        XCTAssertEqual(context.topDistractingAppMinutes, 30)
        XCTAssertTrue(context.blockRecommendationReason?.contains("YouTube") ?? false)
        XCTAssertTrue(vm.currentIdleStarterDecision?.message?.contains("YouTube") ?? false)
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

    // MARK: - Pause Break (spec: break state controls must include Pause break)

    func testPauseBreakSetsPausedFlagAndDoesNotChangeState() throws {
        let container = try makeInMemoryContainer()
        let vm = TimerViewModel()
        vm.configure(modelContext: container.mainContext)
        defer { AppUsageTracker.shared.stop() }

        vm.state = .onBreak(.shortBreak)
        vm.remainingSeconds = 240

        vm.pauseBreak()

        XCTAssertTrue(vm.isBreakPaused, "pauseBreak should set isBreakPaused = true")
        XCTAssertEqual(vm.state, .onBreak(.shortBreak), "state should remain onBreak")
        XCTAssertEqual(vm.remainingSeconds, 240, "remaining seconds should be frozen at pause point")
    }

    func testResumeBreakClearsPausedFlagAndRestoresState() throws {
        let container = try makeInMemoryContainer()
        let vm = TimerViewModel()
        vm.configure(modelContext: container.mainContext)
        defer { AppUsageTracker.shared.stop() }

        vm.state = .onBreak(.shortBreak)
        vm.remainingSeconds = 180
        vm.pauseBreak()
        XCTAssertTrue(vm.isBreakPaused)

        vm.resumeBreak()

        XCTAssertFalse(vm.isBreakPaused, "resumeBreak should clear isBreakPaused")
        XCTAssertEqual(vm.state, .onBreak(.shortBreak), "state should remain onBreak after resume")
        XCTAssertEqual(vm.remainingSeconds, 180, "remaining seconds should resume from frozen value")
    }

    func testPauseBreakOutsideBreakStateIsNoOp() throws {
        let container = try makeInMemoryContainer()
        let vm = TimerViewModel()
        vm.configure(modelContext: container.mainContext)
        defer { AppUsageTracker.shared.stop() }

        vm.state = .idle
        vm.pauseBreak()

        XCTAssertFalse(vm.isBreakPaused, "pauseBreak should be no-op when not in break state")
    }

    func testStopClearsBreakPausedFlag() throws {
        let container = try makeInMemoryContainer()
        let vm = TimerViewModel()
        vm.configure(modelContext: container.mainContext)
        defer { AppUsageTracker.shared.stop() }

        vm.state = .onBreak(.shortBreak)
        vm.pauseBreak()
        XCTAssertTrue(vm.isBreakPaused)

        vm.stop()

        XCTAssertFalse(vm.isBreakPaused, "stop() should clear isBreakPaused")
    }

    // MARK: - Pause time exclusion from session duration (bug fix)

    /// Regression: actualDuration must exclude time spent paused.
    func testActualDurationExcludesPausedSeconds() throws {
        let session = FocusSession(type: .focus, duration: 1800)
        let wallElapsed: TimeInterval = 2400 // 40 min wall clock
        let pausedSeconds: TimeInterval = 600  // 10 min paused

        session.startedAt = Date().addingTimeInterval(-wallElapsed)
        session.endedAt   = Date()
        session.completed = true
        session.totalPausedSeconds = pausedSeconds

        // Active focus = 40 min - 10 min = 30 min
        XCTAssertEqual(session.actualDuration, wallElapsed - pausedSeconds, accuracy: 1,
                       "actualDuration should subtract totalPausedSeconds from wall-clock elapsed")
    }

    /// Regression: actualDuration must not go negative even with extreme pause values.
    func testActualDurationClampedToZeroWhenPausedExceedsElapsed() throws {
        let session = FocusSession(type: .focus, duration: 600)
        session.startedAt = Date().addingTimeInterval(-300)
        session.endedAt = Date()
        session.completed = false
        session.totalPausedSeconds = 1000 // more than elapsed — should clamp to 0

        XCTAssertGreaterThanOrEqual(session.actualDuration, 0,
                                    "actualDuration must never be negative")
    }

    /// Regression: sessions with zero paused seconds should behave identically to before.
    func testActualDurationWithNoPauseUnchanged() throws {
        let elapsed: TimeInterval = 1500
        let session = FocusSession(type: .focus, duration: 1500)
        session.startedAt = Date().addingTimeInterval(-elapsed)
        session.endedAt = Date()
        session.completed = true
        session.totalPausedSeconds = 0

        XCTAssertEqual(session.actualDuration, elapsed, accuracy: 1,
                       "actualDuration with no pause should equal wall-clock elapsed")
    }

    /// Regression: resume() must accumulate the pause interval into totalPausedSeconds.
    func testResumeAccumulatesPauseIntoSession() throws {
        let container = try makeInMemoryContainer()
        let vm = TimerViewModel()
        vm.configure(modelContext: container.mainContext)
        defer { AppUsageTracker.shared.stop() }

        vm.startFocus()
        // Simulate a 5-minute pause by back-dating pauseStartTime
        vm.pause()
        vm.pauseStartTime = Date().addingTimeInterval(-300) // pretend paused 5 min ago

        vm.resume()

        let sessions = try container.mainContext.fetch(FetchDescriptor<FocusSession>())
        let session = try XCTUnwrap(sessions.first)
        XCTAssertGreaterThanOrEqual(session.totalPausedSeconds, 299,
                                    "resume() should commit ~5 min of pause time into session")
    }

    /// Regression: stop() while paused must also commit in-flight pause time.
    func testStopWhilePausedAccumulatesPauseIntoSession() throws {
        let container = try makeInMemoryContainer()
        let vm = TimerViewModel()
        vm.configure(modelContext: container.mainContext)
        defer { AppUsageTracker.shared.stop() }

        vm.startFocus()
        // Back-date startedAt so the session passes the minimum-retention check
        let sessions = try container.mainContext.fetch(FetchDescriptor<FocusSession>())
        if let session = sessions.first {
            session.startedAt = Date().addingTimeInterval(-600)
            try container.mainContext.save()
        }

        vm.pause()
        vm.pauseStartTime = Date().addingTimeInterval(-180) // 3 min in-flight pause

        vm.stop()

        // After stop the session record should have accumulated pause time
        let updatedSessions = try container.mainContext.fetch(FetchDescriptor<FocusSession>())
        if let saved = updatedSessions.first {
            XCTAssertGreaterThanOrEqual(saved.totalPausedSeconds, 179,
                                        "stop() while paused should commit in-flight pause time into the session")
        }
        // State machine should be idle regardless
        XCTAssertEqual(vm.state, .idle)
    }

    /// Regression: loadTodayStats() must use actualDuration (pause-excluded) not wall-clock overlap.
    func testLoadTodayStatsExcludesPauseTime() throws {
        let container = try makeInMemoryContainer()
        let vm = TimerViewModel()
        vm.configure(modelContext: container.mainContext)
        defer { AppUsageTracker.shared.stop() }

        // Manually insert a session with 30 min wall-clock, 10 min paused → 20 min active
        let session = FocusSession(type: .focus, duration: 1800)
        session.startedAt = Calendar.current.startOfDay(for: Date()).addingTimeInterval(3600) // 1h after midnight
        session.endedAt   = session.startedAt.addingTimeInterval(1800) // 30 min wall-clock
        session.completed = true
        session.totalPausedSeconds = 600 // 10 min paused

        container.mainContext.insert(session)
        try container.mainContext.save()

        vm.loadTodayStats()

        // todayFocusTime should reflect ~20 min, NOT 30 min
        XCTAssertEqual(vm.todayFocusTime, 1200, accuracy: 5,
                       "loadTodayStats should exclude paused seconds from the daily focus total")
    }

    // MARK: - Bug regression: switchProject while paused commits pause to correct session

    /// Regression: switchProject() must commit in-flight pause time to the OLD session,
    /// not the newly created session.
    func testSwitchProjectWhilePausedAccumulatesPauseToCorrectSession() throws {
        let container = try makeInMemoryContainer()
        let vm = TimerViewModel()
        vm.configure(modelContext: container.mainContext)
        defer { AppUsageTracker.shared.stop() }

        vm.startFocus()

        // Ensure enough elapsed time so the old session passes the minimum-retention check (>= 5 min)
        let oldTotalSeconds = vm.totalSeconds
        vm.remainingSeconds = oldTotalSeconds - 360 // 6 min elapsed

        vm.pause()
        // Back-date pauseStartTime so there's ~5 min of in-flight pause time
        vm.pauseStartTime = Date().addingTimeInterval(-300)

        // Create a project to switch to
        let newProject = Project(name: "Switched Project")
        container.mainContext.insert(newProject)
        try container.mainContext.save()

        vm.switchProject(to: newProject, reason: .requiredSwitch)

        // Fetch all sessions — should be 2 (old + new)
        let allSessions = try container.mainContext.fetch(FetchDescriptor<FocusSession>())
        let oldSession = allSessions.first(where: { $0.endedAt != nil })
        let newSession = allSessions.first(where: { $0.endedAt == nil })

        let old = try XCTUnwrap(oldSession, "Old session should exist (endedAt set)")
        let new = try XCTUnwrap(newSession, "New session should exist (endedAt nil)")

        // Old session must have accumulated the in-flight pause time
        XCTAssertGreaterThanOrEqual(old.totalPausedSeconds, 299,
                                    "Old session must accumulate in-flight pause time from switchProject")

        // New session must NOT have any pause time stolen from the old session
        XCTAssertEqual(new.totalPausedSeconds, 0,
                       "New session must not have pause time from the old session")
    }

    // MARK: - Bug regression: wake recovery keepOvertime excludes sleep from duration

    /// Regression: resolveWakeRecovery(.keepOvertime) must add sleep duration to
    /// totalPausedSeconds so actualDuration excludes the sleep period.
    func testWakeRecoveryKeepOvertimeExcludesSleepFromActualDuration() throws {
        let container = try makeInMemoryContainer()
        let vm = TimerViewModel()
        vm.configure(modelContext: container.mainContext)
        defer { AppUsageTracker.shared.stop() }

        // Create a session that ran for 1 hour wall-clock with 30 min of sleep
        let session = FocusSession(type: .focus, duration: 3600)
        session.startedAt = Date().addingTimeInterval(-3600) // 1 hour ago
        session.endedAt = nil
        container.mainContext.insert(session)
        try container.mainContext.save()

        // Setup wake recovery state
        vm.wakeRecoverySession = session
        vm.wakeRecoverySleepStartTime = session.startedAt.addingTimeInterval(1800) // fell asleep 30 min in
        vm.wakeRecoveryWakeTime = Date()
        vm.wakeRecoveryWasOvertime = false
        vm.showWakeRecoveryPrompt = true // makes isWakeRecoveryActive true

        vm.resolveWakeRecovery(choice: .keepOvertime)

        // Session should be ended and completed
        XCTAssertTrue(session.completed)
        XCTAssertNotNil(session.endedAt)

        // Sleep duration is ~30 min = 1800 seconds
        XCTAssertEqual(session.totalPausedSeconds, 1800, accuracy: 5,
                       "totalPausedSeconds should include the sleep duration")

        // actualDuration = wall-clock elapsed minus sleep = 3600 - 1800 = 1800 (30 min active)
        XCTAssertEqual(session.actualDuration, 1800, accuracy: 5,
                       "actualDuration should exclude the sleep period")
    }

    // MARK: - Pause count and pause label model tests

    /// New session must have zero pause count.
    func testNewSessionHasZeroPauseCount() {
        let session = FocusSession(type: .focus, duration: 1800)
        XCTAssertEqual(session.pauseCount, 0)
        XCTAssertEqual(session.totalPausedSeconds, 0)
        XCTAssertNil(session.pauseLabel)
    }

    /// pauseLabel formats correctly with multiple pauses.
    func testPauseLabelFormatsMultiplePauses() {
        let session = FocusSession(type: .focus, duration: 1800)
        session.startedAt = Date().addingTimeInterval(-2400) // 40 min ago
        session.endedAt = Date()
        session.completed = true
        session.pauseCount = 3
        session.totalPausedSeconds = 600 // 10 min paused
        // actualDuration = 2400 - 600 = 1800 = 30m
        XCTAssertEqual(session.pauseLabel, "30m focus · 3 pauses · 10m paused")
    }

    /// pauseLabel uses singular "pause" for count of 1.
    func testPauseLabelFormatsSinglePause() {
        let session = FocusSession(type: .focus, duration: 1800)
        session.startedAt = Date().addingTimeInterval(-1800) // 30 min ago
        session.endedAt = Date()
        session.completed = true
        session.pauseCount = 1
        session.totalPausedSeconds = 120 // 2 min paused
        // actualDuration = 1800 - 120 = 1680 = 28m
        XCTAssertEqual(session.pauseLabel, "28m focus · 1 pause · 2m paused")
    }

    /// pauseLabel returns nil when only count is set but no time (edge case).
    func testPauseLabelNilWhenNoPauseTime() {
        let session = FocusSession(type: .focus, duration: 1800)
        session.pauseCount = 0
        session.totalPausedSeconds = 0
        XCTAssertNil(session.pauseLabel)
    }

    /// resume() must also set pauseCount on the session.
    func testResumeSetsPauseCountOnSession() throws {
        let container = try makeInMemoryContainer()
        let vm = TimerViewModel()
        vm.configure(modelContext: container.mainContext)
        defer { AppUsageTracker.shared.stop() }

        vm.startFocus()
        vm.pause()
        vm.pauseStartTime = Date().addingTimeInterval(-60) // 1 min pause

        vm.resume()

        let sessions = try container.mainContext.fetch(FetchDescriptor<FocusSession>())
        let session = try XCTUnwrap(sessions.first)
        XCTAssertGreaterThanOrEqual(session.pauseCount, 1,
                                    "resume() should set pauseCount >= 1 on the session")
        XCTAssertEqual(session.pauseCount, 1,
                       "resume() should set pauseCount to 1 after one pause cycle")
    }

    /// stop() while paused must also set pauseCount.
    func testStopWhilePausedSetsPauseCount() throws {
        let container = try makeInMemoryContainer()
        let vm = TimerViewModel()
        vm.configure(modelContext: container.mainContext)
        defer { AppUsageTracker.shared.stop() }

        vm.startFocus()
        // Back-date startedAt so the session passes the minimum-retention check
        let sessions = try container.mainContext.fetch(FetchDescriptor<FocusSession>())
        if let session = sessions.first {
            session.startedAt = Date().addingTimeInterval(-600)
            try container.mainContext.save()
        }

        vm.pause()
        vm.pauseStartTime = Date().addingTimeInterval(-60) // 1 min pause

        vm.stop()

        let updatedSessions = try container.mainContext.fetch(FetchDescriptor<FocusSession>())
        if let saved = updatedSessions.first {
            XCTAssertGreaterThanOrEqual(saved.pauseCount, 1,
                                        "stop() while paused should set pauseCount >= 1")
        }
    }

    /// switchProject() must set pauseCount on the old session, not the new one.
    func testSwitchProjectSetsPauseCountOnCorrectSession() throws {
        let container = try makeInMemoryContainer()
        let vm = TimerViewModel()
        vm.configure(modelContext: container.mainContext)
        defer { AppUsageTracker.shared.stop() }

        vm.startFocus()
        let oldTotalSeconds = vm.totalSeconds
        vm.remainingSeconds = oldTotalSeconds - 360 // 6 min elapsed

        vm.pause()
        vm.pauseStartTime = Date().addingTimeInterval(-300)

        let newProject = Project(name: "Switched Project")
        container.mainContext.insert(newProject)
        try container.mainContext.save()

        vm.switchProject(to: newProject, reason: .requiredSwitch)

        let allSessions = try container.mainContext.fetch(FetchDescriptor<FocusSession>())
        let oldSession = allSessions.first(where: { $0.endedAt != nil })
        let newSession = allSessions.first(where: { $0.endedAt == nil })

        let old = try XCTUnwrap(oldSession)
        let new = try XCTUnwrap(newSession)

        // Old session must have the pause count
        XCTAssertGreaterThanOrEqual(old.pauseCount, 1,
                                    "Old session must have pauseCount set from switchProject")
        // New session must have zero pause count
        XCTAssertEqual(new.pauseCount, 0,
                       "New session must not inherit pause count from old session")
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
            BreakLearningEvent.self,
            IdleDistractionItem.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: config)
    }
}
