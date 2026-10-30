import XCTest
import SwiftData
import SwiftUI
@testable import FocusFlow

@MainActor
final class DailyTaskTests: XCTestCase {
    private var container: ModelContainer?
    private let calendar = Calendar.current
    private var today: Date { calendar.startOfDay(for: Date()) }
    private func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today)! }

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

    private func task(_ title: String, on day: Date, order: Int = 0, done: Bool = false, project: UUID? = nil) -> DailyTask {
        let task = DailyTask(title: title, day: day, order: order, projectID: project)
        task.isDone = done
        task.doneAt = done ? day.addingTimeInterval(3600 + Double(order)) : nil
        return task
    }

    // MARK: Planner

    func testStatsLabelAndOrdering() {
        let a = task("A", on: today, order: 2)
        let b = task("B", on: today, order: 0, done: true)
        let c = task("C", on: today, order: 1)
        let old = task("Old", on: day(-1))
        let all = [a, b, c, old]
        XCTAssertEqual(DailyTaskPlanner.tasks(all, on: Date()).map(\.title), ["C", "A", "B"], "Open by order, then done")
        let stats = DailyTaskPlanner.stats(all, on: Date())
        XCTAssertEqual(stats, DailyTaskStats(planned: 3, done: 1))
        XCTAssertEqual(stats.label, "1 of 3 done")
        XCTAssertEqual(DailyTaskStats(planned: 0, done: 0).label, "No tasks yet")
        XCTAssertEqual(DailyTaskStats(planned: 4, done: 4).label, "All 4 done")
        XCTAssertEqual(DailyTaskStats(planned: 1, done: 1).label, "1 of 1 done", "Never a bare Done")
    }

    func testNextTaskPrefersTheProject() {
        let learning = UUID()
        let all = [task("Email", on: today, order: 0), task("SQL", on: today, order: 1, project: learning)]
        XCTAssertEqual(DailyTaskPlanner.nextTask(all, on: Date())?.title, "Email")
        XCTAssertEqual(DailyTaskPlanner.nextTask(all, on: Date(), for: learning)?.title, "SQL")
    }

    /// A Learning block shows Learning's tasks only (2026-10-30): never another project's reminders,
    /// never unassigned tasks. With no project, everything.
    func testNextTaskNeverCrossesProjects() {
        let learning = UUID(), work = UUID()
        let epic = task("Create the backup Epic", on: today, order: 0, project: work)
        let loose = task("Call the bank", on: today, order: 1)
        let sql = task("Window functions", on: today, order: 2, project: learning)
        XCTAssertEqual(DailyTaskPlanner.nextTask([epic, loose, sql], on: Date(), for: learning)?.title, "Window functions")
        XCTAssertNil(DailyTaskPlanner.nextTask([epic, loose], on: Date(), for: learning))
        XCTAssertEqual(DailyTaskPlanner.forProject([epic, loose, sql], learning).map(\.title), ["Window functions"])
        XCTAssertEqual(DailyTaskPlanner.forProject([epic, loose, sql], nil).count, 3)
    }

    func testCarryOverTakesTheLastPlannedDayOnly() {
        let older = task("Ancient", on: day(-3))
        let open = task("SQL set", on: day(-2))
        let done = task("Done one", on: day(-2), done: true)
        let tooOld = task("Too old", on: day(-10))
        var all = [older, open, done, tooOld]
        XCTAssertEqual(DailyTaskPlanner.carryOverCandidates(all, today: Date()).map(\.title), ["SQL set"])

        let carried = task("SQL set", on: today)
        carried.carriedFromID = open.id
        all.append(carried)
        XCTAssertTrue(DailyTaskPlanner.carryOverCandidates(all, today: Date()).isEmpty, "Already carried")
    }

    func testHistoryAndWeekSummary() {
        let all = [task("a", on: day(-1)), task("b", on: day(-1), done: true), task("c", on: today, done: true)]
        let history = DailyTaskPlanner.history(all, endingOn: Date(), days: 7)
        XCTAssertEqual(history.count, 7)
        XCTAssertEqual(history.last?.planned, 1)
        XCTAssertEqual(history[5].planned, 2)
        XCTAssertEqual(history[5].done, 1)
        XCTAssertEqual(DailyTaskPlanner.completionRate(history) ?? 0, 2.0 / 3.0, accuracy: 0.001)
        XCTAssertEqual(DailyTaskPlanner.weekSummary(history), "3 planned · 2 done · 67%")
        XCTAssertNil(DailyTaskPlanner.weekSummary(DailyTaskPlanner.history([], endingOn: Date())))
    }

    func testLeverSuggestionsSkipWhatIsAlreadyPlanned() {
        let resultID = UUID()
        let lever = DailyLever(id: resultID, goalTitle: "Interview-ready", projectID: nil, action: "3 LeetCode questions",
                               reason: "need 2.6/day", status: .behind, urgency: 1, amount: 3)
        XCTAssertEqual(DailyTaskPlanner.leverSuggestions([lever], existing: [], on: Date()).count, 1)
        let linked = task("Something", on: today)
        linked.keyResultID = resultID
        XCTAssertTrue(DailyTaskPlanner.leverSuggestions([lever], existing: [linked], on: Date()).isEmpty)
    }

    func testLeversCarryTheirAmount() {
        let input = DailyLevers.KeyResultInput(
            id: UUID(), title: "LeetCode", unit: "questions", target: 60, done: 0, doneToday: 0,
            goalTitle: "Interview-ready", projectID: nil, start: day(-1), deadline: day(31), isBossFight: true
        )
        let lever = try? XCTUnwrap(DailyLevers.levers([input], now: Date()).first)
        // 60 over 30–31 days left is 1.94–2.0 a day at any time of day: 2.
        XCTAssertEqual(lever?.action, "2 LeetCode questions")
        XCTAssertEqual(lever?.amount, 2)
    }

    // MARK: Store

    func testTickingALinkedTaskLogsGoalProgressAndUntickRemovesIt() throws {
        let (vm, context) = try makeVM()
        let goal = ProjectGoal(title: "Interview-ready", projectID: nil, startDate: day(-1), deadline: day(20))
        let result = GoalKeyResult(title: "LeetCode", kind: .count, target: 60, unit: "questions")
        context.insert(goal)
        context.insert(result)
        goal.keyResults = [result]
        try context.save()

        let task = try XCTUnwrap(vm.addDailyTask(title: "  3 LeetCode questions ", keyResultID: result.id, amount: 3))
        XCTAssertEqual(task.title, "3 LeetCode questions")
        XCTAssertNil(vm.addDailyTask(title: "   "), "Blank titles are ignored")
        XCTAssertEqual(vm.dailyTaskStats(), DailyTaskStats(planned: 1, done: 0))

        let revision = vm.dailyTaskRevision
        vm.setDailyTask(task, done: true)
        XCTAssertGreaterThan(vm.dailyTaskRevision, revision)
        XCTAssertEqual(result.done, 3)
        XCTAssertEqual(task.loggedCount, 3)
        XCTAssertEqual(try context.fetch(FetchDescriptor<GoalProgressEntry>()).map(\.taskID), [task.id], "The entry knows its task")
        XCTAssertEqual(vm.dailyTaskStats().label, "1 of 1 done")

        vm.setDailyTask(task, done: true)
        XCTAssertEqual(result.done, 3, "Ticking twice logs once")

        vm.setDailyTask(task, done: false)
        XCTAssertEqual(result.done, 0)
        XCTAssertEqual(task.loggedCount, 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<GoalProgressEntry>()), 0)

        vm.setDailyTask(task, done: true)
        vm.deleteDailyTask(task)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<GoalProgressEntry>()), 0, "Deleting a done task removes its progress")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<DailyTask>()), 0)
    }

    func testCarryOverCopiesOnceAndKeepsYesterdayHonest() throws {
        let (vm, context) = try makeVM()
        let yesterday = task("Write the README", on: day(-1))
        context.insert(yesterday)
        try context.save()
        XCTAssertEqual(vm.carryOverDailyTasks(), 1)
        XCTAssertEqual(vm.carryOverDailyTasks(), 0)
        XCTAssertEqual(vm.todayTasks().map(\.title), ["Write the README"])
        XCTAssertFalse(yesterday.isDone, "Yesterday's task stays unfinished")
        XCTAssertEqual(yesterday.day, day(-1))
    }

    func testMoveToTomorrowAndToTop() throws {
        let (vm, _) = try makeVM()
        let first = try XCTUnwrap(vm.addDailyTask(title: "First"))
        let second = try XCTUnwrap(vm.addDailyTask(title: "Second"))
        vm.moveDailyTaskToTop(second)
        XCTAssertEqual(vm.todayTasks().map(\.title), ["Second", "First"])
        vm.moveDailyTaskToTomorrow(first)
        XCTAssertEqual(vm.todayTasks().map(\.title), ["Second"])
        XCTAssertEqual(first.day, day(1))
    }

    func testABlockStartedForATaskRemembersIt() throws {
        let (vm, _) = try makeVM()
        let task = try XCTUnwrap(vm.addDailyTask(title: "SQL window functions"))
        vm.pendingTaskID = task.id
        vm.pendingIntentText = task.title
        vm.startFocus()
        XCTAssertEqual(vm.currentBlockTaskID, task.id)
        XCTAssertNil(vm.pendingTaskID)
    }

    func testCoachStartUsesTheNextPlannedTask() throws {
        let (vm, _) = try makeVM()
        let task = try XCTUnwrap(vm.addDailyTask(title: "Mock interview answers"))
        XCTAssertTrue(vm.startNextBlock(minutes: 5))
        XCTAssertEqual(vm.currentBlockTaskID, task.id)
        XCTAssertEqual(vm.currentIntentText, "Mock interview answers")
    }

    // MARK: Captures (layout only)

    func testCaptureDailyTaskSurfaces() throws {
        guard let dir = ProcessInfo.processInfo.environment["FOCUSFLOW_CAPTURE_OUTPUT_DIR"], !dir.isEmpty else {
            throw XCTSkip("Set FOCUSFLOW_CAPTURE_OUTPUT_DIR to capture")
        }
        let output = URL(fileURLWithPath: dir).appendingPathComponent("tasks", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let (vm, context) = try makeVM()
        let learning = Project(name: "Learning", color: "purple", icon: "graduationcap.fill")
        learning.priorityRank = 1
        learning.area = .learning
        context.insert(learning)
        let goal = ProjectGoal(title: "Interview-ready by 28 Nov", projectID: learning.id, startDate: day(-10), deadline: day(20), isBossFight: true)
        let leet = GoalKeyResult(title: "LeetCode", kind: .count, target: 60, unit: "questions")
        let sql = GoalKeyResult(title: "SQL", kind: .count, target: 10, unit: "sets", order: 1)
        context.insert(goal)
        [leet, sql].forEach { context.insert($0) }
        goal.keyResults = [leet, sql]
        for (offset, plan) in [(-6, (4, 3)), (-5, (5, 5)), (-4, (3, 1)), (-3, (0, 0)), (-2, (4, 2)), (-1, (5, 3))] {
            for index in 0..<plan.0 {
                context.insert(task("Task \(index)", on: day(offset), order: index, done: index < plan.1))
            }
        }
        try context.save()
        let solved = try XCTUnwrap(vm.addDailyTask(title: "2 LeetCode questions", projectID: learning.id, keyResultID: leet.id, amount: 2))
        vm.setDailyTask(solved, done: true, receipt: false)
        // A counted task one of three in, with the receipt of that +1 showing.
        let counted = try XCTUnwrap(vm.addDailyTask(title: "LeetCode questions", projectID: learning.id, keyResultID: leet.id, amount: 3))
        vm.stepDailyTask(counted, by: 1)
        _ = vm.addDailyTask(title: "Window functions practice set", projectID: learning.id, keyResultID: sql.id)
        _ = vm.addDailyTask(title: "Ask Priya for a referral", projectID: learning.id)
        _ = vm.addDailyTask(title: "Review the system design notes")

        for dark in [false, true] {
            let suffix = dark ? "dark" : "light"
            let today = ScrollView { DailyTasksSection(now: Date()).padding(24) }
                .frame(width: 900, height: 620)
                .background(FFPalette.windowBackground)
            try write(today, size: CGSize(width: 900, height: 620), dark: dark, vm: vm, context: context, to: output.appendingPathComponent("today_tasks_\(suffix).png"))

            let session = SessionTasksSection(sessionID: UUID(), blockTaskID: vm.todayTasks().first { !$0.isDone }?.id, projectID: learning.id)
                .padding(24)
                .frame(width: 480, height: 300)
                .background(FFPalette.windowBackground)
            try write(session, size: CGSize(width: 480, height: 300), dark: dark, vm: vm, context: context, to: output.appendingPathComponent("session_tasks_\(suffix).png"))
        }
    }

    private func write<V: View>(_ view: V, size: CGSize, dark: Bool, vm: TimerViewModel, context: ModelContext, to url: URL) throws {
        let root = view
            .environment(vm)
            .modelContainer(context.container)
            .environment(\.modelContext, context)
            .environment(\.colorScheme, dark ? .dark : .light)
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(origin: .zero, size: size)
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.appearance = appearance
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = appearance
        window.contentView = host
        window.displayIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        host.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        appearance?.performAsCurrentDrawingAppearance { host.cacheDisplay(in: host.bounds, to: rep) }
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: url)
        window.close()
    }
}

