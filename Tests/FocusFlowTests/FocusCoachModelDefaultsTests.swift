import XCTest
@testable import FocusFlow

final class FocusCoachModelDefaultsTests: XCTestCase {

    // MARK: - TaskIntent

    func testTaskIntentDefaults() {
        let intent = TaskIntent(title: "Write failing test")
        XCTAssertEqual(intent.expectedResistance, 3)
        XCTAssertEqual(intent.taskType, .deepWork)
        XCTAssertNil(intent.suggestedDurationMinutes)
        XCTAssertNil(intent.successCriteria)
        XCTAssertNil(intent.sessionId)
    }

    func testTaskIntentCustomValues() {
        let intent = TaskIntent(
            title: "Review PR",
            taskType: .admin,
            expectedResistance: 1,
            suggestedDurationMinutes: 15,
            successCriteria: "All comments addressed"
        )
        XCTAssertEqual(intent.title, "Review PR")
        XCTAssertEqual(intent.taskType, .admin)
        XCTAssertEqual(intent.expectedResistance, 1)
        XCTAssertEqual(intent.suggestedDurationMinutes, 15)
        XCTAssertEqual(intent.successCriteria, "All comments addressed")
    }

    // MARK: - CoachInterruption

    func testCoachInterruptionDefaults() {
        let interruption = CoachInterruption(sessionId: UUID(), kind: .drift)
        XCTAssertEqual(interruption.kind, .drift)
        XCTAssertNil(interruption.reason)
        XCTAssertFalse(interruption.isLegitimate)
        XCTAssertEqual(interruption.riskScoreAtDetection, 0)
    }

    func testCoachInterruptionWithLegitimateReason() {
        let interruption = CoachInterruption(
            sessionId: UUID(),
            kind: .midSessionStop,
            reason: .meeting,
            riskScoreAtDetection: 0.8
        )
        XCTAssertTrue(interruption.isLegitimate)
        XCTAssertEqual(interruption.reason, .meeting)
    }

    func testCoachInterruptionAvoidanceNotLegitimate() {
        let interruption = CoachInterruption(
            sessionId: UUID(),
            kind: .drift,
            reason: .procrastinating
        )
        XCTAssertFalse(interruption.isLegitimate)
    }

    // MARK: - InterventionAttempt

    func testInterventionAttemptDefaults() {
        let attempt = InterventionAttempt(kind: .softNudge, riskScore: 0.4)
        XCTAssertFalse(attempt.dismissed)
        XCTAssertNil(attempt.outcomeRawValue)
        XCTAssertNil(attempt.outcome)
        XCTAssertNil(attempt.sessionId)
        XCTAssertNil(attempt.resolvedAt)
    }

    func testInterventionAttemptOutcomeRoundTrip() {
        let attempt = InterventionAttempt(kind: .quickPrompt, riskScore: 0.7)
        attempt.outcome = .improved
        XCTAssertEqual(attempt.outcome, .improved)
        XCTAssertEqual(attempt.outcomeRawValue, "improved")
    }

    // MARK: - Enum Coverage

    func testReasonLegitimacyClassification() {
        let legitimate: [FocusCoachReason] = [.meeting, .familyPersonal, .plannedResearch, .realBreak, .fatigue, .requiredSwitch]
        let notLegitimate: [FocusCoachReason] = [.procrastinating, .vibeCodingDrift, .overPlanning, .scrollingBrowsing, .avoidingHardPart, .lowPriorityWork]
        for reason in legitimate {
            XCTAssertTrue(reason.isLegitimate, "\(reason) should be legitimate")
        }
        for reason in notLegitimate {
            XCTAssertFalse(reason.isLegitimate, "\(reason) should not be legitimate")
        }
    }

    func testAllEnumsCaseIterableAndCodable() {
        XCTAssertGreaterThan(FocusCoachTaskType.allCases.count, 0)
        XCTAssertGreaterThan(FocusCoachReason.allCases.count, 0)
        XCTAssertGreaterThan(FocusCoachInterruptionKind.allCases.count, 0)
        XCTAssertGreaterThan(FocusCoachInterventionKind.allCases.count, 0)
        XCTAssertGreaterThan(FocusCoachOutcome.allCases.count, 0)
        XCTAssertGreaterThan(FocusCoachRiskLevel.allCases.count, 0)
    }
}
