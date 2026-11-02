import XCTest
@testable import FocusFlow

/// The idle popover follows the picked project (2026-10-30): no all-projects task list, the
/// project's own lever, and only its tasks in the goal field's menu.
final class PopoverProjectScopeTests: XCTestCase {
    private let learning = UUID()
    private let work = UUID()

    private func lever(_ action: String, project: UUID?) -> DailyLever {
        DailyLever(id: UUID(), goalTitle: action, projectID: project, action: action,
                   reason: "need 1/day", status: .behind, urgency: 1)
    }

    func testLeverFollowsThePickedProject() {
        let levers = [lever("SQL Questions: 3 today", project: learning), lever("Ship the EDW doc", project: work)]
        XCTAssertEqual(PopoverProjectScope.lever(levers, projectID: nil)?.action, "SQL Questions: 3 today")
        XCTAssertEqual(PopoverProjectScope.lever(levers, projectID: work)?.action, "Ship the EDW doc")
        XCTAssertNil(PopoverProjectScope.lever(levers, projectID: UUID()), "A project without a lever never shows another project's")
    }

    @MainActor
    func testGoalMenuListsOnlyThePickedProjectsOpenTasks() {
        let day = Date()
        let sql = DailyTask(title: "Window functions", day: day, projectID: learning)
        let epic = DailyTask(title: "Create the backup Epic", day: day, projectID: work)
        let loose = DailyTask(title: "Call the bank", day: day)
        let done = DailyTask(title: "Read chapter 3", day: day, projectID: learning)
        done.isDone = true
        let all = [sql, epic, loose, done]
        XCTAssertEqual(PopoverProjectScope.openTasks(all, projectID: learning).map(\.title), ["Window functions"])
        XCTAssertEqual(PopoverProjectScope.openTasks(all, projectID: work).map(\.title), ["Create the backup Epic"])
        XCTAssertEqual(PopoverProjectScope.openTasks(all, projectID: nil).count, 3)
    }

    /// Source contract: the idle popover has no task strip and one "Working on" label.
    func testIdlePopoverHasNoTaskStrip() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let popover = try String(contentsOf: root.appendingPathComponent("Sources/FocusFlow/Views/MenuBar/MenuBarPopoverView.swift"), encoding: .utf8)
        XCTAssertFalse(popover.contains("PopoverTasksStrip"))
        XCTAssertEqual(popover.components(separatedBy: #"IdleSectionLabel("Working on")"#).count - 1, 1)
        XCTAssertTrue(popover.contains(#"IdleSectionLabel("Project")"#))
    }

    /// Block-end footer (review 2026-10-30): the task is a caption, not inside the Start label, and
    /// the break pill is the same component as the others.
    func testBlockEndFooterKeepsTheTaskOutOfTheButton() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let window = try String(contentsOf: root.appendingPathComponent("Sources/FocusFlow/Views/SessionCompleteWindow.swift"), encoding: .utf8)
        XCTAssertFalse(window.contains(#"Start \(nextMinutes)m · \(task.title)"#))
        XCTAssertTrue(window.contains(#"Text("Next: \(task.title)")"#))
        XCTAssertTrue(window.contains(#"LiquidActionButton(title: "Start \(small)m""#), "Both start pills say Start and share the row")
        XCTAssertFalse(window.contains("primaryAction:"), "No native split menu in the footer")
    }
}