/// Crash 2026-10-28 (macOS 26.2): `PopoverIdleHero.body` called `goalProgressSeconds`, which wrote an
/// observed cache. Writing observed state while a view is being drawn invalidates that view inside
/// layout; AppKit then throws "needs another Update Constraints pass" and the app quits.
/// Every read the views call while drawing must leave observed state alone.
@MainActor
final class ViewReadPathTests: XCTestCase {
    private var container: ModelContainer?

    func testReadsThatViewsMakeWhileDrawingNeverChangeObservedState() throws {
        let schema = Schema([
            Project.self, FocusSession.self, AppSettings.self, TimeSplit.self, BlockProfile.self, AppUsageRecord.self,
            AppUsageEntry.self, TaskIntent.self, CoachInterruption.self, InterventionAttempt.self, BreakLearningEvent.self,
            IdleDistractionItem.self, WeeklyPriority.self, PlannedBlock.self, ProjectGoal.self, GoalKeyResult.self,
            GoalProgressEntry.self, DailyTask.self,
        ])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        self.container = container
        let settings = AppSettings()
        container.mainContext.insert(settings)
        try container.mainContext.save()
        let vm = TimerViewModel()
        vm.systemIdleSecondsProvider = { 0 }
        vm.coachExploreSizes = false
        vm.configureForEvidence(modelContext: container.mainContext, settings: settings)

        // The calls the popover hero, tasks strip, notch, settings preview and insights make in `body`.
        let reads = {
            _ = vm.goalProgressSeconds(now: Date())
            _ = vm.goalProgressSeconds(now: Date().addingTimeInterval(120)) // past the cache window: recomputes
            _ = vm.todayTasks()
            _ = vm.dailyTaskStats()
            _ = vm.historyReaderActiveGoals()
            _ = vm.startLadderRecommendation(now: Date())
            _ = vm.regularMinutes
            _ = vm.dailyGoal(now: Date())
        }
        reads() // warm up any first-use work outside the tracked pass

        final class Flag: @unchecked Sendable { var raised = false }
        let invalidated = Flag()
        withObservationTracking {
            _ = vm.state
            _ = vm.todayFocusTime
            _ = vm.dailyTaskRevision
            reads()
        } onChange: {
            invalidated.raised = true
        }
        reads()
        XCTAssertFalse(invalidated.raised, "A read made while drawing changed observed state: SwiftUI would loop in layout and crash")
    }

