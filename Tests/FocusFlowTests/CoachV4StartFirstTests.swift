import XCTest
import SwiftData
@testable import FocusFlow

/// Coach v4: start first (docs/plans/2026-10-28-coach-v4-start-first-design.md).
@MainActor
final class CoachV4StartFirstTests: XCTestCase {
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

    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private func t(_ minutes: Double) -> Date { t0.addingTimeInterval(minutes * 60) }

    // MARK: §3.3 Size ladder

    func testLadderStartsAt15AndShrinksAfterTwoUnansweredAsks() {
        XCTAssertEqual(CoachBlockSizeLadder.recommend(events: []), .init(minutes: 15, why: .starting))
        let one = CoachBlockSizeLadder.recommend(events: [.init(at: t(0), kind: .declined(reason: nil))])
        XCTAssertEqual(one.minutes, 15, "One miss is not a pattern")
        let two = CoachBlockSizeLadder.recommend(events: [
            .init(at: t(0), kind: .declined(reason: nil)),
            .init(at: t(60), kind: .declined(reason: nil)),
        ])
        XCTAssertEqual(two, .init(minutes: 5, why: .shrunkAfterDeclines))
        XCTAssertTrue(two.caption.contains("didn't land"))
    }

    func testLadderActsOnTheReason() {
        let tooBig = CoachBlockSizeLadder.recommend(events: [.init(at: t(0), kind: .declined(reason: .taskTooBig))])
        XCTAssertEqual(tooBig, .init(minutes: 5, why: .tooBig))
        let unclear = CoachBlockSizeLadder.recommend(events: [.init(at: t(0), kind: .declined(reason: .unclearNextStep))])
        XCTAssertEqual(unclear.minutes, 5)
        XCTAssertTrue(unclear.findsNextStep)
        let busy = CoachBlockSizeLadder.recommend(events: [
            .init(at: t(0), kind: .declined(reason: .urgentTask)),
            .init(at: t(30), kind: .declined(reason: .justTired)),
            .init(at: t(60), kind: .declined(reason: .urgentTask)),
        ])
        XCTAssertEqual(busy.minutes, 15, "Busy or tired is a real reason, not a sign the ask was too big")
    }

    func testLadderFollowsStartsAndGrowsAfterThreeFinishedBlocks() {
        var events: [CoachBlockSizeLadder.Event] = [
            .init(at: t(0), kind: .declined(reason: .taskTooBig)),
            .init(at: t(10), kind: .startedFromPrompt(minutes: 5)),
        ]
        XCTAssertEqual(CoachBlockSizeLadder.recommend(events: events), .init(minutes: 5, why: .lastStart))
        events += [
            .init(at: t(15), kind: .blockEnded(minutes: 5, completed: true)),
            .init(at: t(100), kind: .blockEnded(minutes: 5, completed: true)),
        ]
        XCTAssertEqual(CoachBlockSizeLadder.recommend(events: events).minutes, 5)
        events.append(.init(at: t(200), kind: .blockEnded(minutes: 25, completed: true)))
        XCTAssertEqual(CoachBlockSizeLadder.recommend(events: events), .init(minutes: 15, why: .grew))
        // An abandoned block resets the run.
        events += [
            .init(at: t(300), kind: .blockEnded(minutes: 15, completed: true)),
            .init(at: t(400), kind: .blockEnded(minutes: 15, completed: false)),
            .init(at: t(500), kind: .blockEnded(minutes: 15, completed: true)),
            .init(at: t(600), kind: .blockEnded(minutes: 15, completed: true)),
        ]
        XCTAssertEqual(CoachBlockSizeLadder.recommend(events: events).minutes, 15)
        events.append(.init(at: t(700), kind: .blockEnded(minutes: 15, completed: true)))
        XCTAssertEqual(CoachBlockSizeLadder.recommend(events: events).minutes, 25, "Never above 25: the ask stays proximal")
        events += (0..<3).map { .init(at: t(800 + Double($0) * 60), kind: .blockEnded(minutes: 50, completed: true)) }
        XCTAssertEqual(CoachBlockSizeLadder.recommend(events: events).minutes, 25)
    }

    // MARK: §3.2 Presence

