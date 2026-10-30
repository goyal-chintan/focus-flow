import XCTest
import SwiftData
@testable import FocusFlow

/// Clarity fixes 2026-10-28 (docs/plans/2026-10-28-clarity-fixes.md): focus blocks on the
/// calendar, counted tasks with a receipt and Undo, and the daily reminder line.
@MainActor
final class ClarityFixesTests: XCTestCase {
    private var container: ModelContainer?

    private func makeVM() throws -> (TimerViewModel, ModelContext) {
        let schema = Schema([
            Project.self, FocusSession.self, AppSettings.self, TimeSplit.self, BlockProfile.self, AppUsageRecord.self,
            AppUsageEntry.self, TaskIntent.self, CoachInterruption.self, InterventionAttempt.self, BreakLearningEvent.self,
            IdleDistractionItem.self, WeeklyPriority.self, PlannedBlock.self, ProjectGoal.self, GoalKeyResult.self,
            GoalProgressEntry.self, DailyTask.self,
        ])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        self.container = container
        let context = container.mainContext
        let settings = AppSettings()
        context.insert(settings)
        try context.save()
        let vm = TimerViewModel()
        vm.systemIdleSecondsProvider = { 0 }
        vm.coachExploreSizes = false
        vm.configureForEvidence(modelContext: context, settings: settings)
        return (vm, context)
    }

    /// "DSA Revision": Problems solved, 40 by the deadline.
    private func makeGoal(_ context: ModelContext) throws -> GoalKeyResult {
        let goal = ProjectGoal(title: "DSA Revision", projectID: nil, deadline: Date().addingTimeInterval(30 * 86400))
        let result = GoalKeyResult(title: "Problems solved", kind: .count, target: 40)
        context.insert(goal)
        context.insert(result)
        goal.keyResults = [result]
        try context.save()
        return result
    }

    // MARK: Calendar focus blocks

    func testFocusBlockTitlesAreRecognised() {
        for title in ["Deep work", "Placeholder: Deep Work / Squad 3 Hotline", "Focus time", "Focus", "Heads-down"] {
            XCTAssertTrue(CalendarAvailability.isFocusBlock(title: title), title)
        }
        for title in ["Daily Sync up", "Lunch", "Commute", "Focus group with users", nil] {
            XCTAssertFalse(CalendarAvailability.isFocusBlock(title: title), title ?? "nil")
        }
    }

    func testAFocusBlockIsNotBusyUnlessAMeetingOverlapsIt() {
        let now = Date()
        let deepWork = DateInterval(start: now.addingTimeInterval(-600), duration: 3600)
        let free = CalendarAvailability.compute(busyIntervals: [], focusIntervals: [deepWork], now: now)
        XCTAssertFalse(free.isBusyNow)
        XCTAssertTrue(free.isFocusBlockNow)
        let sync = DateInterval(start: now.addingTimeInterval(-60), duration: 1800)
        let meeting = CalendarAvailability.compute(busyIntervals: [sync], focusIntervals: [deepWork], now: now)
        XCTAssertTrue(meeting.isBusyNow)
        XCTAssertFalse(meeting.isFocusBlockNow, "A meeting inside the block still wins")
    }

    // MARK: Counted tasks

