import XCTest
import SwiftData
@testable import FocusFlow

@MainActor
final class CoachInterventionFixesTests: XCTestCase {
    private var retainedContainer: ModelContainer?
    private var defaultsSuite = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaultsSuite = "FocusFlowTests.\(UUID())"
        defaults = UserDefaults(suiteName: defaultsSuite)!
    }

    override func tearDown() {
        TestDefaults.remove(defaultsSuite)
        super.tearDown()
    }

    // MARK: - Declassify uses the same key as classify (session review undo)

    func testDeclassifyRemovesPlannedAllowanceForApp() throws {
        let vm = try makeConfiguredViewModel()
        defer { AppUsageTracker.shared.stop() }
        let entry = AppUsageTracker.SessionDistractingEntry(
            bundleIdentifier: "com.example.Game",
            displayLabel: "Game",
            normalizedKey: "app:com.example.game",
            seconds: 120
        )

        vm.classifySessionApp(entry: entry, isPlanned: true)
        XCTAssertTrue(plannedAllowance(vm, key: "com.example.game"))

        vm.declassifySessionApp(entry: entry)
        XCTAssertFalse(plannedAllowance(vm, key: "com.example.game"))
    }

    func testDeclassifyRemovesPlannedAllowanceForWebsite() throws {
        let vm = try makeConfiguredViewModel()
        defer { AppUsageTracker.shared.stop() }
        let entry = AppUsageTracker.SessionDistractingEntry(
            bundleIdentifier: "com.google.Chrome",
            displayLabel: "reddit.com",
            normalizedKey: "domain:reddit.com",
            seconds: 90
        )

        vm.classifySessionApp(entry: entry, isPlanned: true)
        XCTAssertTrue(plannedAllowance(vm, key: "reddit.com"))

        vm.declassifySessionApp(entry: entry)
        XCTAssertFalse(plannedAllowance(vm, key: "reddit.com"))
    }

    // MARK: - Dismissing the intervention window records an outcome (B12)

    func testDismissWithoutActionRecordsDismissedOutcome() throws {
        let vm = try makeConfiguredViewModel()
        defer { AppUsageTracker.shared.stop() }
        vm.coachEngine.recordDeliveredIntervention(kind: .quickPrompt)
        vm.showCoachInterventionWindow = true

        vm.dismissCoachInterventionWindow()

        XCTAssertEqual(vm.coachEngine.store.attempts.first?.outcome, .dismissed)
    }

    func testDismissAfterSuccessfulActionDoesNotOverwriteOutcome() throws {
        let vm = try makeConfiguredViewModel()
        defer { AppUsageTracker.shared.stop() }
        vm.coachEngine.recordDeliveredIntervention(kind: .quickPrompt)
        vm.showCoachInterventionWindow = true

        XCTAssertTrue(vm.handleCoachAction(.returnNow))
        // CoachInterventionWindowView calls dismiss() after a successful action.
        vm.dismissCoachInterventionWindow()

        XCTAssertEqual(vm.coachEngine.store.attempts.first?.outcome, .improved)
    }

    // MARK: - Start-now uses the recommended length without changing the chosen one (B15)

    func testStartFocusNowUsesRecommendedMinutesAndRestoresSelection() throws {
        let vm = try makeConfiguredViewModel()
        defer { AppUsageTracker.shared.stop() }
        vm.selectedMinutes = 25
        vm.idleStarterRecommendedMinutes = 45

        XCTAssertTrue(vm.handleCoachAction(.startFocusNow))

        XCTAssertEqual(vm.totalSeconds, 45 * 60)
        XCTAssertEqual(vm.selectedMinutes, 25)
    }

    // MARK: - Helpers

    private func makeConfiguredViewModel() throws -> TimerViewModel {
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
            IdleDistractionItem.self,
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        // Keep the container alive for the test: the view model's context must outlive the helper.
        retainedContainer = container
        let vm = TimerViewModel(defaults: defaults)
        vm.systemIdleSecondsProvider = { 0 } // at the desk (v4 presence gate)
        vm.coachExploreSizes = false
        vm.configure(modelContext: container.mainContext)
        return vm
    }

    private func plannedAllowance(_ vm: TimerViewModel, key: String) -> Bool {
        vm.driftMemoryStore.sessionScopedAllowance(projectId: nil, workMode: nil, appOrDomain: key)
    }
}