    func testArrivalFiresOnceWhenTheUserComesBackAfterTenMinutes() {
        var detector = CoachPresence.ArrivalDetector()
        XCTAssertFalse(detector.observe(systemIdleSeconds: 5))
        XCTAssertFalse(detector.observe(systemIdleSeconds: 300))
        XCTAssertFalse(detector.observe(systemIdleSeconds: 3))
        XCTAssertFalse(detector.observe(systemIdleSeconds: 200))
        XCTAssertFalse(detector.observe(systemIdleSeconds: 700))
        XCTAssertTrue(detector.observe(systemIdleSeconds: 2), "Back after 11+ minutes away")
        XCTAssertFalse(detector.observe(systemIdleSeconds: 1), "Only once")
        XCTAssertTrue(CoachPresence.isPresent(systemIdleSeconds: 89))
        XCTAssertFalse(CoachPresence.isPresent(systemIdleSeconds: 90))
    }

    // MARK: §3.4 Reasons

    func testDeclineResponses() {
        let calendar = Calendar.current
        let afternoon = calendar.date(bySettingHour: 15, minute: 0, second: 0, of: t0)!
        let night = calendar.date(bySettingHour: 22, minute: 30, second: 0, of: t0)!
        XCTAssertEqual(CoachDeclineResponse.action(for: .taskTooBig, now: afternoon), .counterOffer(minutes: 5, findNextStep: false))
        XCTAssertEqual(CoachDeclineResponse.action(for: .unclearNextStep, now: afternoon), .counterOffer(minutes: 5, findNextStep: true))
        XCTAssertEqual(CoachDeclineResponse.action(for: .urgentTask, now: afternoon), .quietUntil(afternoon.addingTimeInterval(3600)))
        XCTAssertEqual(CoachDeclineResponse.action(for: .justTired, now: afternoon), .quietUntil(afternoon.addingTimeInterval(3600)))
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: night))!
        XCTAssertEqual(CoachDeclineResponse.action(for: .justTired, now: night), .quietUntil(tomorrow), "Tired at night: done for tonight")
    }

    // MARK: §3.1 Attribution

    func testCreditGoesToTheLatestSeenPromptInTheLastTenMinutes() {
        func candidate(_ minutesBefore: Double, surface: CoachSurface? = .panel, outcome: FocusCoachOutcome? = nil, reward: Double? = nil, context: Bool = true) -> CoachPromptAttribution.Candidate {
            .init(id: UUID(), deliveredAt: t(-minutesBefore), surface: surface, outcome: outcome, reward: reward, hasContext: context)
        }
        let card = candidate(4, outcome: .snoozed)
        let candidates = [
            candidate(12),
            card,
            candidate(2, surface: .badge),
            candidate(1, outcome: .unseen),
            candidate(1.5, reward: 1),
            candidate(0.5, context: false),
        ]
        XCTAssertEqual(CoachPromptAttribution.creditTarget(for: t(0), candidates: candidates), card.id)
        XCTAssertNil(CoachPromptAttribution.creditTarget(for: t(0), candidates: [candidate(11)]))
        XCTAssertEqual(CoachPromptAttribution.label(contextKey: CoachPlannedCue.inviteContextKey, surface: .panel), "start card")
        XCTAssertEqual(CoachPromptAttribution.label(contextKey: "avail:low|idle:30-90|front:neutral|today:0|lvl:2|surf:panel", surface: .panel), "rescue (L2)")
    }

    // MARK: §3.2 Guardrails

    func testAnUnseenPanelDoesNotStartThePanelSpacing() {
        let guardrails = CoachGuardrails()
        var input = CoachGuardrails.Input(now: t(30), quietStartMinute: 0, quietEndMinute: 0)
        input.deliveries = [.init(surface: .panel, deliveredAt: t(0), countsTowardCap: false, wasSeen: false)]
        XCTAssertEqual(guardrails.verdict(for: .panel, input: input), .allowed)
        input.deliveries = [.init(surface: .panel, deliveredAt: t(0))]
        XCTAssertEqual(guardrails.verdict(for: .panel, input: input), .panelTooSoon)
    }

    // MARK: Copy

    func testStartCardAndCounterOfferCopy() {
        func compose(_ trigger: CoachTrigger, target: CoachStartTarget, sessionsToday: Int = 0) -> CoachComposedMessage {
            var facts = CoachFacts()
            facts.sessionsToday = sessionsToday
            facts.goalMinutes = 120
            return CoachMessageComposer.compose(CoachComposerInput(style: .challenger, trigger: trigger, facts: facts, target: target))
        }
        let target = CoachStartTarget(minutes: 15, name: "SQL prep")
        let first = compose(.dailyPlan(goalMinutes: 120, firstSuggestion: nil), target: target)
        XCTAssertEqual(first.hook, "First block. Start small.")
        XCTAssertEqual(first.primaryTitle, "Start 15m on SQL prep")
        XCTAssertFalse(first.accessibilityText.contains("2h"), "Never the day's goal")
        XCTAssertEqual(compose(.dailyPlan(goalMinutes: 120, firstSuggestion: nil), target: target, sessionsToday: 2).hook, "Next block. Small is fine.")

        var small = target
        small.minutes = 5
        XCTAssertEqual(compose(.counterOffer(reason: .taskTooBig), target: small).hook, "Too big? Then 5 minutes. Just open it.")
        small.findNextStep = true
        let unclear = compose(.counterOffer(reason: .unclearNextStep), target: small)
        XCTAssertEqual(unclear.hook, "No next step? Spend 5 minutes finding it.")
        XCTAssertEqual(unclear.primaryTitle, "Find the next step · 5m")
    }

    /// Screen audit 2026-10-28: "start small" once (the hook); the detail names the next task;
    /// no caption for the default size; the eyebrow names the plan; the button names the task.
    func testStartCardSaysStartSmallOnceAndNamesTheTask() {
        var facts = CoachFacts()
        facts.goalMinutes = 120
        let target = CoachStartTarget(minutes: 15, name: "SQL prep", taskTitle: "Window functions practice set", rank: 1)
        let card = CoachMessageComposer.compose(CoachComposerInput(
            style: .challenger, trigger: .dailyPlan(goalMinutes: 120, firstSuggestion: nil), facts: facts, target: target,
            pickedDetail: .houseLine("Starting is the whole game. 5 minutes counts.")
        ))
        XCTAssertEqual(card.hook, "First block. Start small.")
        XCTAssertEqual(card.detail, .line("Next: Window functions practice set"))
        XCTAssertNil(card.motivation, "A house line only when there is no task or lever")
        XCTAssertEqual(card.eyebrow, "#1 · SQL PREP")
        XCTAssertEqual(card.primaryTitle, "Start 15m · Window functions practi…", "The task, never the project")
        let smallCount = card.accessibilityText.lowercased().components(separatedBy: "small").count - 1
        XCTAssertEqual(smallCount, 1)

        var bare = target
        bare.taskTitle = nil
        let bareCard = CoachMessageComposer.compose(CoachComposerInput(
            style: .challenger, trigger: .dailyPlan(goalMinutes: 120, firstSuggestion: nil), facts: facts, target: bare,
            pickedDetail: .houseLine("Starting is the whole game. 5 minutes counts.")
        ))
        XCTAssertNil(bareCard.detail)
        XCTAssertEqual(bareCard.motivation, .houseLine("Starting is the whole game. 5 minutes counts."))
        XCTAssertEqual(bareCard.primaryTitle, "Start 15m on SQL prep")

        // A goal fact wins the eyebrow.
        facts.goal = CoachGoalFact(goalTitle: "Interview goal", resultTitle: "SQL", done: 4, target: 20, behind: 3, daysLeft: 9)
        let behind = CoachMessageComposer.compose(CoachComposerInput(style: .gentle, trigger: .startNudge, facts: facts, target: target))
        XCTAssertEqual(behind.eyebrow, "INTERVIEW GOAL · BEHIND")
        XCTAssertEqual(behind.detail, .line("Next: Window functions practice set"))
        XCTAssertNil(CoachMessageComposer.compose(CoachComposerInput(style: .gentle, trigger: .momentum, facts: facts, target: target)).eyebrow)

        // The default size has no caption on the panel; real reasons keep theirs.
        let starting = CoachBlockSizeLadder.Recommendation(minutes: 15, why: .starting)
        XCTAssertNil(starting.panelCaption)
        XCTAssertNil(CoachPanelPresentation(kind: .dailyPlan, message: card, sizeOptions: [5, 15, 25], sizeCaption: starting.caption).sizeCaption)
        let tooBig = CoachBlockSizeLadder.Recommendation(minutes: 5, why: .tooBig)
        XCTAssertEqual(CoachPanelPresentation(kind: .dailyPlan, message: card, sizeOptions: [5, 15, 25], sizeCaption: tooBig.caption).sizeCaption, tooBig.caption)

        // One vocabulary for the decline menu.
        XCTAssertEqual(CoachPanelPresentation(kind: .pseudoProductivity, message: card).menuTitle, "Not now")

        // The neutral fallback names the target when known.
        XCTAssertEqual(CoachMessageComposer.neutralFallback(isInSession: false).primaryTitle, "Start focus")
        let named = CoachMessageComposer.neutralFallback(isInSession: false, target: target)
        XCTAssertEqual(named.hook, "Ready for Window functions practi…?")
        XCTAssertEqual(named.primaryTitle, "Start 15m · Window functions practi…")
    }

    // MARK: End to end

    func testStartCardOffersSizesAndAPopoverStartCreditsIt() throws {
        let vm = try makeViewModel()
        let now = Date()
        XCTAssertTrue(vm.evaluateDailyPlanInvite(now: now))
        let card = try XCTUnwrap(vm.coachPanel)
        XCTAssertEqual(card.kind, .dailyPlan)
        XCTAssertEqual(card.sizeOptions, [5, 15, 25])
        XCTAssertEqual(card.recommendedMinutes, 15)
        XCTAssertFalse(card.hasPrimary, "The pills are the primary")
        XCTAssertEqual(card.reasonActions, CoachPanelSecondaryAction.reasons)
        let attemptID = try XCTUnwrap(card.attemptID)

        // The user ignores the card and starts 25 minutes from the popover a minute later.
        XCTAssertTrue(vm.startNextBlock(minutes: 25))
        XCTAssertEqual(vm.state, .focusing)
        XCTAssertEqual(Int(vm.totalSeconds), 25 * 60)
        let attempt = try XCTUnwrap(vm.coachEngine.store.attempt(id: attemptID))
        XCTAssertEqual(attempt.reward, CoachRewardLedger.startReward, "v4 F1: a start after the card is the card's win")
        XCTAssertEqual(attempt.outcome, .improved)
        XCTAssertNil(vm.coachPanel)
        XCTAssertTrue(vm.coachJournal.entries(on: now).contains { $0.kind == .started && $0.text.contains("start card") })
    }

    func testSizePillStartsThatSize() throws {
        let vm = try makeViewModel()
        XCTAssertTrue(vm.evaluateDailyPlanInvite(now: Date()))
        XCTAssertTrue(vm.performCoachPanelStart(minutes: 5))
        XCTAssertEqual(Int(vm.totalSeconds), 5 * 60)
        XCTAssertEqual(vm.startLadderRecommendation(now: Date()).why, .lastStart)
    }

    func testNoStartPromptWhileNobodyIsAtTheDesk() throws {
        let vm = try makeViewModel()
        vm.systemIdleSecondsProvider = { 600 }
        vm.evaluateIdleStarterIntervention(idleSeconds: 90 * 60, frontmostCategory: .neutral)
        XCTAssertEqual(vm.lastIdleStarterSuppressionReason, .userAway)
        XCTAssertNil(vm.coachPanel)
        XCTAssertTrue(vm.coachEngine.store.attempts.isEmpty, "Nothing delivered, nothing to learn from")
    }

    func testArrivalOpensItsOwnWindow() throws {
        let vm = try makeViewModel()
        // Mark today's start card as handled, so the arrival shows a start nudge.
        CoachDailyPlanInviteStore(defaults: defaults).save(.init(day: Calendar.current.startOfDay(for: Date()), declined: true))
        // Cold start with one start 12 hours away: now is outside every learned window.
        let far = Date().addingTimeInterval(-12 * 3600)
        vm.availabilityModelOverride = CoachAvailabilityModel(sessions: [.init(start: far, end: far.addingTimeInterval(1500))], activeDays: [])
        vm.refreshCoachModelsIfNeeded(force: true)
        vm.evaluateIdleStarterIntervention(idleSeconds: 90 * 60, frontmostCategory: .neutral)
        XCTAssertNil(vm.coachPanel, "Outside a learned window: quiet")
        XCTAssertTrue(vm.handleArrival(now: Date()))
        XCTAssertEqual(vm.coachPanel?.kind, .startNudge)
        XCTAssertEqual(vm.coachPanel?.sizeOptions, [5, 15, 25])
    }

    func testTooBigCounterOffersFiveMinutesOnTheSamePrompt() throws {
        let vm = try makeViewModel()
        XCTAssertTrue(vm.evaluateDailyPlanInvite(now: Date()))
        let attemptID = try XCTUnwrap(vm.coachPanel?.attemptID)
        vm.performCoachPanelSecondary(.reasonTooBig)
        let offer = try XCTUnwrap(vm.coachPanel)
        XCTAssertEqual(offer.kind, .startNudge)
        XCTAssertEqual(offer.plan?.minutes, 5)
        XCTAssertEqual(offer.attemptID, attemptID)
        XCTAssertTrue(offer.reasonActions.isEmpty, "A counter-offer doesn't ask why again")
        let attempt = try XCTUnwrap(vm.coachEngine.store.attempt(id: attemptID))
        XCTAssertEqual(attempt.skipReason, .taskTooBig)
        XCTAssertEqual(vm.startLadderRecommendation(now: Date()), .init(minutes: 5, why: .tooBig))

        XCTAssertTrue(vm.performCoachPanelPrimary())
        XCTAssertEqual(Int(vm.totalSeconds), 5 * 60)
        XCTAssertEqual(attempt.reward, CoachRewardLedger.startReward)
    }

    func testUnclearNextStepStartsAFindTheStepBlock() throws {
        let vm = try makeViewModel()
        XCTAssertTrue(vm.evaluateDailyPlanInvite(now: Date()))
        vm.performCoachPanelSecondary(.reasonUnclear)
        XCTAssertEqual(vm.coachPanel?.message.primaryTitle, "Find the next step · 5m")
        XCTAssertTrue(vm.performCoachPanelPrimary())
        let context = try XCTUnwrap(containers.last?.mainContext)
        let session = try XCTUnwrap(context.fetch(FetchDescriptor<FocusSession>()).first)
        XCTAssertEqual(session.intentText, "Find the next step")
    }

    func testBusyGoesQuietForAnHour() throws {
        let vm = try makeViewModel()
        let now = Date()
        XCTAssertTrue(vm.evaluateDailyPlanInvite(now: now))
        vm.performCoachPanelSecondary(.reasonBusy, now: now)
        XCTAssertNil(vm.coachPanel)
        XCTAssertEqual(vm.coachQuietUntil, now.addingTimeInterval(3600))
        XCTAssertFalse(vm.evaluateDailyPlanInvite(now: now.addingTimeInterval(3 * 3600)), "The card is done for today")
        XCTAssertTrue(vm.coachJournal.entries(on: now).contains { $0.kind == .declined && $0.text.contains("busy with work") })
    }

    // MARK: v5 learning engine, end to end

    func testEveryDecisionPointIsLoggedWithItsProbabilityAndResolvesAfterTheHour() throws {
        let vm = try makeViewModel()
        vm.coachArmOverride = nil
        vm.coachRandom = SplitMix64(seed: 11)
        let now = Date()
        vm.evaluateIdleStarterIntervention(idleSeconds: 40 * 60, frontmostCategory: .neutral)
        let decision = try XCTUnwrap(vm.coachEngine.store.attempts.first { $0.decisionRaw == CoachPromptPolicy.decisionKey })
        XCTAssertEqual(CoachPromptFeatures.decode(decision.featuresRaw)?.count, CoachPromptFeatures.count)
        let p = try XCTUnwrap(decision.propensity)
        XCTAssertTrue((CoachPromptPolicy.minProbability...CoachPromptPolicy.maxProbability).contains(p))
        XCTAssertEqual(decision.treated, vm.coachPanel != nil)
        XCTAssertTrue(vm.promptLearningObservations(now: now).isEmpty, "Unresolved for an hour")
        let resolved = vm.promptLearningObservations(now: now.addingTimeInterval(3601))
        XCTAssertEqual(resolved.count, 1)
        XCTAssertEqual(resolved.first?.reward, 0, "No block followed")
        if decision.treated == true {
            XCTAssertEqual(decision.askedMinutes, 15)
            XCTAssertEqual(vm.sizeLearningObservations(now: now.addingTimeInterval(3601)).first?.arm, 15)
        }
        let summary = vm.coachLearningSummary(now: now.addingTimeInterval(3601))
        XCTAssertEqual(summary.decisions, 1)
        XCTAssertNil(summary.lift, "Needs 20 randomised moments")
    }

    // MARK: Priorities and goals → coach (priorities-goals design §3.5)

    func testCoachAimsAtTheTopPriorityAndTodaysLeverBecomesTheIntent() throws {
        let vm = try makeViewModel()
        let context = try XCTUnwrap(containers.last?.mainContext)
        let office = Project(name: "Office")
        office.priorityRank = 2
        office.area = .work
        let learning = Project(name: "Learning")
        learning.priorityRank = 1
        learning.area = .learning
        context.insert(office)
        context.insert(learning)
        let now = Date()
        let goal = ProjectGoal(title: "Apply by Nov 28", projectID: learning.id, startDate: now.addingTimeInterval(-10 * 86_400), deadline: now.addingTimeInterval(20 * 86_400))
        context.insert(goal)
        let leet = GoalKeyResult(title: "LeetCode", kind: .count, target: 60, unit: "questions")
        context.insert(leet)
        goal.keyResults = [leet]
        try context.save()

        let snapshot = vm.coachSnapshot(now: now, idleSeconds: 0, frontmostCategory: .neutral)
        XCTAssertEqual(snapshot.target.name, "Learning", "No weekly priority: the #1 project")
        XCTAssertEqual(snapshot.target.projectID, learning.id)
        XCTAssertEqual(snapshot.facts.lever, "3 LeetCode questions", "60 left over 20 days")

        XCTAssertTrue(vm.startNextBlock(minutes: 15))
        let session = try XCTUnwrap(context.fetch(FetchDescriptor<FocusSession>()).first)
        XCTAssertEqual(session.project?.id, learning.id)
        XCTAssertEqual(session.intentText, "3 LeetCode questions")
    }

    func testOfficeHoursDoNotFillTheOwnWorkGoal() throws {
        let vm = try makeViewModel()
        let context = try XCTUnwrap(containers.last?.mainContext)
        let office = Project(name: "Office")
        office.area = .work
        let learning = Project(name: "Learning")
        learning.area = .learning
        context.insert(office)
        context.insert(learning)
        let start = Calendar.current.startOfDay(for: Date()).addingTimeInterval(60)
        func block(_ project: Project, at offset: TimeInterval, minutes: Double) {
            let session = FocusSession(type: .focus, duration: minutes * 60, project: project)
            session.startedAt = start.addingTimeInterval(offset)
            session.endedAt = session.startedAt.addingTimeInterval(minutes * 60)
            session.completed = true
            context.insert(session)
        }
        block(office, at: 0, minutes: 180)
        try context.save()
        vm.todayFocusTime = 180 * 60
        XCTAssertEqual(vm.goalProgressSeconds(), 0, "Three hours of office are not your own work")
        block(learning, at: 4 * 3600, minutes: 30)
        try context.save()
        vm.todayFocusTime = 210 * 60
        XCTAssertEqual(vm.goalProgressSeconds(), 1800, accuracy: 1)

        office.areaRaw = nil
        try context.save()
        vm.todayFocusTime = 210 * 60 + 1
        XCTAssertEqual(vm.goalProgressSeconds(), 210 * 60 + 1, "No Work project: all focus counts, as before")
    }

    // MARK: Journal file

    func testJournalWritesReadsAndTrims() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("journal-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent(CoachJournal.fileName)
        let journal = CoachJournal(fileURL: url)
        journal.record(.quiet, "Quiet: quiet hours.", at: t(0))
        journal.record(.quiet, "Quiet: quiet hours.", at: t(1))
        journal.record(.shown, "Start card.", at: t(2))
        XCTAssertEqual(CoachJournal.load(from: url).map(\.text), ["Quiet: quiet hours.", "Start card."], "Repeated quiet reasons are written once")
        XCTAssertEqual(CoachJournal(fileURL: url).entries(on: t0).count, 2)
        CoachJournal.trim(url, keep: 1)
        XCTAssertEqual(CoachJournal.load(from: url).map(\.text), ["Start card."])
    }

    // MARK: Fixture

    private func makeViewModel() throws -> TimerViewModel {
        let schema = Schema([
            Project.self, FocusSession.self, AppSettings.self, TimeSplit.self, BlockProfile.self,
            AppUsageRecord.self, AppUsageEntry.self, TaskIntent.self, CoachInterruption.self,
            InterventionAttempt.self, BreakLearningEvent.self, IdleDistractionItem.self, WeeklyPriority.self, PlannedBlock.self, ProjectGoal.self, GoalKeyResult.self, GoalProgressEntry.self, DailyTask.self,
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
