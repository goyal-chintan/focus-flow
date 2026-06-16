import XCTest
import SwiftData
@testable import FocusFlow

@MainActor
final class WakeRecoveryTests: XCTestCase {
    private var modelContainer: ModelContainer!
    private var modelContext: ModelContext!
    private var timerVM: TimerViewModel!
    private var settings: AppSettings!

    override func setUp() async throws {
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
            IdleDistractionItem.self
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

    func testPauseOnSleepAndWakeAutoResumeShortSleep() throws {
        // Start a session
        timerVM.startFocus()
        XCTAssertEqual(timerVM.state, .focusing)
        let initialRemaining = timerVM.remainingSeconds
        
        // Let's manually tick the timer down a bit
        timerVM.remainingSeconds -= 10
        let expectedRemaining = timerVM.remainingSeconds
        
        // Verify database has exactly 1 session
        var sessions = try modelContext.fetch(FetchDescriptor<FocusSession>())
        XCTAssertEqual(sessions.count, 1)
        
        // Sleep system (brief)
        timerVM.pauseForSystemSleep()
        XCTAssertEqual(timerVM.state, .paused)
        XCTAssertNotNil(timerVM.systemSleepStartTime)
        
        // Wake system after 5 seconds (within threshold)
        timerVM.resumeAfterSystemWake()
        XCTAssertEqual(timerVM.state, .focusing)
        XCTAssertNil(timerVM.systemSleepStartTime)
        
        // Assert remainingSeconds is preserved
        XCTAssertEqual(timerVM.remainingSeconds, expectedRemaining)
        
        // Assert no duplicate session was inserted
        sessions = try modelContext.fetch(FetchDescriptor<FocusSession>())
        XCTAssertEqual(sessions.count, 1)
    }

    func testPauseOnSleepAndWakeAutoResumeBriefOvertime() throws {
        // Start a session and transition to overtime
        timerVM.startFocus()
        XCTAssertEqual(timerVM.state, .focusing)
        
        timerVM.isOvertime = true
        timerVM.state = .idle
        
        // Sleep system (brief)
        timerVM.pauseForSystemSleep()
        
        // Verify timer is invalidated and nil
        XCTAssertNil(timerVM.timer)
        XCTAssertEqual(timerVM.state, .idle)
        XCTAssertTrue(timerVM.isOvertime)
        XCTAssertNotNil(timerVM.systemSleepStartTime)
        
        // Wake system after 5 seconds (within threshold)
        timerVM.resumeAfterSystemWake()
        
        // Verify timer is restored and ticking
        XCTAssertNotNil(timerVM.timer)
        XCTAssertEqual(timerVM.state, .idle)
        XCTAssertTrue(timerVM.isOvertime)
        XCTAssertNil(timerVM.systemSleepStartTime)
    }

    func testLongSleepTriggersWakeRecovery() throws {
        // Start a session
        timerVM.startFocus()
        XCTAssertEqual(timerVM.state, .focusing)
        let session = try XCTUnwrap(modelContext.fetch(FetchDescriptor<FocusSession>()).first)
        
        // Sleep system
        timerVM.pauseForSystemSleep()
        XCTAssertEqual(timerVM.state, .paused)
        
        // Manually adjust sleep start time to be 15 minutes ago
        timerVM.systemSleepStartTime = Date().addingTimeInterval(-900)
        
        // Wake system (long sleep > 10 min threshold)
        timerVM.resumeAfterSystemWake()
        
        XCTAssertEqual(timerVM.state, .idle)
        XCTAssertTrue(timerVM.showWakeRecoveryPrompt)
        XCTAssertTrue(timerVM.isWakeRecoveryActive)
        XCTAssertEqual(timerVM.wakeRecoverySession?.id, session.id)
    }

    func testResolveSaveToSleepStart() throws {
        timerVM.startFocus()
        let session = try XCTUnwrap(modelContext.fetch(FetchDescriptor<FocusSession>()).first)
        timerVM.pauseForSystemSleep()
        
        let sleepStart = Date().addingTimeInterval(-600)
        timerVM.systemSleepStartTime = sleepStart
        timerVM.resumeAfterSystemWake()
        
        timerVM.resolveWakeRecovery(choice: .saveToSleepStart)
        
        XCTAssertFalse(timerVM.showWakeRecoveryPrompt)
        XCTAssertEqual(session.endedAt, sleepStart)
        XCTAssertNotNil(timerVM.lastCompletedSession)
    }

    func testResolveKeepOvertime() throws {
        timerVM.startFocus()
        let session = try XCTUnwrap(modelContext.fetch(FetchDescriptor<FocusSession>()).first)
        timerVM.pauseForSystemSleep()
        
        let sleepStart = Date().addingTimeInterval(-600)
        timerVM.systemSleepStartTime = sleepStart
        timerVM.resumeAfterSystemWake()
        
        let wakeTime = try XCTUnwrap(timerVM.wakeRecoveryWakeTime)
        timerVM.resolveWakeRecovery(choice: .keepOvertime)
        
        XCTAssertFalse(timerVM.showWakeRecoveryPrompt)
        XCTAssertEqual(session.endedAt, wakeTime)
        XCTAssertNotNil(timerVM.lastCompletedSession)
    }

    func testResolveDiscard() {
        timerVM.startFocus()
        timerVM.pauseForSystemSleep()
        
        timerVM.systemSleepStartTime = Date().addingTimeInterval(-600)
        timerVM.resumeAfterSystemWake()
        
        timerVM.resolveWakeRecovery(choice: .discard)
        
        XCTAssertFalse(timerVM.showWakeRecoveryPrompt)
        XCTAssertFalse(timerVM.showSessionComplete)
        XCTAssertNil(timerVM.wakeRecoverySession)
    }
}