    func testCountedTaskStepsOneAtATimeAndCompletesAtItsNumber() throws {
        let (vm, context) = try makeVM()
        let result = try makeGoal(context)
        let task = try XCTUnwrap(vm.addDailyTask(title: "Problems solved", keyResultID: result.id, amount: 3))
        XCTAssertTrue(task.isCounted)

        vm.advanceDailyTask(task)
        XCTAssertEqual(task.loggedCount, 1)
        XCTAssertFalse(task.isDone, "One of three is not done")
        XCTAssertEqual(result.done, 1)
        XCTAssertEqual(vm.dailyTaskReceipt?.text, "+1 Problems solved · today 1 of 3 · goal 1 of 40")

        vm.advanceDailyTask(task)
        vm.advanceDailyTask(task)
        XCTAssertTrue(task.isDone)
        XCTAssertEqual(result.done, 3)
        XCTAssertEqual(vm.dailyTaskReceipt?.text, "+1 Problems solved · today's 3 done · goal 3 of 40")

        XCTAssertTrue(vm.stepDailyTask(task, by: -1))
        XCTAssertFalse(task.isDone, "Taking one back reopens it")
        XCTAssertEqual(result.done, 2)

        vm.setDailyTask(task, done: true)
        XCTAssertEqual(result.done, 3, "Mark all done logs only what was left")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<GoalProgressEntry>()), 3)
        vm.setDailyTask(task, done: false)
        XCTAssertEqual(result.done, 0, "Not done takes back everything it logged")
        XCTAssertEqual(task.loggedCount, 0)
        XCTAssertFalse(vm.stepDailyTask(task, by: -1), "Nothing to take back")
    }

    func testUndoReversesTheLastChangeWithoutANewReceipt() throws {
        let (vm, context) = try makeVM()
        let result = try makeGoal(context)
        let task = try XCTUnwrap(vm.addDailyTask(title: "Problems solved", keyResultID: result.id, amount: 3))
        vm.advanceDailyTask(task)
        vm.undoDailyTaskReceipt()
        XCTAssertEqual(task.loggedCount, 0)
        XCTAssertEqual(result.done, 0)
        XCTAssertNil(vm.dailyTaskReceipt)

        let plain = try XCTUnwrap(vm.addDailyTask(title: "Read the notes"))
        vm.advanceDailyTask(plain)
        XCTAssertTrue(plain.isDone)
        XCTAssertEqual(vm.dailyTaskReceipt?.text, "Done: Read the notes")
        vm.undoDailyTaskReceipt()
        XCTAssertFalse(plain.isDone)
    }

    /// The 2026-10-28 store: a task ticked by the old build carries one +3 entry without `taskID`.
    func testALegacyTickIsAdoptedSoTakingOneBackWorks() throws {
        let (vm, context) = try makeVM()
        let result = try makeGoal(context)
        let task = DailyTask(title: "3 problems solved", day: Calendar.current.startOfDay(for: Date()), keyResultID: result.id, amount: 3)
        context.insert(task)
        let legacy = GoalProgressEntry(amount: 3, note: task.title)
        context.insert(legacy)
        result.entries.append(legacy)
        task.isDone = true
        task.doneAt = Date()
        task.progressEntryID = legacy.id
        try context.save()

        XCTAssertEqual(task.loggedCount, 3, "Done before the column existed counts as full")
        XCTAssertTrue(vm.stepDailyTask(task, by: -1))
        XCTAssertEqual(task.loggedCount, 2)
        XCTAssertFalse(task.isDone)
        XCTAssertEqual(result.done, 2)
        XCTAssertEqual(legacy.taskID, task.id)
        XCTAssertNil(task.progressEntryID)
    }

    func testCountedTasksAreNamedForWhatYouCount() {
        var lever = DailyLever(id: UUID(), goalTitle: "DSA", projectID: nil, action: "Problems solved: 3 today",
                               reason: "", status: .onTrack, urgency: 1, amount: 3)
        lever.countedName = "Problems solved"
        XCTAssertEqual(lever.taskTitle, "Problems solved")
        lever.amount = 1
        XCTAssertEqual(lever.taskTitle, "Problems solved: 3 today", "A one-off keeps the action")
    }

    // MARK: One truth (2026-10-28 evening)

    /// 26m on Office read "Focus today 26m" in the ring and "0m on your #1" in the footer.
    func testTheGoalTracksTheStarProjectNotOfficeTime() throws {
        let (vm, context) = try makeVM()
        let learning = Project(name: "Learning")
        learning.priorityRank = 1
        learning.area = .personal
        let office = Project(name: "Office")
        [learning, office].forEach { context.insert($0) }
        let session = FocusSession(type: .focus, duration: 25 * 60, project: office)
        session.startedAt = Date().addingTimeInterval(-3600)
        session.endedAt = session.startedAt.addingTimeInterval(26 * 60)
        session.completed = true
        context.insert(session)
        try context.save()

        let scope = GoalDataBuilder.goalScope([learning, office])
        XCTAssertEqual(scope, .project(key: GoalDataBuilder.projectKey(learning), name: "Learning"))
        XCTAssertEqual(scope.label, "★ Learning")
        XCTAssertEqual(vm.goalProgressSeconds(), 0, "Office time does not fill Learning's ring")
        let snapshot = CompanionSnapshot(sessions: [session], settings: nil, projects: [learning, office])
        XCTAssertTrue(snapshot.goalSamples.isEmpty)
        XCTAssertEqual(TodayView.goalTitle(snapshot.goalScope), "★ Learning today")
        XCTAssertEqual(GoalDataBuilder.goalScope([office]), .allFocus, "No #1 and no Work project: every block counts")
        XCTAssertEqual(FFFormat.compactDuration(150 * 60), "2h30")
    }

    /// The task said "Done" while the lever said "2 today": a task for a key result is the commitment.
    func testATaskForAKeyResultIsTodaysCommitmentNotTheLever() throws {
        let (vm, context) = try makeVM()
        let result = try makeGoal(context)
        let lever = DailyLever(id: result.id, goalTitle: "DSA Revision", projectID: nil, action: "Problems solved: 4 today",
                               reason: "need 3.1/day", status: .behind, urgency: 1, amount: 4)
        XCTAssertEqual(DailyTaskPlanner.reconcile([lever], with: [], on: Date()).first?.action, "Problems solved: 4 today")

        let task = try XCTUnwrap(vm.addDailyTask(title: "Problems solved", keyResultID: result.id, amount: 3))
        vm.stepDailyTask(task, by: 1)
        let open = DailyTaskPlanner.reconcile([lever], with: [task], on: Date())
        XCTAssertEqual(open.first?.action, "Problems solved: 1 of 3 today")
        XCTAssertEqual(open.first?.amount, 2)

        vm.setDailyTask(task, done: true)
        XCTAssertTrue(DailyTaskPlanner.reconcile([lever], with: [task], on: Date()).isEmpty, "Met today: no lever asking for more")
    }

    // MARK: Daily reminder

    func testOwnLinesComeFirstAndTheLineHoldsForTheDay() throws {
        let morning = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date())!
        let evening = Calendar.current.date(bySettingHour: 21, minute: 0, second: 0, of: Date())!
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: morning)!

        let library = DailyReminder.line(own: [], style: .challenger, on: morning)
        XCTAssertNotNil(library)
        XCTAssertFalse(library?.isOwn ?? true)
        XCTAssertEqual(library, DailyReminder.line(own: [], style: .challenger, on: evening), "Same line all day")
        XCTAssertNotEqual(library, DailyReminder.line(own: [], style: .challenger, on: tomorrow), "A new line tomorrow")

        let own = DailyReminder.ownLines(why: ["If I don't change today, I stay where I am."],
                                         antiVision: "Still stuck in five years. Same desk.", vision: nil)
        XCTAssertEqual(own.map(\.text), ["If I don't change today, I stay where I am.", "Still stuck in five years."])
    }

    /// 2026-10-28: "majorly Dan Koe", challenging, his questions; never "some random" clarity line.
    func testTheReminderPoolIsMostlyDanKoeAndOnlyChallengingLines() {
        let pool = DailyReminder.libraryLines(style: .challenger)
        let koe = pool.filter { $0.attribution.hasPrefix("Dan Koe") }
        XCTAssertGreaterThan(Double(koe.count) / Double(pool.count), 0.5, "Mostly Dan Koe")
        XCTAssertEqual(pool.filter(\.isQuestion).count, 12)
        XCTAssertFalse(pool.contains { $0.text.hasPrefix("Clarity about what matters") })
        XCTAssertTrue(pool.contains { $0.text == "What am I avoiding right now by doing what I'm doing?" })
        XCTAssertTrue(pool.contains { $0.text == CoachOnePercent.compounding }, "1% better")
        XCTAssertTrue(pool[0].isQuestion && !pool[1].isQuestion && pool[2].isQuestion, "A question every other day")
        XCTAssertTrue(DailyReminder.groundingQuoteIDs.allSatisfy { CoachQuoteLibrary.quote(id: $0) != nil })

        let own = [DailyReminderLine(text: "Mine", attribution: "Your why", isOwn: true)]
        let today = Date()
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
        let pair = [DailyReminder.line(own: own, style: .challenger, on: today), DailyReminder.line(own: own, style: .challenger, on: tomorrow)]
        XCTAssertEqual(pair.filter { $0?.isOwn == true }.count, 1, "Own lines take every other day")
    }

    func testGentleNeverGetsChallengerHouseLines() {
        let gentle = DailyReminder.libraryLines(style: .gentle)
        XCTAssertFalse(gentle.contains { $0.attribution == "FocusFlow" })
        XCTAssertTrue(DailyReminder.libraryLines(style: .challenger).contains { $0.attribution == "FocusFlow" })
        XCTAssertFalse(DailyReminder.libraryLines(style: .challenger).contains { $0.text.contains("{N}") })
    }

    func testReminderReadsAreSafeWhileDrawing() throws {
        let (vm, _) = try makeVM()
        let changed = Flag()
        withObservationTracking {
            _ = vm.dailyReminder()
            _ = vm.ownReminderLines
            _ = vm.dailyTaskReceipt
        } onChange: { changed.value = true }
        _ = vm.dailyReminder(offset: 3)
        XCTAssertFalse(changed.value)
    }

    private final class Flag: @unchecked Sendable { var value = false }
}
