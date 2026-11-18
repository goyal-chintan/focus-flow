import XCTest
import SwiftData
@testable import FocusFlow

/// 6 Nov 2026: "how many did I solve today?" had no clear answer. One count per number and day:
/// the goal card, the lever and today's task agree, block titles carry no number, and fixing old
/// tasks never deletes an entry.
@MainActor
final class GoalTodayCountTests: XCTestCase {
    private var container: ModelContainer!
    private var vm: TimerViewModel!
    private var context: ModelContext { container.mainContext }
    private var result: GoalKeyResult!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        try await super.setUp()
        container = try ModelContainer(for: FocusFlowSchema.schema, configurations: ModelConfiguration(schema: FocusFlowSchema.schema, isStoredInMemoryOnly: true))
        let settings = AppSettings(); context.insert(settings)
        let cal = Calendar.current
        let goal = ProjectGoal(title: "Programming", projectID: nil, startDate: cal.date(byAdding: .day, value: -10, to: cal.startOfDay(for: Date()))!,
                               deadline: cal.date(byAdding: .day, value: 10, to: cal.startOfDay(for: Date()))!)
        context.insert(goal)
        result = GoalKeyResult(title: "Problems Solved", kind: .count, target: 40)
        context.insert(result)
        goal.keyResults = [result]
        // 20 before today: 20 left over 10 days, 2 a day.
        let old = GoalProgressEntry(amount: 20, at: cal.date(byAdding: .day, value: -3, to: Date())!)
        context.insert(old); result.entries.append(old)
        try context.save()
        defaults = cleanDefaults("todaycount")
        vm = TimerViewModel(defaults: defaults)
        vm.configureForEvidence(modelContext: context, settings: settings)
    }

    override func tearDown() async throws {
        AppUsageTracker.shared.stop()
        vm = nil; result = nil; container = nil
        try await super.tearDown()
    }

    private func logLoose(_ n: Int, minutesAgo: Double) {
        for i in 0..<n {
            let entry = GoalProgressEntry(amount: 1, at: Date().addingTimeInterval(-minutesAgo * 60 - Double(i)))
            context.insert(entry); result.entries.append(entry)
        }
        try? context.save()
    }

    private var entryTotal: Double { result.entries.reduce(0) { $0 + $1.amount } }

    func testATaskForTheLeverStartsFromWhatIsDoneToday() throws {
        guard Calendar.current.component(.hour, from: Date()) < 23 else { throw XCTSkip("Too close to midnight") }
        logLoose(1, minutesAgo: 30)
        let lever = try XCTUnwrap(vm.todayLevers().first)
        XCTAssertEqual(lever.action, "Problems Solved: 1 of 2 today")
        XCTAssertEqual(lever.intentTitle, "Problems Solved")
        let task = try XCTUnwrap(vm.addLeverTask(lever))
        XCTAssertEqual(task.title, "Problems Solved", "No numbers in a task title")
        XCTAssertEqual(task.loggedCount, 1)
        XCTAssertEqual(task.progressAmount, 2, "The day's aim, the same 1 of 2 as the goal")
        XCTAssertEqual(GoalDataBuilder.todayCounts(try XCTUnwrap(result.goal), now: Date())[result.id]?.label, "1 of 2 today")
    }

    func testTheGoalsPlusOneGoesThroughTodaysTask() throws {
        guard Calendar.current.component(.hour, from: Date()) < 23 else { throw XCTSkip("Too close to midnight") }
        let task = try XCTUnwrap(vm.addLeverTask(try XCTUnwrap(vm.todayLevers().first)))
        vm.logOneMore(resultID: result.id)
        XCTAssertEqual(task.loggedCount, 1)
        XCTAssertEqual(entryTotal, 21)
        vm.takeBackOne(resultID: result.id)
        XCTAssertEqual(task.loggedCount, 0)
        XCTAssertEqual(entryTotal, 20)
        vm.takeBackOne(resultID: result.id)
        XCTAssertEqual(entryTotal, 19, "Nothing on the task: a plain −1 on the number")
    }

    /// The live case: 2 solved, then a "2 more" task made at 18:49 read "0 of 2".
    func testAnOldTaskIsRepairedOnceAndNoEntryIsEverLost() throws {
        guard Calendar.current.component(.hour, from: Date()) >= 1 else { throw XCTSkip("Too close to midnight") }
        logLoose(2, minutesAgo: 30)
        let old = DailyTask(title: "Problems Solved", day: Calendar.current.startOfDay(for: Date()), order: 0, projectID: nil, keyResultID: result.id, amount: 2)
        old.createdAt = Date().addingTimeInterval(-10 * 60)
        context.insert(old)
        try context.save()

        vm.repairCountedTasks(now: Date().addingTimeInterval(60))
        XCTAssertEqual(old.loggedCount, 2)
        XCTAssertEqual(old.progressAmount, 4, "2 done + 2 more")
        vm.repairCountedTasks(now: Date().addingTimeInterval(120))
        XCTAssertEqual(old.progressAmount, 4, "Once only")
        XCTAssertEqual(entryTotal, 22, "Repair changes no entry")

        vm.setDailyTask(old, done: true)
        XCTAssertEqual(entryTotal, 24, "Done logs only the 2 still open")
        vm.setDailyTask(old, done: false)
        XCTAssertEqual(entryTotal, 22, "Untick removes what the task logged, never the 2 you logged before it")
        vm.deleteDailyTask(old)
        XCTAssertEqual(entryTotal, 22)
    }

    func testATaskMadeAfterTheFixIsNotRepaired() throws {
        _ = CountedTaskRepair(defaults: defaults).cutoff(now: Date().addingTimeInterval(-3600))
        logLoose(2, minutesAgo: 5)
        let manual = DailyTask(title: "Problems Solved", day: Calendar.current.startOfDay(for: Date()), order: 0, projectID: nil, keyResultID: result.id, amount: 3)
        context.insert(manual)
        try context.save()
        vm.repairCountedTasks()
        XCTAssertEqual(manual.progressAmount, 3)
        XCTAssertEqual(manual.loggedCount, 0)
    }
}
