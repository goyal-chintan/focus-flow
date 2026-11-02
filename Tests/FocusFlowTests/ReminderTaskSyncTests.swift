import XCTest
import SwiftData
@testable import FocusFlow

/// Per-project Reminders sync (2026-10-30): one list per project, today's reminders become its
/// tasks, and ticks, adds, moves and deletes go back.
@MainActor
final class ReminderTaskSyncTests: XCTestCase {
    private let calendar = Calendar.current
    /// Held for the test's length: SwiftData resets models when their container goes away.
    private var container: ModelContainer?
    private var today: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 30, hour: 10))! }
    private var yesterday: Date { calendar.date(byAdding: .day, value: -1, to: today)! }
    private var tomorrow: Date { calendar.date(byAdding: .day, value: 1, to: today)! }

    private func item(_ id: String, _ title: String, list: String = "work", due: Date? = nil) -> RemindersService.ReminderItem {
        .init(id: id, title: title, list: "Work", listId: list, dueDate: due)
    }

    // MARK: Plan (pure)

    func testImportsEveryReminderOfSyncedListsOnceLaterOnesOnTheirDay() {
        let project = UUID()
        let plan = ReminderTaskSync.plan(
            open: [
                item("a", "Today", due: today),
                item("b", "Overdue", due: yesterday),
                item("c", "Undated"),
                item("d", "Tomorrow", due: tomorrow),
                item("e", "Other list", list: "home"),
                item("f", "Already a task"),
            ],
            projectForList: ["work": project],
            tasks: [.init(id: UUID(), reminderID: "f", day: today, isDone: false, title: "Already a task")],
            today: today
        )
        XCTAssertEqual(plan.imports.map(\.reminderID), ["a", "b", "c", "d"])
        XCTAssertTrue(plan.imports.allSatisfy { $0.projectID == project })
        XCTAssertEqual(plan.imports.map(\.day), [today, today, today, tomorrow].map(calendar.startOfDay(for:)))
    }

    func testAnUnfinishedEarlierTaskMakesTheImportItsCarryOver() {
        let earlier = UUID()
        let plan = ReminderTaskSync.plan(
            open: [item("a", "Write spec")],
            projectForList: ["work": UUID()],
            tasks: [.init(id: earlier, reminderID: "a", day: yesterday, isDone: false, title: "Write spec")],
            today: today
        )
        XCTAssertEqual(plan.imports.first?.carriedFromID, earlier)
    }

    func testRenamesFollowRemindersAndMissingOnesAreChecked() {
        let renamed = UUID(), gone = UUID()
        let plan = ReminderTaskSync.plan(
            open: [item("a", "New title")],
            projectForList: ["work": UUID()],
            tasks: [
                .init(id: renamed, reminderID: "a", day: today, isDone: false, title: "Old title"),
                .init(id: gone, reminderID: "z", day: today, isDone: false, title: "Done on phone"),
                .init(id: UUID(), reminderID: "y", day: today, isDone: true, title: "Already done"),
            ],
            today: today
        )
        XCTAssertEqual(plan.renames.map(\.taskID), [renamed])
        XCTAssertEqual(plan.renames.first?.title, "New title")
        XCTAssertEqual(plan.toCheck.map(\.taskID), [gone], "Done tasks are left alone")
    }

    func testRescheduledLaterMovesTheTaskAndUntickedReopensIt() {
        let later = UUID(), done = UUID()
        let plan = ReminderTaskSync.plan(
            open: [item("a", "Later", due: tomorrow), item("b", "Unticked")],
            projectForList: ["work": UUID()],
            tasks: [
                .init(id: later, reminderID: "a", day: today, isDone: false, title: "Later"),
                .init(id: done, reminderID: "b", day: today, isDone: true, title: "Unticked"),
            ],
            today: today
        )
        XCTAssertEqual(plan.deferrals.map(\.taskID), [later])
        XCTAssertEqual(plan.deferrals.first?.day, calendar.startOfDay(for: tomorrow))
        XCTAssertEqual(plan.reopens, [done])
        XCTAssertTrue(plan.imports.isEmpty)
    }

    // MARK: View model, against a fake Reminders store

    private func makeVM() throws -> (TimerViewModel, FakeReminders, Project, ModelContainer) {
        let schema = Schema([Project.self, FocusSession.self, AppSettings.self, TimeSplit.self, BlockProfile.self, AppUsageRecord.self,
                             AppUsageEntry.self, TaskIntent.self, CoachInterruption.self, InterventionAttempt.self, BreakLearningEvent.self,
                             IdleDistractionItem.self, WeeklyPriority.self, PlannedBlock.self, ProjectGoal.self, GoalKeyResult.self,
                             GoalProgressEntry.self, DailyTask.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        self.container = container
        let vm = TimerViewModel()
        vm.systemIdleSecondsProvider = { 0 }
        vm.coachExploreSizes = false
        let fake = FakeReminders()
        vm.reminderBridge = fake
        vm.configure(modelContext: container.mainContext)
        vm.settings?.remindersIntegrationEnabled = true
        let project = Project(name: "Work")
        project.reminderListID = "work"
        container.mainContext.insert(project)
        try container.mainContext.save()
        return (vm, fake, project, container)
    }

    func testSyncImportsThenTickCompletesTheReminder() async throws {
        let (vm, fake, project, _) = try makeVM()
        defer { AppUsageTracker.shared.stop() }
        fake.open = [item("a", "Ship the fix", due: today)]

        await vm.syncReminders(now: today)
        let task = try XCTUnwrap(vm.todayTasks(now: today).first)
        XCTAssertEqual(task.title, "Ship the fix")
        XCTAssertEqual(task.projectID, project.id)
        XCTAssertEqual(task.reminderID, "a")

        await vm.syncReminders(now: today)
        XCTAssertEqual(vm.todayTasks(now: today).count, 1, "Imported once")

        vm.setDailyTask(task, done: true, now: today, receipt: false)
        await vm.reminderWrite?.value
        XCTAssertEqual(fake.completed["a"], true)
    }

    func testCompletedOnThePhoneTicksTheTaskAndDeletedUnlinksIt() async throws {
        let (vm, fake, _, _) = try makeVM()
        defer { AppUsageTracker.shared.stop() }
        fake.open = [item("a", "One"), item("b", "Two")]
        await vm.syncReminders(now: today)

        fake.open = []
        fake.states = ["a": .completed, "b": .missing]
        await vm.syncReminders(now: today)
        let tasks = vm.todayTasks(now: today)
        let one = try XCTUnwrap(tasks.first { $0.title == "One" })
        let two = try XCTUnwrap(tasks.first { $0.title == "Two" })
        XCTAssertTrue(one.isDone)
        XCTAssertFalse(two.isDone)
        XCTAssertNil(two.reminderID, "Deleted in Reminders: the task stays, unlinked")
        await vm.reminderWrite?.value
        XCTAssertNil(fake.completed["a"], "State read from Reminders is not written back")
    }

    func testNewTaskOnASyncedProjectCreatesItsReminder() async throws {
        let (vm, fake, project, _) = try makeVM()
        defer { AppUsageTracker.shared.stop() }
        let task = try XCTUnwrap(vm.addDailyTask(title: "Review PR", projectID: project.id, now: today))
        await vm.reminderWrite?.value
        XCTAssertEqual(fake.created.first?.title, "Review PR")
        XCTAssertEqual(fake.created.first?.listId, "work")
        XCTAssertEqual(task.reminderID, fake.created.first?.id)

        _ = try XCTUnwrap(vm.addDailyTask(title: "No project", now: today))
        await vm.reminderWrite?.value
        XCTAssertEqual(fake.created.count, 1, "Tasks without a synced project stay local")
    }

    func testMoveToTomorrowAndDeleteGoBackToReminders() async throws {
        let (vm, fake, _, _) = try makeVM()
        defer { AppUsageTracker.shared.stop() }
        fake.open = [item("a", "Move me"), item("b", "Delete me")]
        await vm.syncReminders(now: today)
        let tasks = vm.todayTasks(now: today)
        vm.moveDailyTaskToTomorrow(try XCTUnwrap(tasks.first { $0.reminderID == "a" }), now: today)
        vm.deleteDailyTask(try XCTUnwrap(tasks.first { $0.reminderID == "b" }))
        await vm.reminderWrite?.value
        XCTAssertNotNil(fake.dueDays["a"] ?? nil)
        XCTAssertEqual(fake.deleted, ["b"])
    }

    /// Review 2026-10-30: a linked reminder moved to an unsynced list stays `.open`; the sync must
    /// not save or bump the revision, or the popover (keyed on it) re-syncs in a loop.
    func testASyncThatChangesNothingDoesNotRedraw() async throws {
        let (vm, fake, _, _) = try makeVM()
        defer { AppUsageTracker.shared.stop() }
        fake.open = [item("a", "Moved away")]
        await vm.syncReminders(now: today)
        fake.open = []
        fake.states = ["a": .open(title: "Moved away")]
        let revision = vm.dailyTaskRevision
        await vm.syncReminders(now: today)
        await vm.syncReminders(now: today)
        XCTAssertEqual(vm.dailyTaskRevision, revision)
    }

    func testATickOnThePhoneIsNotCreditedToTheRunningBlock() async throws {
        let (vm, fake, _, _) = try makeVM()
        defer { AppUsageTracker.shared.stop() }
        fake.open = [item("a", "Phone task")]
        await vm.syncReminders(now: today)
        XCTAssertTrue(vm.startFocus())
        fake.open = []
        fake.states = ["a": .completed]
        await vm.syncReminders(now: today)
        let task = try XCTUnwrap(vm.todayTasks(now: today).first)
        XCTAssertTrue(task.isDone)
        XCTAssertNil(task.sessionID, "Done in Reminders, not in this block")
        vm.stop()
    }

    func testAfterDontSyncNothingIsWrittenToTheOldList() async throws {
        let (vm, fake, project, _) = try makeVM()
        defer { AppUsageTracker.shared.stop() }
        fake.open = [item("a", "One"), item("b", "Two")]
        await vm.syncReminders(now: today)
        project.reminderListID = nil
        let tasks = vm.todayTasks(now: today)
        vm.setDailyTask(try XCTUnwrap(tasks.first { $0.reminderID == "a" }), done: true, now: today, receipt: false)
        vm.deleteDailyTask(try XCTUnwrap(tasks.first { $0.reminderID == "b" }))
        await vm.reminderWrite?.value
        XCTAssertTrue(fake.completed.isEmpty)
        XCTAssertTrue(fake.deleted.isEmpty)
    }

    func testCarryOverSkipsATaskTheSyncAlreadyBroughtIn() async throws {
        let (vm, fake, project, _) = try makeVM()
        defer { AppUsageTracker.shared.stop() }
        let old = try XCTUnwrap(vm.addDailyTask(title: "Old title", projectID: project.id, reminderID: "a", day: yesterday, now: yesterday))
        fake.open = [item("a", "Renamed in Reminders")]
        await vm.syncReminders(now: today)
        let recent = vm.recentDailyTasks(days: 8, now: today)
        XCTAssertTrue(DailyTaskPlanner.carryOverCandidates(recent, today: today).isEmpty, "Banner and action agree")
        XCTAssertEqual(vm.carryOverDailyTasks(now: today), 0)
        XCTAssertEqual(vm.todayTasks(now: today).first?.carriedFromID, old.id)
    }

    /// Bug 2026-10-30: switching a project's list kept the old list's tasks as plain tasks, and
    /// switching back imported them again. Now the old list's open tasks go; done ones stay.
    func testSwitchingListsRemovesTheOldListsOpenTasksWithoutDuplicates() async throws {
        let (vm, fake, project, _) = try makeVM()
        defer { AppUsageTracker.shared.stop() }
        fake.open = [item("a1", "From A", list: "work"), item("a2", "Done in A", list: "work"), item("b1", "From B", list: "home")]
        await vm.syncReminders(now: today)
        let doneTask = try XCTUnwrap(vm.todayTasks(now: today).first { $0.reminderID == "a2" })
        vm.setDailyTask(doneTask, done: true, now: today, receipt: false)
        await vm.reminderWrite?.value

        project.reminderListID = "home"
        vm.reminderListChanged(forProject: project.id, now: today)
        await vm.syncReminders(now: today)
        var titles = vm.todayTasks(now: today).map(\.title).sorted()
        XCTAssertEqual(titles, ["Done in A", "From B"], "A's open task is gone; the done one stays as history")
        XCTAssertNil(vm.todayTasks(now: today).first { $0.title == "Done in A" }?.reminderID)
        XCTAssertTrue(fake.deleted.isEmpty, "Nothing is deleted in Reminders")

        project.reminderListID = "work"
        vm.reminderListChanged(forProject: project.id, now: today)
        await vm.syncReminders(now: today)
        titles = vm.todayTasks(now: today).map(\.title).sorted()
        XCTAssertEqual(titles, ["Done in A", "From A"], "Back on A: its open reminder once, the done one kept")
        XCTAssertEqual(vm.todayTasks(now: today).filter { $0.title == "From A" }.count, 1, "No duplicates after switching back")
        XCTAssertEqual(vm.todayTasks(now: today).filter { $0.title == "From B" }.count, 0, "B's open task is gone")
    }

    /// Bug 2026-10-30: the queued write held the new task weakly; callers that drop the task
    /// (`_ = addDailyTask…`, as Today's add field does) lost the reminder.
    func testAddingATaskAndDroppingItStillCreatesItsReminder() async throws {
        let (vm, fake, project, _) = try makeVM()
        defer { AppUsageTracker.shared.stop() }
        _ = vm.addDailyTask(title: "Schema finalisation", projectID: project.id, now: today)
        await vm.reminderWrite?.value
        XCTAssertEqual(fake.created.map(\.title), ["Schema finalisation"])
        XCTAssertEqual(vm.todayTasks(now: today).first?.reminderID, fake.created.first?.id)
    }

    func testAReminderMatchingAnUnlinkedTaskIsLinkedNotImported() async throws {
        let (vm, fake, project, _) = try makeVM()
        defer { AppUsageTracker.shared.stop() }
        vm.settings?.remindersIntegrationEnabled = false
        let local = try XCTUnwrap(vm.addDailyTask(title: "Bridge operator suite", projectID: project.id, now: today))
        vm.settings?.remindersIntegrationEnabled = true
        fake.open = [item("r9", "bridge operator suite ")]
        await vm.syncReminders(now: today)
        XCTAssertEqual(vm.todayTasks(now: today).count, 1, "No duplicate")
        XCTAssertEqual(local.reminderID, "r9")
    }

    func testNothingSyncsWithTheToggleOff() async throws {
        let (vm, fake, project, _) = try makeVM()
        defer { AppUsageTracker.shared.stop() }
        vm.settings?.remindersIntegrationEnabled = false
        fake.open = [item("a", "Hidden")]
        await vm.syncReminders(now: today)
        XCTAssertTrue(vm.todayTasks(now: today).isEmpty)
        _ = vm.addDailyTask(title: "Local", projectID: project.id, now: today)
        await vm.reminderWrite?.value
        XCTAssertTrue(fake.created.isEmpty)
    }

    // MARK: Project page (project tasks redesign 2026-11-02)

    func testTheProjectPageSaysWhyNothingShows() throws {
        let (vm, fake, project, _) = try makeVM()
        defer { AppUsageTracker.shared.stop() }
        XCTAssertEqual(vm.reminderLink(for: project), .linked(listTitle: "Work"))
        fake.lists = []
        XCTAssertEqual(vm.reminderLink(for: project), .listMissing)
        project.reminderListID = nil
        XCTAssertEqual(vm.reminderLink(for: project), .notLinked)
        fake.isAuthorized = false
        XCTAssertEqual(vm.reminderLink(for: project), .noAccess)
        vm.settings?.remindersIntegrationEnabled = false
        XCTAssertEqual(vm.reminderLink(for: project), .syncOff)
    }

    func testLaterRemindersAreTheProjectsTasksOnTheirDays() async throws {
        let (vm, fake, project, _) = try makeVM()
        defer { AppUsageTracker.shared.stop() }
        let nextWeek = calendar.date(byAdding: .day, value: 7, to: today)!
        fake.open = [item("a", "Today's", due: today), item("b", "Next week", due: nextWeek),
                     item("c", "Tomorrow's", due: tomorrow), item("d", "Undated"), item("x", "Other list", list: "home", due: tomorrow)]
        await vm.syncReminders(now: today)
        XCTAssertEqual(Set(vm.todayTasks(now: today).map(\.title)), ["Today's", "Undated"])
        XCTAssertEqual(vm.laterTasks(forProject: project.id, now: today).map(\.title), ["Tomorrow's", "Next week"])

        // Imported once; rescheduled in Reminders, the task follows (here: to today).
        fake.open = [item("a", "Today's", due: today), item("b", "Next week", due: today),
                     item("c", "Tomorrow's", due: tomorrow), item("d", "Undated")]
        await vm.syncReminders(now: today)
        XCTAssertEqual(Set(vm.todayTasks(now: today).map(\.title)), ["Today's", "Undated", "Next week"])
        XCTAssertEqual(vm.laterTasks(forProject: project.id, now: today).map(\.title), ["Tomorrow's"])
    }

    func testALaterReminderDoneOnThePhoneTicksItsTask() async throws {
        let (vm, fake, project, _) = try makeVM()
        defer { AppUsageTracker.shared.stop() }
        fake.open = [item("c", "Tomorrow's", due: tomorrow)]
        await vm.syncReminders(now: today)
        let task = try XCTUnwrap(vm.laterTasks(forProject: project.id, now: today).first)
        fake.open = []
        fake.states = ["c": .completed]
        await vm.syncReminders(now: today)
        XCTAssertTrue(task.isDone)
    }

    func testDoTodayMovesALaterReminderAndItsDueDate() async throws {
        let (vm, fake, project, _) = try makeVM()
        defer { AppUsageTracker.shared.stop() }
        fake.open = [item("b", "Write the transfer doc", due: tomorrow)]
        await vm.syncReminders(now: today)
        let task = try XCTUnwrap(vm.laterTasks(forProject: project.id, now: today).first)
        vm.moveDailyTaskToToday(task, now: today)
        await vm.reminderWrite?.value
        XCTAssertTrue(calendar.isDate(task.day, inSameDayAs: today))
        XCTAssertEqual(fake.dueDays["b"] ?? nil, calendar.startOfDay(for: today))

        // Reminders now says today, so the next sync keeps it today and adds no copy.
        fake.open = [item("b", "Write the transfer doc", due: today)]
        await vm.syncReminders(now: today)
        XCTAssertEqual(vm.todayTasks(now: today).map(\.title), ["Write the transfer doc"])
        XCTAssertTrue(vm.laterTasks(forProject: project.id, now: today).isEmpty)
    }

    // MARK: Picking reminders into a goal (2026-11-02)

    func testPickedRemindersMakeANewNumberAndEachDoneAddsOne() async throws {
        let (vm, fake, project, container) = try makeVM()
        defer { AppUsageTracker.shared.stop() }
        let goal = ProjectGoal(title: "Create a transfer document", projectID: project.id, startDate: yesterday,
                               deadline: calendar.date(byAdding: .day, value: 10, to: today)!)
        container.mainContext.insert(goal)
        fake.open = [item("a", "Outline", due: today), item("b", "Draft", due: tomorrow), item("c", "Review", due: tomorrow)]
        await vm.syncReminders(now: today)
        let picked = vm.todayTasks(now: today) + vm.laterTasks(forProject: project.id, now: today).prefix(1)

        let number = try XCTUnwrap(vm.countTasks(picked, toward: goal, resultID: nil, newTitle: "Sections", now: today))
        XCTAssertEqual(number.title, "Sections")
        XCTAssertEqual(number.target, 2)
        XCTAssertEqual(goal.keyResults.count, 1)
        XCTAssertTrue(picked.allSatisfy { $0.keyResultID == number.id })

        // Done here: +1. Done on the phone (a later one): +1 too.
        let first = try XCTUnwrap(vm.todayTasks(now: today).first)
        vm.setDailyTask(first, done: true, now: today, receipt: false)
        fake.open = [item("c", "Review", due: tomorrow)]
        fake.states = ["b": .completed]
        await vm.syncReminders(now: today)
        XCTAssertEqual(number.entries.reduce(0) { $0 + $1.amount }, 2)

        // Picking one more into the same number raises its target.
        let review = try XCTUnwrap(vm.laterTasks(forProject: project.id, now: today).first)
        vm.countTasks([review], toward: goal, resultID: number.id, now: today)
        XCTAssertEqual(number.target, 3)
    }

    func testACarriedOverReminderKeepsCountingTowardItsGoal() async throws {
        let (vm, fake, project, container) = try makeVM()
        defer { AppUsageTracker.shared.stop() }
        let goal = ProjectGoal(title: "Handover", projectID: project.id, startDate: yesterday,
                               deadline: calendar.date(byAdding: .day, value: 10, to: today)!)
        container.mainContext.insert(goal)
        fake.open = [item("a", "Outline")]
        await vm.syncReminders(now: yesterday)
        let number = try XCTUnwrap(vm.countTasks(vm.todayTasks(now: yesterday), toward: goal, resultID: nil, now: yesterday))
        await vm.syncReminders(now: today)
        XCTAssertEqual(vm.todayTasks(now: today).first?.keyResultID, number.id)
    }

}

@MainActor
final class FakeReminders: ReminderBridge {
    var isAuthorized = true
    var open: [RemindersService.ReminderItem] = []
    var states: [String: RemindersService.ReminderState] = [:]
    var completed: [String: Bool] = [:]
    var dueDays: [String: Date?] = [:]
    var created: [(id: String, title: String, listId: String)] = []
    var deleted: [String] = []

    func fetchIncompleteReminders(in listIds: [String]?, dueDateStarting: Date?, dueDateEnding: Date?) async -> [RemindersService.ReminderItem] {
        // Like EventKit: completed reminders are not in the incomplete fetch.
        open.filter { (listIds?.contains($0.listId) ?? true) && completed[$0.id] != true }
    }
    func reminderState(identifier: String) -> RemindersService.ReminderState { states[identifier] ?? .missing }
    func setReminderCompleted(identifier: String, _ value: Bool) -> Bool { completed[identifier] = value; return true }
    func setReminderDueDay(identifier: String, _ day: Date?) -> Bool { dueDays[identifier] = day; return true }
    var titles: [String: String] = [:]
    func setReminderTitle(identifier: String, _ title: String) -> Bool { titles[identifier] = title; return true }
    func createReminder(title: String, dueDay: Date?, listId: String) -> String? {
        let id = "new-\(created.count)"
        created.append((id, title, listId))
        return id
    }
    func deleteReminder(identifier: String) -> Bool { deleted.append(identifier); return true }
    var lists: [(id: String, title: String, source: String)] = [("work", "Work", "iCloud")]
    func reminderLists() -> [(id: String, title: String, source: String)] { lists }
}
