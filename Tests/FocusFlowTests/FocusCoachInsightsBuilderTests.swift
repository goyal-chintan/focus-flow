import XCTest
@testable import FocusFlow

final class FocusCoachInsightsBuilderTests: XCTestCase {

    let builder = FocusCoachInsightsBuilder()

    // MARK: - Helper: Sample Data

    private func makeSessions(count: Int, completed: Bool = true) -> [FocusCoachInsightsBuilder.SessionSnapshot] {
        (0..<count).map { i in
            let start = Date().addingTimeInterval(-Double(i) * 3600)
            return FocusCoachInsightsBuilder.SessionSnapshot(
                id: UUID(),
                type: "focus",
                duration: 1500,
                startedAt: start,
                endedAt: start.addingTimeInterval(1500),
                completed: completed
            )
        }
    }

    private func makeInterruptions(count: Int, legitimate: Bool = false) -> [FocusCoachInsightsBuilder.InterruptionSnapshot] {
        (0..<count).map { i in
            FocusCoachInsightsBuilder.InterruptionSnapshot(
                kind: .drift,
                reason: legitimate ? .meeting : .procrastinating,
                isLegitimate: legitimate,
                detectedAt: Date().addingTimeInterval(-Double(i) * 600)
            )
        }
    }

    private func makeAttempts(improved: Int, ignored: Int) -> [FocusCoachInsightsBuilder.AttemptSnapshot] {
        var results: [FocusCoachInsightsBuilder.AttemptSnapshot] = []
        for i in 0..<improved {
            let delivered = Date().addingTimeInterval(-Double(i) * 600)
            results.append(FocusCoachInsightsBuilder.AttemptSnapshot(
                kind: .quickPrompt,
                outcome: .improved,
                riskScore: 0.6,
                deliveredAt: delivered,
                resolvedAt: delivered.addingTimeInterval(30)
            ))
        }
        for i in 0..<ignored {
            let delivered = Date().addingTimeInterval(-Double(improved + i) * 600)
            results.append(FocusCoachInsightsBuilder.AttemptSnapshot(
                kind: .quickPrompt,
                outcome: .ignored,
                riskScore: 0.5,
                deliveredAt: delivered,
                resolvedAt: delivered.addingTimeInterval(90)
            ))
        }
        return results
    }

    private func makeAppUsage() -> [FocusCoachInsightsBuilder.AppUsageSnapshot] {
        [
            .init(appName: "Twitter", duringFocusSeconds: 300, category: "distracting"),
            .init(appName: "YouTube", duringFocusSeconds: 180, category: "distracting"),
            .init(appName: "Xcode", duringFocusSeconds: 2400, category: "productive"),
            .init(appName: "Safari", duringFocusSeconds: 600, category: "neutral"),
        ]
    }

    // MARK: - Tests

    func testBuildsStartLatencyTrend() {
        let report = builder.build(
            sessions: makeSessions(count: 5),
            interruptions: [],
            attempts: [],
            appUsage: []
        )
        XCTAssertGreaterThanOrEqual(report.avgStartLatencySeconds, 0)
        XCTAssertEqual(report.totalSessions, 5)
    }

    func testCompletionRateCalculation() {
        let completed = makeSessions(count: 7, completed: true)
        let incomplete = makeSessions(count: 3, completed: false)
        let report = builder.build(
            sessions: completed + incomplete,
            interruptions: [],
            attempts: [],
            appUsage: []
        )
        XCTAssertEqual(report.completionRate, 0.7, accuracy: 0.01)
    }

    func testInterventionWinRateCalculation() {
        let report = builder.build(
            sessions: makeSessions(count: 3),
            interruptions: [],
            attempts: makeAttempts(improved: 6, ignored: 4),
            appUsage: []
        )
        XCTAssertEqual(report.interventionWinRate, 0.6, accuracy: 0.01)
    }

    func testRanksTopTriggerFromAppUsage() {
        let report = builder.build(
            sessions: makeSessions(count: 3),
            interruptions: makeInterruptions(count: 2),
            attempts: [],
            appUsage: makeAppUsage()
        )
        XCTAssertFalse(report.topTriggers.isEmpty)
        XCTAssertEqual(report.topTriggers.first?.label, "Twitter")
    }

    func testFallsBackToInterruptionTriggersWhenNoDistracting() {
        let report = builder.build(
            sessions: makeSessions(count: 3),
            interruptions: makeInterruptions(count: 5),
            attempts: [],
            appUsage: [.init(appName: "Xcode", duringFocusSeconds: 2400, category: "productive")]
        )
        XCTAssertFalse(report.topTriggers.isEmpty)
        XCTAssertEqual(report.topTriggers.first?.label, "Drift")
    }

    func testLegitimateInterruptionRatio() {
        let legit = makeInterruptions(count: 3, legitimate: true)
        let avoidance = makeInterruptions(count: 7, legitimate: false)
        let report = builder.build(
            sessions: makeSessions(count: 3),
            interruptions: legit + avoidance,
            attempts: [],
            appUsage: []
        )
        XCTAssertEqual(report.legitimateInterruptionRatio, 0.3, accuracy: 0.01)
    }

    func testEmptyDataReturnsZeros() {
        let report = builder.build(sessions: [], interruptions: [], attempts: [], appUsage: [])
        XCTAssertEqual(report.totalSessions, 0)
        XCTAssertEqual(report.completionRate, 0)
        XCTAssertEqual(report.interventionWinRate, 0)
        XCTAssertTrue(report.topTriggers.isEmpty)
    }

    func testAvgSessionMinutesCalculation() {
        let report = builder.build(
            sessions: makeSessions(count: 4),
            interruptions: [],
            attempts: [],
            appUsage: []
        )
        XCTAssertEqual(report.avgSessionMinutes, 25)
    }

    func testBuildsRecoveryFunnelAndCalibration() {
        let now = Date()
        let attempts: [FocusCoachInsightsBuilder.AttemptSnapshot] = [
            .init(
                kind: .quickPrompt,
                outcome: .improved,
                riskScore: 0.82,
                deliveredAt: now.addingTimeInterval(-300),
                resolvedAt: now.addingTimeInterval(-220)
            ),
            .init(
                kind: .quickPrompt,
                outcome: .ignored,
                riskScore: 0.88,
                deliveredAt: now.addingTimeInterval(-200),
                resolvedAt: now.addingTimeInterval(-20)
            ),
            .init(
                kind: .strongPrompt,
                outcome: .improved,
                riskScore: 0.52,
                deliveredAt: now.addingTimeInterval(-180),
                resolvedAt: now.addingTimeInterval(-120)
            ),
            .init(
                kind: .quickPrompt,
                outcome: .snoozed,
                riskScore: 0.61,
                deliveredAt: now.addingTimeInterval(-100),
                resolvedAt: now.addingTimeInterval(-40)
            )
        ]

        let report = builder.build(
            sessions: makeSessions(count: 4),
            interruptions: makeInterruptions(count: 2),
            attempts: attempts,
            appUsage: []
        )

        XCTAssertEqual(report.recoveryFunnel.prompted, 4)
        XCTAssertEqual(report.recoveryFunnel.acted, 3)
        XCTAssertEqual(report.recoveryFunnel.recoveredWithin2Minutes, 2)
        XCTAssertEqual(report.confidenceCalibration.highRiskAttempts, 2)
        XCTAssertEqual(report.confidenceCalibration.lowRiskAttempts, 2)
    }
}
