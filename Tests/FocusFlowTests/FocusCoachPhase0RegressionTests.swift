import XCTest
import SwiftData
import UserNotifications
@testable import FocusFlow

/// Regression tests for audit bugs B1–B5 and Coach v2 Phase 0
/// (docs/audits/2026-10-17-focus-coach-settings-audit.md §2,
///  docs/plans/2026-10-17-coach-v2-learning-motivation-design.md §1, §5).
@MainActor
final class FocusCoachPhase0RegressionTests: XCTestCase {

    // MARK: - B1: in-session rescue keeps the session

    func testInSessionRescueSavesRunningSessionInsteadOfDeletingIt() throws {
        let container = try makeInMemoryContainer()
        let vm = TimerViewModel()
        vm.configure(modelContext: container.mainContext)
        defer { AppUsageTracker.shared.stop() }

        vm.selectedMinutes = 25
        XCTAssertTrue(vm.startFocus())
        let original = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<FocusSession>()).first)
        let originalId = original.id
        original.startedAt = Date().addingTimeInterval(-22 * 60)
        try container.mainContext.save()

        XCTAssertTrue(vm.handleCoachAction(.cleanRestart5m))

        let sessions = try container.mainContext.fetch(FetchDescriptor<FocusSession>())
        let saved = try XCTUnwrap(sessions.first { $0.id == originalId }, "22 minutes of focus must not be deleted")
        XCTAssertNotNil(saved.endedAt)
        XCTAssertFalse(saved.completed)
        let rescue = try XCTUnwrap(sessions.first { $0.id != originalId })
        XCTAssertEqual(rescue.duration, 5 * 60)
        XCTAssertEqual(vm.state, .focusing)
        XCTAssertEqual(vm.selectedMinutes, 25, "The rescue block must not change the user's chosen duration")
    }

    func testBackToWorkKeepsSessionRunning() throws {
        let container = try makeInMemoryContainer()
        let vm = TimerViewModel()
        vm.configure(modelContext: container.mainContext)
        defer { AppUsageTracker.shared.stop() }

        XCTAssertTrue(vm.startFocus())
        vm.pause()
        XCTAssertTrue(vm.handleCoachAction(.returnNow))

        XCTAssertEqual(vm.state, .focusing)
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<FocusSession>()).count, 1)
    }

    // MARK: - B2: snooze duration is honoured

    func testSnoozeKeepsRequestedDurationWhenAnAttemptExists() {
        let engine = FocusCoachEngine(store: InMemoryCoachStore())
        engine.recordDeliveredIntervention(kind: .strongPrompt)

        let before = Date()
        engine.snooze(minutes: 120)

        let until = try? XCTUnwrap(engine.promptState.snoozedUntil)
        XCTAssertEqual(until?.timeIntervalSince(before) ?? 0, 120 * 60, accuracy: 5)
    }

    func testOffForTodaySnoozeIsNotShortenedByOutcomeRecording() throws {
        let container = try makeInMemoryContainer()
        let vm = TimerViewModel()
        vm.configure(modelContext: container.mainContext)
        defer { AppUsageTracker.shared.stop() }

        vm.coachEngine.recordDeliveredIntervention(kind: .strongPrompt)
        let before = Date()
        vm.handleCoachAction(.markOffDuty)

        let until = try XCTUnwrap(vm.coachEngine.promptState.snoozedUntil)
        XCTAssertEqual(until.timeIntervalSince(before), 90 * 60, accuracy: 5)
    }

    func testLegitimateSkipReasonStillExtendsShortSnooze() {
        let engine = FocusCoachEngine(store: InMemoryCoachStore())
        engine.recordDeliveredIntervention(kind: .quickPrompt)

        let before = Date()
        engine.snooze(minutes: 10, skipReason: .inMeeting)

        let until = try? XCTUnwrap(engine.promptState.snoozedUntil)
        XCTAssertEqual(until?.timeIntervalSince(before) ?? 0, 20 * 60, accuracy: 5)
    }

    // MARK: - B3: outcomes land on the newest attempt (SwiftData store)

    func testOutcomeIsWrittenToNewestAttemptInSwiftDataStore() throws {
        let container = try makeInMemoryContainer()
        let store = SwiftDataCoachStore(modelContext: container.mainContext)
        let engine = FocusCoachEngine(store: store)
        let now = Date()

        engine.recordDeliveredIntervention(kind: .quickPrompt, now: now.addingTimeInterval(-3 * 3600))
        engine.recordDeliveredIntervention(kind: .quickPrompt, now: now.addingTimeInterval(-2 * 3600))
        engine.recordDeliveredIntervention(kind: .strongPrompt, now: now.addingTimeInterval(-60))

        engine.recordInterventionOutcome(.snoozed, skipReason: .urgentTask)

        // Read back through a fresh context to prove the change was saved.
        let attempts = try ModelContext(container).fetch(
            FetchDescriptor<InterventionAttempt>(sortBy: [SortDescriptor(\.deliveredAt)])
        )
        XCTAssertEqual(attempts.count, 3)
        XCTAssertNil(attempts[0].outcome, "Oldest attempt must not receive the outcome")
        XCTAssertNil(attempts[1].outcome)
        XCTAssertEqual(attempts[2].outcome, .snoozed)
        XCTAssertEqual(attempts[2].skipReason, .urgentTask)
        XCTAssertNotNil(attempts[2].resolvedAt)
    }

    func testOutcomeAfterRelaunchResolvesNewestPersistedAttempt() throws {
        let container = try makeInMemoryContainer()
        let store = SwiftDataCoachStore(modelContext: container.mainContext)
        let firstRun = FocusCoachEngine(store: store)
        let now = Date()
        firstRun.recordDeliveredIntervention(kind: .quickPrompt, now: now.addingTimeInterval(-7200))
        firstRun.recordDeliveredIntervention(kind: .strongPrompt, now: now.addingTimeInterval(-30))

        let relaunched = FocusCoachEngine(store: SwiftDataCoachStore(modelContext: container.mainContext))
        relaunched.recordInterventionOutcome(.improved)

        let newest = try XCTUnwrap(store.attempts.first)
        XCTAssertEqual(newest.kind, .strongPrompt)
        XCTAssertEqual(newest.outcome, .improved)
        XCTAssertNil(store.attempts.last?.outcome)
    }

    func testSecondOutcomeDoesNotOverwriteResolvedAttempt() throws {
        let container = try makeInMemoryContainer()
        let engine = FocusCoachEngine(store: SwiftDataCoachStore(modelContext: container.mainContext))
        engine.recordDeliveredIntervention(kind: .quickPrompt)

        engine.recordInterventionOutcome(.improved)
        engine.recordInterventionOutcome(.dismissed)

        XCTAssertEqual(engine.store.attempts.first?.outcome, .improved)
    }

    // MARK: - B4: actionable notifications

    func testCoachNotificationResponseMapping() {
        let category = CoachNotificationResponse.categoryIdentifier
        XCTAssertEqual(
            CoachNotificationResponse(categoryIdentifier: category, actionIdentifier: CoachNotificationResponse.startActionIdentifier),
            .startFocus
        )
        XCTAssertEqual(
            CoachNotificationResponse(categoryIdentifier: category, actionIdentifier: CoachNotificationResponse.snoozeActionIdentifier),
            .snooze
        )
        XCTAssertEqual(
            CoachNotificationResponse(categoryIdentifier: category, actionIdentifier: UNNotificationDefaultActionIdentifier),
            .open
        )
        XCTAssertNil(CoachNotificationResponse(categoryIdentifier: category, actionIdentifier: UNNotificationDismissActionIdentifier))
        XCTAssertNil(CoachNotificationResponse(categoryIdentifier: "other", actionIdentifier: CoachNotificationResponse.startActionIdentifier))
    }

    func testCoachCategoryOffersStartAndSnoozeActions() {
        let category = NotificationService.coachCheckInCategory
        XCTAssertEqual(category.identifier, CoachNotificationResponse.categoryIdentifier)
        XCTAssertEqual(
            category.actions.map(\.identifier),
            [CoachNotificationResponse.startActionIdentifier, CoachNotificationResponse.snoozeActionIdentifier]
        )
    }

    func testNotificationStartActionStartsSessionAndLabelsAttempt() throws {
        let container = try makeInMemoryContainer()
        let vm = TimerViewModel()
        vm.configure(modelContext: container.mainContext)
        defer { AppUsageTracker.shared.stop() }

        vm.coachEngine.recordDeliveredIntervention(kind: .softNudge)
        NotificationService.shared.handleCoachNotificationResponse(.startFocus)

        XCTAssertEqual(vm.state, .focusing)
        XCTAssertEqual(vm.coachEngine.store.attempts.first?.outcome, .improved)
    }

    func testNotificationSnoozeActionSnoozesCoach() throws {
        let container = try makeInMemoryContainer()
        let vm = TimerViewModel()
        vm.configure(modelContext: container.mainContext)
        defer { AppUsageTracker.shared.stop() }

        vm.coachEngine.recordDeliveredIntervention(kind: .softNudge)
        NotificationService.shared.handleCoachNotificationResponse(.snooze)

        XCTAssertEqual(vm.state, .idle)
        XCTAssertNotNil(vm.coachEngine.promptState.snoozedUntil)
        XCTAssertEqual(vm.coachEngine.store.attempts.first?.outcome, .snoozed)
    }

    // MARK: - B5: start failures are visible

    func testRefusedStartKeepsPromptOpenAndReportsError() throws {
        let container = try makeInMemoryContainer()
        let vm = TimerViewModel()
        vm.configure(modelContext: container.mainContext)
        defer { AppUsageTracker.shared.stop() }

        var popoverCloseRequests = 0
        vm.onPopoverCloseRequested = { popoverCloseRequests += 1 }
        vm.isOvertime = true
        let prompt = FocusCoachDecision(kind: .quickPrompt, suggestedActions: [.startFocusNow], message: "Start?")
        vm.currentIdleStarterDecision = prompt
        vm.coachEngine.recordDeliveredIntervention(kind: .quickPrompt)

        XCTAssertFalse(vm.startFocus())
        XCTAssertFalse(vm.handleCoachAction(.startFocusNow))

        XCTAssertNotNil(vm.startError)
        XCTAssertEqual(popoverCloseRequests, 0, "The surface showing the error must stay open")
        XCTAssertNotNil(vm.currentIdleStarterDecision, "The start prompt must stay so the user can retry")
        XCTAssertNil(vm.coachEngine.store.attempts.first?.outcome, "A failed start is not an 'improved' outcome")
    }

    // MARK: - Phase 0: daily cap and strong-window spacing

    func testGuardrailsAllowThreePromptsPerDay() {
        let guardrails = CoachGuardrails()
        let now = Date()
        let calendar = Calendar.current
        let earlierToday = max(calendar.startOfDay(for: now), now.addingTimeInterval(-6 * 3600))
        func input(_ count: Int) -> CoachGuardrails.Input {
            CoachGuardrails.Input(
                now: now,
                deliveries: (0..<count).map { _ in .init(surface: .badge, deliveredAt: earlierToday) },
                quietStartMinute: 0,
                quietEndMinute: 0
            )
        }

        XCTAssertEqual(guardrails.verdict(for: .badge, input: input(2)), .allowed)
        XCTAssertEqual(guardrails.verdict(for: .badge, input: input(3)), .dailyCapReached)
        XCTAssertEqual(guardrails.verdict(for: .notification, input: input(3)), .dailyCapReached)
        XCTAssertEqual(guardrails.verdict(for: .silent, input: input(3)), .allowed, "Silence is never capped")
    }

    func testGuardrailsIgnoreYesterdaysPrompts() {
        let guardrails = CoachGuardrails()
        let now = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        let input = CoachGuardrails.Input(
            now: now,
            deliveries: (0..<5).map { _ in .init(surface: .panel, deliveredAt: yesterday) },
            quietStartMinute: 0,
            quietEndMinute: 0
        )

        XCTAssertEqual(guardrails.verdict(for: .badge, input: input), .allowed)
    }

    func testGuardrailsSpacePanelsByTwoHours() {
        let guardrails = CoachGuardrails()
        let now = Date()
        func input(minutesAgo: Double) -> CoachGuardrails.Input {
            CoachGuardrails.Input(
                now: now,
                deliveries: [.init(surface: .panel, deliveredAt: now.addingTimeInterval(-minutesAgo * 60))],
                quietStartMinute: 0,
                quietEndMinute: 0
            )
        }

        XCTAssertEqual(guardrails.verdict(for: .panel, input: input(minutesAgo: 90)), .panelTooSoon)
        XCTAssertEqual(guardrails.verdict(for: .badge, input: input(minutesAgo: 90)), .allowed)
        XCTAssertEqual(guardrails.verdict(for: .panel, input: input(minutesAgo: 121)), .allowed)
    }

    func testLegacyStrongPromptRowsCountAsPanelsForSpacing() {
        let attempt = InterventionAttempt(kind: .strongPrompt, riskScore: 0.5)
        XCTAssertEqual(CoachGuardrails.Delivery(attempt: attempt).surface, .strongWindow)
        let quick = InterventionAttempt(kind: .quickPrompt, riskScore: 0.5)
        XCTAssertEqual(CoachGuardrails.Delivery(attempt: quick).surface, .badge)
    }

    func testIdleStarterRespectsDailyPromptCap() throws {
        let (container, vm) = try makeIdleStarterViewModel()
        _ = container
        defer { AppUsageTracker.shared.stop() }
        let now = Date()
        let earlierToday = max(Calendar.current.startOfDay(for: now), now.addingTimeInterval(-3 * 3600))
        for _ in 0..<3 {
            vm.coachEngine.recordDeliveredIntervention(kind: .quickPrompt, now: earlierToday)
        }

        vm.evaluateIdleStarterIntervention(idleSeconds: 10 * 60, frontmostCategory: .distracting)

        XCTAssertEqual(vm.lastIdleStarterSuppressionReason, .dailyPromptCapReached)
        XCTAssertNil(vm.currentIdleStarterDecision)
        XCTAssertFalse(vm.showCoachInterventionWindow)
        XCTAssertEqual(vm.coachEngine.store.attempts.count, 3, "No new prompt may be delivered")
    }

    func testIdleStarterSpacesPanels() throws {
        let (container, vm) = try makeIdleStarterViewModel()
        _ = container
        defer { AppUsageTracker.shared.stop() }
        vm.coachEngine.recordDeliveredIntervention(kind: .strongPrompt, now: Date().addingTimeInterval(-30 * 60))

        vm.evaluateIdleStarterIntervention(idleSeconds: 10 * 60, frontmostCategory: .distracting)

        XCTAssertNil(vm.coachPanel, "No second panel within 2 hours")
        XCTAssertNotEqual(vm.currentIdleStarterDecision?.kind, .strongPrompt)
    }

    func testIdleStarterStillPromptsUnderTheCap() throws {
        let (container, vm) = try makeIdleStarterViewModel()
        _ = container
        defer { AppUsageTracker.shared.stop() }

        vm.evaluateIdleStarterIntervention(idleSeconds: 10 * 60, frontmostCategory: .distracting)

        XCTAssertEqual(vm.currentIdleStarterDecision?.kind, .strongPrompt)
        XCTAssertEqual(vm.coachEngine.store.attempts.count, 1)
    }

    // MARK: - T3: calendar busy and next event

    func testIdleStarterSuppressedWhileCalendarIsBusy() throws {
        let (container, vm) = try makeIdleStarterViewModel()
        _ = container
        defer { AppUsageTracker.shared.stop() }
        vm.calendarAvailabilityProvider = { _ in CalendarAvailability(isBusyNow: true, minutesUntilNextEvent: nil) }

        vm.evaluateIdleStarterIntervention(idleSeconds: 10 * 60, frontmostCategory: .distracting)

        XCTAssertEqual(vm.lastIdleStarterSuppressionReason, .calendarBusy)
        XCTAssertNil(vm.currentIdleStarterDecision)
    }

    func testIdleStarterUsesNextCalendarEvent() throws {
        let (container, vm) = try makeIdleStarterViewModel()
        _ = container
        defer { AppUsageTracker.shared.stop() }
        vm.calendarAvailabilityProvider = { _ in CalendarAvailability(isBusyNow: false, minutesUntilNextEvent: 40) }

        vm.evaluateIdleStarterIntervention(idleSeconds: 10 * 60, frontmostCategory: .distracting)

        XCTAssertEqual(vm.currentIdleStarterDecision?.kind, .strongPrompt)
        // max(25, min(120 remaining, 50)) = 50, shortened to end 5 min before the event at +40.
        XCTAssertEqual(vm.idleStarterRecommendedMinutes, 35)
        XCTAssertEqual(vm.coachPanel?.plan?.minutes, 35)
        XCTAssertTrue(vm.coachPanel?.message.primaryTitle.hasPrefix("Start 35m") == true)
    }

    func testCalendarAvailabilityComputation() {
        let now = Date()
        let current = DateInterval(start: now.addingTimeInterval(-600), end: now.addingTimeInterval(600))
        let next = DateInterval(start: now.addingTimeInterval(45 * 60), end: now.addingTimeInterval(75 * 60))
        let past = DateInterval(start: now.addingTimeInterval(-7200), end: now.addingTimeInterval(-3600))

        XCTAssertEqual(
            CalendarAvailability.compute(busyIntervals: [current, next, past], now: now),
            CalendarAvailability(isBusyNow: true, minutesUntilNextEvent: 45)
        )
        XCTAssertEqual(
            CalendarAvailability.compute(busyIntervals: [past], now: now),
            CalendarAvailability(isBusyNow: false, minutesUntilNextEvent: nil)
        )
    }

    // MARK: - T4: "since your last focused block" uses the real session end

    func testSinceLastBlockCopyRequiresRealLastSessionTime() {
        func compose(_ minutesSince: Int?) -> CoachComposedMessage {
            var facts = CoachFacts()
            facts.goalMinutes = 120
            facts.hasHistory = true
            facts.missedYesterday = true
            facts.minutesSinceLastSession = minutesSince
            return CoachMessageComposer.compose(CoachComposerInput(
                style: .challenger,
                trigger: .startNudge,
                facts: facts,
                target: CoachStartTarget(minutes: 25, name: nil)
            ))
        }

        XCTAssertFalse(compose(nil).accessibilityText.contains("Last block"),
                       "Without a last-session time the coach must not claim time since the last block")
        XCTAssertEqual(compose(125).detail, .fact("Last block ended 2h 5m ago."))
    }

    func testCoachContextCarriesTimeSinceLastFocusSession() throws {
        let (container, vm) = try makeIdleStarterViewModel()
        defer { AppUsageTracker.shared.stop() }
        let session = FocusSession(type: .focus, duration: 25 * 60, project: nil)
        session.startedAt = Date().addingTimeInterval(-4 * 3600)
        session.endedAt = Date().addingTimeInterval(-3 * 3600)
        container.mainContext.insert(session)
        try container.mainContext.save()

        vm.evaluateIdleStarterIntervention(idleSeconds: 10 * 60, frontmostCategory: .distracting)

        let seconds = try XCTUnwrap(vm.currentIdleStarterDecision?.context?.secondsSinceLastFocusSession)
        XCTAssertEqual(Double(seconds), 3 * 3600, accuracy: 10)
    }

    // MARK: - W1 / W2: block recommendations

    func testWorkAndChatToolsAreNotDerailerTargets() {
        let tools: [(String, String)] = [
            ("com.tinyspeck.slackmacgap", "Slack"),
            ("com.anthropic.claudefordesktop", "Claude"),
            ("com.openai.chat", "ChatGPT"),
            ("com.hnc.Discord", "Discord"),
            ("ru.keepcoder.Telegram", "Telegram"),
            ("net.whatsapp.WhatsApp", "WhatsApp")
        ]
        for (bundleId, name) in tools {
            XCTAssertNil(
                AppUsageEntry.recommendedBlockTarget(bundleIdentifier: bundleId, appName: name),
                "\(name) must not be a hardcoded block target"
            )
        }
        XCTAssertEqual(AppUsageEntry.recommendedBlockTarget(bundleIdentifier: "domain:youtube.com", appName: "YouTube"), "youtube.com")
    }

    func testBlockRecommendationNeedsTwentyMinutesOfDistractingUse() {
        let advisor = FocusCoachGuardianAdvisor()
        let shortVisit = [AppUsageEntry(appName: "YouTube", bundleIdentifier: "domain:youtube.com", outsideFocusSeconds: 5 * 60)]
        let longVisit = [AppUsageEntry(appName: "YouTube", bundleIdentifier: "domain:youtube.com", outsideFocusSeconds: 25 * 60)]

        XCTAssertNil(advisor.recommendation(frontmostBundleId: "domain:youtube.com", frontmostAppName: "YouTube", entries: shortVisit, selectedProject: nil))
        let rec = advisor.recommendation(frontmostBundleId: "com.apple.Safari", frontmostAppName: "Safari", entries: longVisit, selectedProject: nil)
        XCTAssertEqual(rec?.target, "youtube.com")
        XCTAssertTrue(rec?.reason.contains("25m today") == true, rec?.reason ?? "nil")
    }

    func testBlockRecommendationNeverTargetsWorkSites() {
        let advisor = FocusCoachGuardianAdvisor()
        let workDay = [
            AppUsageEntry(appName: "github.com", bundleIdentifier: "domain:github.com", outsideFocusSeconds: 3 * 3600),
            AppUsageEntry(appName: "acme.atlassian.net", bundleIdentifier: "domain:acme.atlassian.net", outsideFocusSeconds: 2 * 3600),
            AppUsageEntry(appName: "Slack", bundleIdentifier: "com.tinyspeck.slackmacgap", outsideFocusSeconds: 4 * 3600)
        ]

        XCTAssertNil(advisor.recommendation(frontmostBundleId: "domain:github.com", frontmostAppName: "github.com", entries: workDay, selectedProject: nil))
    }

    // MARK: - W6: no auto-created distraction suggestions

    func testIgnoredPromptDoesNotCreateDistractionSuggestionAndKeepsExistingRows() throws {
        let (container, vm) = try makeIdleStarterViewModel()
        defer { AppUsageTracker.shared.stop() }
        let existing = IdleDistractionItem(
            key: "youtube.com",
            displayName: "YouTube",
            targetKind: .website,
            severity: .minor,
            source: .suggested,
            status: .pending,
            evidenceCount: 2
        )
        container.mainContext.insert(existing)
        try container.mainContext.save()
        AppUsageTracker.shared.testingSetFrontmostContext(bundleId: "com.atlassian.jira", appName: "Jira")

        vm.evaluateIdleStarterIntervention(idleSeconds: 20 * 60, frontmostCategory: .neutral)
        if let id = vm.coachPanel?.id { vm.coachPanelTimedOut(id: id) }
        vm.evaluateIdleStarterIntervention(idleSeconds: 40 * 60, frontmostCategory: .neutral)

        let items = try container.mainContext.fetch(FetchDescriptor<IdleDistractionItem>())
        XCTAssertEqual(items.map(\.key), ["youtube.com"], "Only the user's existing row may remain")
        XCTAssertEqual(items.first?.evidenceCount, 2)
    }

    // MARK: - Helpers

    private func makeIdleStarterViewModel() throws -> (ModelContainer, TimerViewModel) {
        let container = try makeInMemoryContainer()
        let vm = TimerViewModel()
        vm.configure(modelContext: container.mainContext)
        vm.calendarAvailabilityProvider = { _ in .unknown }

        let settings = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<AppSettings>()).first)
        settings.antiProcrastinationEnabled = true
        settings.coachIdleStarterEnabled = true
        settings.coachSuppressPopupsDuringScreenShare = false
        settings.coachInterventionMode = .balanced
        // Deterministic: quiet hours off, panel × challenger arm, no learned windows.
        settings.coachQuietStartMinute = 0
        settings.coachQuietEndMinute = 0
        try container.mainContext.save()
        vm.coachArmOverride = CoachArm(surface: .panel, style: .challenger)
        vm.availabilityModelOverride = .empty
        vm.lastProjectSelectedAt = Date()
        return (container, vm)
    }

    private func makeContext(idleSeconds: Int, secondsSinceLastFocusSession: Int?) -> FocusCoachContext {
        FocusCoachContext(
            idleSeconds: idleSeconds,
            frontmostAppName: "Finder",
            frontmostBundleIdentifier: "com.apple.finder",
            frontmostAppCategory: .neutral,
            isInActiveSession: false,
            todayFocusSeconds: 3600,
            dailyGoalSeconds: 7200,
            todaySessionCount: 2,
            selectedProjectName: nil,
            selectedWorkMode: nil,
            hourOfDay: 10,
            topDistractingAppName: nil,
            topDistractingAppMinutes: 0,
            recentLowPriorityWorkCount: 0,
            suggestedBlockTarget: nil,
            blockRecommendationReason: nil,
            inReleaseWindow: false,
            secondsSinceLastFocusSession: secondsSinceLastFocusSession
        )
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
