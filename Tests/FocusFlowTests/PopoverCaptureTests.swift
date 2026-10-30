import XCTest
import SwiftData
import SwiftUI
@testable import FocusFlow

/// Layout captures of the popover with a real day behind it: a ranked project, a goal with a
/// count key result (so a lever and a "+1"), and today's tasks.
/// `FOCUSFLOW_CAPTURE_OUTPUT_DIR=<dir> swift test --filter PopoverCaptureTests` → `<dir>/popover_states/`.
@MainActor
final class PopoverCaptureTests: XCTestCase {
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

    func testCapturePopoverStatesWithTasksAndLever() throws {
        guard let dir = ProcessInfo.processInfo.environment["FOCUSFLOW_CAPTURE_OUTPUT_DIR"], !dir.isEmpty else {
            throw XCTSkip("Set FOCUSFLOW_CAPTURE_OUTPUT_DIR to capture")
        }
        let output = URL(fileURLWithPath: dir).appendingPathComponent("popover_states", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let (vm, context) = try makeVM()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let learning = Project(name: "Learning", color: "purple", icon: "graduationcap.fill")
        learning.priorityRank = 1
        learning.area = .learning
        context.insert(learning)
        let goal = ProjectGoal(title: "Interview-ready by 28 Nov", projectID: learning.id,
                               startDate: calendar.date(byAdding: .day, value: -10, to: today)!,
                               deadline: calendar.date(byAdding: .day, value: 20, to: today)!, isBossFight: true)
        let leet = GoalKeyResult(title: "LeetCode", kind: .count, target: 60, unit: "questions")
        context.insert(goal)
        context.insert(leet)
        goal.keyResults = [leet]
        try context.save()
        let solved = try XCTUnwrap(vm.addDailyTask(title: "2 LeetCode questions", projectID: learning.id, keyResultID: leet.id, amount: 2))
        vm.setDailyTask(solved, done: true, receipt: false)
        // A counted task one of three in, with the receipt of that +1 showing.
        let counted = try XCTUnwrap(vm.addDailyTask(title: "LeetCode questions", projectID: learning.id, keyResultID: leet.id, amount: 3))
        vm.stepDailyTask(counted, by: 1)
        let window = try XCTUnwrap(vm.addDailyTask(title: "Window functions practice set", projectID: learning.id))
        _ = vm.addDailyTask(title: "Ask Priya for a referral", projectID: learning.id)
        _ = vm.addDailyTask(title: "Review the system design notes")

        for dark in [false, true] {
            let suffix = dark ? "dark" : "light"
            vm.selectedProject = nil
            vm.pendingTaskID = window.id
            vm.pendingIntentText = window.title
            try write(dark: dark, vm: vm, context: context, height: 760, to: output.appendingPathComponent("idle_\(suffix).png"))
        }

        vm.selectedProject = learning
        vm.pendingTaskID = window.id
        vm.pendingIntentText = window.title
        XCTAssertTrue(vm.startFocus())
        XCTAssertEqual(vm.currentBlockTaskID, window.id)
        for dark in [false, true] {
            let suffix = dark ? "dark" : "light"
            try write(dark: dark, vm: vm, context: context, height: 760, to: output.appendingPathComponent("focusing_\(suffix).png"))
        }
        vm.pause()
        try write(dark: true, vm: vm, context: context, height: 760, to: output.appendingPathComponent("paused_dark.png"))
        vm.abandonSession()
    }

    private func write(dark: Bool, vm: TimerViewModel, context: ModelContext, height: CGFloat, to url: URL) throws {
        let size = CGSize(width: 342, height: height)
        let root = MenuBarPopoverView()
            .padding(16)
            .frame(width: size.width, height: size.height, alignment: .top)
            .background(dark ? Color(white: 0.12) : Color(white: 0.92))
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
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
        host.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        appearance?.performAsCurrentDrawingAppearance { host.cacheDisplay(in: host.bounds, to: rep) }
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: url)
        window.close()
    }
}
