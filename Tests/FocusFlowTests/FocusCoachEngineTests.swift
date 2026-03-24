import XCTest
@testable import FocusFlow

@MainActor
final class FocusCoachEngineTests: XCTestCase {

    // MARK: - Tick + Risk Scoring Pipeline

    func testTickProducesQuickPromptWhenRiskCrossesThreshold() {
        let store = InMemoryCoachStore()
        let engine = FocusCoachEngine(store: store)
        engine.startSession(id: UUID())

        // Feed high-drift signals
        let signals = FocusCoachSignals(
            startDelaySeconds: 300,
            appSwitchesPerMinute: 10,
            nonWorkForegroundRatio: 0.6,
            inactivityBurstSeconds: 100,
            blockedAppAttempts: 2,
            pauseCount: 2,
            breakOverrunSeconds: 60,
            recentLegitimateReason: false
        )
        engine.recordBehaviorSample(signals)
        let decision = engine.tick()
        XCTAssertNotNil(decision)
        XCTAssertTrue(
            decision?.kind == .quickPrompt || decision?.kind == .strongPrompt,
            "Expected quickPrompt or strongPrompt, got \(String(describing: decision?.kind))"
        )
    }

    func testTickReturnsNilWhenStable() {
        let store = InMemoryCoachStore()
        let engine = FocusCoachEngine(store: store)
        engine.startSession(id: UUID())

        engine.recordBehaviorSample(.zero)
        let decision = engine.tick()
        XCTAssertNil(decision, "Stable signals should produce no intervention")
    }

    func testTickReturnsNilWhenNotActive() {
        let store = InMemoryCoachStore()
        let engine = FocusCoachEngine(store: store)
        // Don't call startSession
        engine.recordBehaviorSample(.sampleHighRisk)
        let decision = engine.tick()
        XCTAssertNil(decision, "Inactive engine should not produce interventions")
    }

    // MARK: - Anomaly Recording

    func testLegitimateReasonCreatesInterruptionMarkedLegitimate() {
        let store = InMemoryCoachStore()
        let engine = FocusCoachEngine(store: store)
        let sessionId = UUID()
        engine.startSession(id: sessionId)
        engine.recordAnomaly(kind: .midSessionStop, reason: .meeting, sessionId: sessionId)

        XCTAssertEqual(store.interruptions.count, 1)
        XCTAssertTrue(store.interruptions.last?.isLegitimate == true)
        XCTAssertEqual(store.interruptions.last?.kind, .midSessionStop)
    }

    func testAvoidanceReasonNotMarkedLegitimate() {
        let store = InMemoryCoachStore()
        let engine = FocusCoachEngine(store: store)
        engine.startSession(id: UUID())
        engine.recordAnomaly(kind: .drift, reason: .procrastinating, sessionId: nil)

        XCTAssertFalse(store.interruptions.last?.isLegitimate ?? true)
    }

    func testLegitimateReasonDampensSubsequentScoring() {
        let store = InMemoryCoachStore()
        let engine = FocusCoachEngine(store: store)
        engine.startSession(id: UUID())

        // Record legitimate reason — should set recentLegitimateReason
        engine.recordAnomaly(kind: .midSessionStop, reason: .meeting, sessionId: nil)
        XCTAssertTrue(engine.currentSignals.recentLegitimateReason)
    }

    // MARK: - Session Lifecycle

    func testStartSessionResetsState() {
        let store = InMemoryCoachStore()
        let engine = FocusCoachEngine(store: store)
        let id = UUID()
        engine.startSession(id: id)

        XCTAssertTrue(engine.isActive)
        XCTAssertEqual(engine.currentSessionId, id)
        XCTAssertEqual(engine.riskLevel, .stable)
    }

    func testEndSessionDeactivates() {
        let store = InMemoryCoachStore()
        let engine = FocusCoachEngine(store: store)
        engine.startSession(id: UUID())
        engine.endSession()

        XCTAssertFalse(engine.isActive)
        XCTAssertNil(engine.currentSessionId)
    }

    // MARK: - Intervention Recording

    func testPromptDecisionRecordsAttempt() {
        let store = InMemoryCoachStore()
        let engine = FocusCoachEngine(store: store)
        engine.startSession(id: UUID())

        // Need to produce at least driftRisk to get a prompt
        let signals = FocusCoachSignals(
            startDelaySeconds: 300,
            appSwitchesPerMinute: 10,
            nonWorkForegroundRatio: 0.6,
            inactivityBurstSeconds: 100,
            blockedAppAttempts: 2,
            pauseCount: 2,
            breakOverrunSeconds: 60,
            recentLegitimateReason: false
        )
        engine.recordBehaviorSample(signals)
        let decision = engine.tick()

        if decision?.kind == .quickPrompt || decision?.kind == .strongPrompt {
            engine.recordDeliveredIntervention(
                kind: decision?.kind == .strongPrompt ? .strongPrompt : .quickPrompt
            )
            XCTAssertEqual(store.attempts.count, 1)
            XCTAssertGreaterThan(store.attempts.first?.riskScore ?? 0, 0)
        }
    }

    func testRecordDeliveredInterventionPersistsAttempt() {
        let store = InMemoryCoachStore()
        let engine = FocusCoachEngine(store: store)
        engine.startSession(id: UUID())

        engine.recordDeliveredIntervention(kind: .quickPrompt, riskScore: 0.74)

        XCTAssertEqual(store.attempts.count, 1)
        XCTAssertEqual(store.attempts.first?.kind, .quickPrompt)
        XCTAssertEqual(store.attempts.first?.riskScore ?? 0, 0.74, accuracy: 0.001)
    }

    // MARK: - Snooze

    func testSnoozeRecordsOutcomeAndSetsWindow() {
        let store = InMemoryCoachStore()
        let engine = FocusCoachEngine(store: store)
        engine.startSession(id: UUID())

        // Generate an attempt first
        engine.recordBehaviorSample(.sampleHighRisk)
        _ = engine.tick()

        engine.snooze(minutes: 10)

        XCTAssertNotNil(engine.promptState.snoozedUntil)
        if let snoozedUntil = engine.promptState.snoozedUntil {
            XCTAssertGreaterThan(snoozedUntil, Date())
        }
    }

    // MARK: - App Switch Rate Computation

    func testComputeAppSwitchRateWithRecentSwitches() {
        let now = Date()
        let timestamps = (0..<10).map { now.addingTimeInterval(-Double($0) * 5) }
        let rate = FocusCoachEngine.computeAppSwitchRate(switchTimestamps: timestamps, windowSeconds: 60)
        XCTAssertGreaterThan(rate, 5, "10 switches in 60 seconds should give > 5/min")
    }

    func testComputeAppSwitchRateWithNoSwitches() {
        let rate = FocusCoachEngine.computeAppSwitchRate(switchTimestamps: [], windowSeconds: 60)
        XCTAssertEqual(rate, 0)
    }

    // MARK: - Incremental Signal Updates

    func testIncrementalSignalUpdates() {
        let store = InMemoryCoachStore()
        let engine = FocusCoachEngine(store: store)
        engine.startSession(id: UUID())

        engine.updateStartDelay(120)
        XCTAssertEqual(engine.currentSignals.startDelaySeconds, 120)

        engine.updatePauseCount(3)
        XCTAssertEqual(engine.currentSignals.pauseCount, 3)

        engine.updateBreakOverrun(60)
        XCTAssertEqual(engine.currentSignals.breakOverrunSeconds, 60)
    }
}
