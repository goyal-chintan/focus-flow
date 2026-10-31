import XCTest
import SwiftData
@testable import FocusFlow

/// A break that runs past its time is break time: never a block's overtime, never focus time.
/// Both arrive as `.idle` + `isOvertime`; `isBreakOvertime` / `isFocusOvertime` tell them apart.
@MainActor
final class BreakOverrunTests: XCTestCase {
    private var modelContainer: ModelContainer!
    private var modelContext: ModelContext!
    private var timerVM: TimerViewModel!
    private var settings: AppSettings!

    override func setUp() async throws {
        let schema = Schema([
            Project.self, FocusSession.self, AppSettings.self, TimeSplit.self, BlockProfile.self,
            AppUsageRecord.self, AppUsageEntry.self, TaskIntent.self, CoachInterruption.self,
            InterventionAttempt.self, BreakLearningEvent.self, IdleDistractionItem.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: schema, configurations: config)
        modelContext = modelContainer.mainContext

        settings = AppSettings()
        settings.autoStopOnSleepThresholdMinutes = 10
        modelContext.insert(settings)
        try modelContext.save()

        timerVM = TimerViewModel()
        timerVM.configureForEvidence(modelContext: modelContext, settings: settings)
    }

    override func tearDown() async throws {
        AppUsageTracker.shared.stop()
        timerVM = nil
        settings = nil
        modelContext = nil
        modelContainer = nil
        try await super.tearDown()
    }

    /// Runs a real one-second break on the main run loop until it has run over.
    private func runBreakIntoOverrun() {
        timerVM.startBreak(overrideDuration: 1)
        XCTAssertEqual(timerVM.state, .onBreak(.shortBreak))
        RunLoop.main.run(until: Date().addingTimeInterval(3.5))
        XCTAssertTrue(timerVM.isOvertime, "the break ended and is running over")
    }

    func testBreakThatRunsOverIsNotFocusTime() {
        let focusBefore = timerVM.todayFocusTime
        runBreakIntoOverrun()

        XCTAssertGreaterThan(timerVM.overtimeSeconds, 0)
        XCTAssertTrue(timerVM.isBreakOvertime)
        XCTAssertFalse(timerVM.isFocusOvertime)
        XCTAssertEqual(timerVM.todayFocusTime, focusBefore, "overrun seconds are break time, not today's focus")
    }

    func testBreakOverrunAndBlockOvertimeAreToldApart() {
        timerVM.seedEvidenceCompletionState(sessionType: .shortBreak, project: nil, customLabel: nil, duration: 300, overtimeSeconds: 90)
        XCTAssertTrue(timerVM.isBreakOvertime)
        XCTAssertFalse(timerVM.isFocusOvertime)

        timerVM.seedEvidenceCompletionState(sessionType: .focus, project: nil, customLabel: "Write", duration: 1500, overtimeSeconds: 90)
        XCTAssertTrue(timerVM.isFocusOvertime)
        XCTAssertFalse(timerVM.isBreakOvertime)
    }

    func testNotchShowsABreakOverrunAsBreakOverNotBlockDone() {
        typealias Mode = NotchSnapshot.Mode
        XCTAssertEqual(Mode.from(state: .idle, isOvertime: true, isBreakOvertime: true, isBreakPaused: false), .breakOver)
        XCTAssertEqual(Mode.from(state: .idle, isOvertime: true, isBreakOvertime: false, isBreakPaused: false), .overtime)
        XCTAssertEqual(Mode.from(state: .idle, isOvertime: false, isBreakOvertime: false, isBreakPaused: false), .idle)
        XCTAssertEqual(Mode.from(state: .focusing, isOvertime: false, isBreakOvertime: false, isBreakPaused: false), .focusing)
        XCTAssertEqual(Mode.from(state: .paused, isOvertime: false, isBreakOvertime: false, isBreakPaused: false), .paused)
        XCTAssertEqual(Mode.from(state: .onBreak(.shortBreak), isOvertime: false, isBreakOvertime: false, isBreakPaused: true), .onBreak(paused: true))
    }

    func testStartingTheNextBlockFromABreakOverrunEndsTheBreak() throws {
        runBreakIntoOverrun()
        timerVM.continueAfterCompletion(action: .continueFocusing)

        XCTAssertEqual(timerVM.state, .focusing)
        XCTAssertFalse(timerVM.isOvertime)
        let breakSession = try XCTUnwrap(modelContext.fetch(FetchDescriptor<FocusSession>()).first { $0.type == .shortBreak })
        XCTAssertNotNil(breakSession.endedAt)
        XCTAssertGreaterThan(breakSession.actualDuration, 1, "the overrun stays on the break session")
    }

    func testFinishDuringABreakEndsItWithoutABlockEndWindow() {
        timerVM.startBreak(overrideDuration: 300)
        timerVM.stopForReflection()

        XCTAssertEqual(timerVM.state, .idle)
        XCTAssertFalse(timerVM.isManualStop, "a break is not a block to log")
        XCTAssertFalse(timerVM.showSessionComplete)
        XCTAssertNil(timerVM.completedBlockContext)
        XCTAssertNil(timerVM.lastCompletedFocusSession)
    }

    func testShortSleepDuringBreakOverrunKeepsCountingWithoutAutoResume() {
        settings.autoResumeOnWake = false
        runBreakIntoOverrun()

        timerVM.pauseForSystemSleep()
        let before = timerVM.overtimeSeconds
        timerVM.systemSleepStartTime = Date().addingTimeInterval(-120) // under the 10-minute threshold
        timerVM.resumeAfterSystemWake()

        XCTAssertTrue(timerVM.isBreakOvertime)
        XCTAssertGreaterThanOrEqual(timerVM.overtimeSeconds, before + 120, "the sleep was more break overrun")
        let afterWake = timerVM.overtimeSeconds
        RunLoop.main.run(until: Date().addingTimeInterval(1.5))
        XCTAssertGreaterThan(timerVM.overtimeSeconds, afterWake, "the overrun counter runs again after wake")
    }

    func testWakeRecoveryOfABreakIsNotTheLastFocusBlock() throws {
        timerVM.startBreak(overrideDuration: 300)
        timerVM.pauseForSystemSleep()
        XCTAssertTrue(timerVM.isBreakPaused)
        let sleepStart = Date().addingTimeInterval(-900)
        timerVM.systemSleepStartTime = sleepStart
        timerVM.resumeAfterSystemWake()

        XCTAssertTrue(timerVM.isWakeRecoveryActive)
        XCTAssertFalse(timerVM.isBreakPaused, "the paused break is over; the next break must not start paused")

        timerVM.resolveWakeRecovery(choice: .saveToSleepStart)
        XCTAssertTrue(timerVM.lastCompletionWasBreak)
        XCTAssertEqual(timerVM.lastCompletedSession?.type, .shortBreak)
        XCTAssertNil(timerVM.lastCompletedFocusSession, "a break never stands in for the last focus block")
        XCTAssertNil(timerVM.lastCompletedDuration)
    }

    func testNextBreakNeverStartsPaused() {
        timerVM.startBreak(overrideDuration: 300)
        timerVM.pauseBreak()
        XCTAssertTrue(timerVM.isBreakPaused)
        timerVM.state = .idle // a path that left the flag behind
        timerVM.startBreak(overrideDuration: 300)
        XCTAssertFalse(timerVM.isBreakPaused)
    }
}
