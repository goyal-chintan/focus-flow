import XCTest
import SwiftData
@testable import FocusFlow

/// Tasks and goals review (2026-10-30): goals are counts, one-off steps are tasks, any task can
/// count toward a goal, and each screen has one way to log.
@MainActor
final class TasksGoalsClarityTests: XCTestCase {
    private var container: ModelContainer?

    private func makeVM() throws -> (TimerViewModel, ModelContext) {
        let schema = Schema([Project.self, FocusSession.self, AppSettings.self, TimeSplit.self, BlockProfile.self, AppUsageRecord.self,
                             AppUsageEntry.self, TaskIntent.self, CoachInterruption.self, InterventionAttempt.self, BreakLearningEvent.self,
                             IdleDistractionItem.self, WeeklyPriority.self, PlannedBlock.self, ProjectGoal.self, GoalKeyResult.self,
                             GoalProgressEntry.self, DailyTask.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        self.container = container
        let vm = TimerViewModel()
        vm.systemIdleSecondsProvider = { 0 }
        vm.coachExploreSizes = false
        vm.configure(modelContext: container.mainContext)
        return (vm, container.mainContext)
    }

    private func goal(_ context: ModelContext, results: [GoalKeyResult]) -> ProjectGoal {
        let goal = ProjectGoal(title: "Interview-ready", projectID: nil, startDate: Date().addingTimeInterval(-86_400 * 5),
                               deadline: Date().addingTimeInterval(86_400 * 20))
        context.insert(goal)
        for result in results { context.insert(result) }
        goal.keyResults = results
        try? context.save()
        return goal
    }

    func testAnyTaskCanBeLinkedAndTickingThenCounts() throws {
        let (vm, context) = try makeVM()
        defer { AppUsageTracker.shared.stop() }
        let leetcode = GoalKeyResult(title: "LeetCode", kind: .count, target: 40)
        _ = goal(context, results: [leetcode])
        let task = try XCTUnwrap(vm.addDailyTask(title: "Two-pointer problems"))

        vm.linkDailyTask(task, toResult: leetcode.id)
        XCTAssertEqual(task.keyResultID, leetcode.id)
        XCTAssertEqual(leetcode.done, 0, "Linking an open task logs nothing yet")
        vm.setDailyTask(task, done: true, receipt: false)
        XCTAssertEqual(leetcode.done, 1)

        // Unlinking a done task takes back what it logged.
        vm.linkDailyTask(task, toResult: nil)
        XCTAssertEqual(leetcode.done, 0)
        XCTAssertNil(task.keyResultID)
    }

    func testLinkingADoneTaskLogsItOnTheNewResult() throws {
        let (vm, context) = try makeVM()
        defer { AppUsageTracker.shared.stop() }
        let sql = GoalKeyResult(title: "SQL", kind: .count, target: 10)
        _ = goal(context, results: [sql])
        let task = try XCTUnwrap(vm.addDailyTask(title: "Window functions"))
        vm.setDailyTask(task, done: true, receipt: false)
        vm.linkDailyTask(task, toResult: sql.id)
        XCTAssertEqual(sql.done, 1)
    }

    func testRenameFollowsToTheReminder() async throws {
        let (vm, context) = try makeVM()
        defer { AppUsageTracker.shared.stop() }
        let fake = FakeReminders()
        vm.reminderBridge = fake
        vm.settings?.remindersIntegrationEnabled = true
        let project = Project(name: "Office")
        project.reminderListID = "work"
        context.insert(project)
        let task = try XCTUnwrap(vm.addDailyTask(title: "Plan sprint", projectID: project.id, reminderID: "r1"))
        vm.renameDailyTask(task, to: "  Plan the 227 sprint ")
        await vm.reminderWrite?.value
        XCTAssertEqual(task.title, "Plan the 227 sprint")
        XCTAssertEqual(fake.titles["r1"], "Plan the 227 sprint")
    }

    /// The popover's and notch's "+1" step today's open linked task, so the task's count and the
    /// goal agree; with no such task it logs on the key result.
    func testPlusOneGoesThroughTheLinkedTask() throws {
        let (vm, context) = try makeVM()
        defer { AppUsageTracker.shared.stop() }
        let leetcode = GoalKeyResult(title: "LeetCode", kind: .count, target: 40)
        _ = goal(context, results: [leetcode])
        let task = try XCTUnwrap(vm.addDailyTask(title: "LeetCode questions", keyResultID: leetcode.id, amount: 3))
        vm.logOneMore(resultID: leetcode.id)
        XCTAssertEqual(task.loggedCount, 1)
        XCTAssertEqual(leetcode.done, 1)
        vm.setDailyTask(task, done: true, receipt: false)
        vm.logOneMore(resultID: leetcode.id)
        XCTAssertEqual(leetcode.done, 4, "No open linked task: logged on the result")
    }

    func testDoneOrNotKeyResultsBecomeTasksOnce() throws {
        let (vm, context) = try makeVM()
        defer { AppUsageTracker.shared.stop() }
        let step = GoalKeyResult(title: "Bridge operator suite and source teams", kind: .checkbox, target: 1)
        let duplicate = GoalKeyResult(title: "Plan their sprint", kind: .checkbox, target: 1)
        let finished = GoalKeyResult(title: "Kickoff", kind: .checkbox, target: 1)
        let count = GoalKeyResult(title: "Pages", kind: .count, target: 10)
        let g = goal(context, results: [step, duplicate, finished, count])
        let entry = GoalProgressEntry(amount: 1)
        context.insert(entry)
        finished.entries = [entry]
        _ = vm.addDailyTask(title: "plan their sprint")

        vm.migrateCheckboxKeyResults()
        let titles = vm.todayTasks().map(\.title).sorted()
        XCTAssertEqual(titles, ["Bridge operator suite and source teams", "plan their sprint"])
        XCTAssertEqual(g.keyResults.map(\.title), ["Pages"], "Only counts remain on the goal")
        vm.migrateCheckboxKeyResults()
        XCTAssertEqual(vm.todayTasks().count, 2, "Runs once")
    }

    func testGoalDraftNeedsANumberAndHasNoDefaultTarget() {
        var draft = GoalDraft()
        draft.title = "Interview-ready"
        draft.keyResults = [.init(title: "LeetCode")]
        XCTAssertNil(draft.keyResults[0].target, "No default 10")
        XCTAssertFalse(draft.isValid)
        draft.keyResults[0].target = 40
        XCTAssertTrue(draft.isValid)
    }

    /// Source contract: the + is a real button, Today's field is ready on open, ⌘N jumps to it,
    /// and the popover says "Working on", not "Goal for this block".
    func testAddRowAndVocabulary() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let tasks = try String(contentsOf: root.appendingPathComponent("Sources/FocusFlow/Views/Goals/DailyTasksSection.swift"), encoding: .utf8)
        XCTAssertTrue(tasks.contains("Button(action: add)"))
        XCTAssertTrue(tasks.contains(".onAppear { fieldFocused = true }"))
        XCTAssertTrue(tasks.contains(#".keyboardShortcut("n", modifiers: .command)"#))
        XCTAssertTrue(tasks.contains(#"Menu("Link to goal")"#))
        let popover = try String(contentsOf: root.appendingPathComponent("Sources/FocusFlow/Views/MenuBar/MenuBarPopoverView.swift"), encoding: .utf8)
        XCTAssertFalse(popover.contains("Goal for this block"))
        XCTAssertTrue(popover.contains(#"IdleSectionLabel("Working on")"#))
    }
}
