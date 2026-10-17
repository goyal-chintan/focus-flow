import XCTest
import SwiftData
import AppKit
@testable import FocusFlow

/// The real AppKit host: a non-activating floating panel at the top right that never becomes
/// key, sizes to its content, replaces rather than stacks, and hides on demand.
@MainActor
final class CoachPanelControllerTests: XCTestCase {
    private var container: ModelContainer?
    private var defaultsSuite = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaultsSuite = "FocusFlowTests-\(UUID())"
        defaults = UserDefaults(suiteName: defaultsSuite)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: defaultsSuite)
        super.tearDown()
    }

    func testPanelIsNonActivatingFloatingTopRightAndDoesNotStack() throws {
        let schema = Schema([
            Project.self, FocusSession.self, AppSettings.self, TimeSplit.self, BlockProfile.self,
            AppUsageRecord.self, AppUsageEntry.self, TaskIntent.self, CoachInterruption.self,
            InterventionAttempt.self, BreakLearningEvent.self, IdleDistractionItem.self, WeeklyPriority.self,
        ])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        self.container = container
        defer {
            for window in NSApplication.shared.windows where window is CoachFloatingPanel { window.orderOut(nil) }
        }
        let settings = AppSettings()
        container.mainContext.insert(settings)
        let vm = TimerViewModel(defaults: defaults)
        vm.configureForEvidence(modelContext: container.mainContext, settings: settings)
        let controller = CoachPanelController(timerVM: vm, modelContainer: container)
        vm.coachPanelHost = controller
        let wasActive = NSApplication.shared.isActive

        let message = CoachMessageComposer.compose(CoachComposerInput(
            style: .challenger,
            trigger: .startNudge,
            facts: CoachFacts(),
            target: CoachStartTarget(minutes: 25, name: "Side App")
        ))
        vm.presentCoachPanel(CoachPanelPresentation(kind: .startNudge, message: message))
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.6))

        let panels = NSApplication.shared.windows.compactMap { $0 as? CoachFloatingPanel }
        XCTAssertEqual(panels.count, 1)
        let panel = try XCTUnwrap(panels.first)
        XCTAssertTrue(panel.isVisible)
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertEqual(panel.level, .floating)
        XCTAssertTrue(panel.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        // Key only after the user clicks it (⏎ / Esc); showing it never takes focus.
        XCTAssertTrue(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertFalse(panel.isKeyWindow, "Showing the panel must not take keyboard focus")
        XCTAssertEqual(NSApplication.shared.isActive, wasActive, "Showing the panel must not activate the app")
        XCTAssertEqual(panel.frame.width, CoachPanelView.width, accuracy: 0.5)
        XCTAssertGreaterThan(panel.frame.height, 80)
        if let screen = panel.screen {
            XCTAssertLessThanOrEqual(screen.visibleFrame.maxY - panel.frame.maxY, 20, "Pinned under the menu bar")
            XCTAssertGreaterThan(panel.frame.midX, screen.visibleFrame.midX, "Right side of the screen")
        }

        // A second prompt replaces the content in the same panel.
        vm.presentCoachPanel(CoachPanelPresentation(kind: .weeklyPriorities, message: CoachMessageComposer.compose(CoachComposerInput(
            style: .gentle, trigger: .weeklyPriorities, facts: CoachFacts(), target: CoachStartTarget(minutes: 25)
        ))))
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
        XCTAssertEqual(NSApplication.shared.windows.compactMap { $0 as? CoachFloatingPanel }.count, 1)

        vm.hideCoachPanel()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.5))
        XCTAssertFalse(panel.isVisible)
    }
}