    /// Freeze 2026-10-30: the break window called `startLadderRecommendation` (SwiftData fetches and a
    /// model fit) three times per render while a break overrun re-rendered it every second.
    func testBlockEndWindowNeverRunsTheLadderWhileDrawing() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let source = try String(
            contentsOf: testsDirectory.deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Sources/FocusFlow/Views/SessionCompleteWindow.swift"),
            encoding: .utf8
        )
        XCTAssertEqual(source.components(separatedBy: "startLadderRecommendation").count - 1, 1, "The ladder runs once, on appear")
        XCTAssertTrue(source.contains("coachAsk = timerVM.startLadderRecommendation()"), "…into @State, never from body")
        XCTAssertTrue(source.contains("BreakOverrunTitle()"), "Only the title view reads the per-second overtime tick")
    }

    /// After a block or its break, and after a 5/15 warm-up, the next block is your regular length
    /// (Settings ▸ Default block), not the warm-up again and not the idle ladder.
    func testNextBlockIsTheRegularLength() {
        XCTAssertEqual(TimerViewModel.regularMinutes(defaultBlockSeconds: 25 * 60, selectedMinutes: 5), 25, "A 5m warm-up doesn't repeat")
        XCTAssertEqual(TimerViewModel.regularMinutes(defaultBlockSeconds: nil, selectedMinutes: 15), 15, "No settings: the chosen size")
        XCTAssertEqual(TimerViewModel.regularMinutes(defaultBlockSeconds: 2 * 60, selectedMinutes: 3), 5, "Never below 5")
    }
}
