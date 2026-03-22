import XCTest
@testable import FocusFlow

final class FocusCoachInterventionPolicyTests: XCTestCase {

    let policy = FocusCoachInterventionPolicy()

    // MARK: - Snooze Gate

    func testSnoozeSuppressesIntervention() {
        let now = Date()
        let state = FocusCoachPromptState(
            promptCountThisSession: 1,
            consecutiveHighRiskWindows: 2,
            snoozedUntil: now.addingTimeInterval(300)
        )
        let decision = policy.decide(now: now, risk: .highRisk, state: state, promptBudget: 4)
        XCTAssertEqual(decision.kind, .none)
    }

    func testExpiredSnoozeAllowsIntervention() {
        let now = Date()
        let state = FocusCoachPromptState(
            promptCountThisSession: 1,
            consecutiveHighRiskWindows: 2,
            snoozedUntil: now.addingTimeInterval(-10) // expired
        )
        let decision = policy.decide(now: now, risk: .highRisk, state: state, promptBudget: 4)
        XCTAssertNotEqual(decision.kind, .none)
    }

    // MARK: - Budget Gate

    func testBudgetExhaustedOnlyAllowsSoftStrip() {
        let state = FocusCoachPromptState(
            promptCountThisSession: 4,
            consecutiveHighRiskWindows: 3,
            snoozedUntil: nil
        )
        let decision = policy.decide(now: Date(), risk: .highRisk, state: state, promptBudget: 4)
        XCTAssertEqual(decision.kind, .softStrip)
    }

    func testBudgetExhaustedStableReturnsNone() {
        let state = FocusCoachPromptState(
            promptCountThisSession: 4,
            consecutiveHighRiskWindows: 0,
            snoozedUntil: nil
        )
        let decision = policy.decide(now: Date(), risk: .stable, state: state, promptBudget: 4)
        XCTAssertEqual(decision.kind, .none)
    }

    // MARK: - Cooldown Gate

    func testCooldownSuppressesPromptReturnsStripForHighRisk() {
        let now = Date()
        let state = FocusCoachPromptState(
            promptCountThisSession: 1,
            consecutiveHighRiskWindows: 2,
            snoozedUntil: nil,
            lastPromptAt: now.addingTimeInterval(-30) // 30s ago, within 90s cooldown
        )
        let decision = policy.decide(now: now, risk: .highRisk, state: state, promptBudget: 4)
        XCTAssertEqual(decision.kind, .softStrip)
    }

    func testCooldownExpiredAllowsPrompt() {
        let now = Date()
        let state = FocusCoachPromptState(
            promptCountThisSession: 1,
            consecutiveHighRiskWindows: 2,
            snoozedUntil: nil,
            lastPromptAt: now.addingTimeInterval(-100) // 100s ago, past 90s cooldown
        )
        let decision = policy.decide(now: now, risk: .highRisk, state: state, promptBudget: 4)
        XCTAssertNotEqual(decision.kind, .softStrip)
        XCTAssertNotEqual(decision.kind, .none)
    }

    // MARK: - Risk Level Decisions

    func testStableReturnsNone() {
        let decision = policy.decide(now: Date(), risk: .stable, state: .initial, promptBudget: 4)
        XCTAssertEqual(decision.kind, .none)
    }

    func testDriftRiskReturnsQuickPrompt() {
        let decision = policy.decide(now: Date(), risk: .driftRisk, state: .initial, promptBudget: 4)
        XCTAssertEqual(decision.kind, .quickPrompt)
        XCTAssertFalse(decision.suggestedActions.isEmpty)
    }

    func testHighRiskFirstTimeReturnsQuickPrompt() {
        let state = FocusCoachPromptState(
            promptCountThisSession: 0,
            consecutiveHighRiskWindows: 1,
            snoozedUntil: nil
        )
        let decision = policy.decide(now: Date(), risk: .highRisk, state: state, promptBudget: 4)
        XCTAssertEqual(decision.kind, .quickPrompt)
    }

    func testEscalatesToStrongAfterRepeatedHighRisk() {
        let state = FocusCoachPromptState(
            promptCountThisSession: 2,
            consecutiveHighRiskWindows: 3,
            snoozedUntil: nil
        )
        let decision = policy.decide(now: Date(), risk: .highRisk, state: state, promptBudget: 4)
        XCTAssertEqual(decision.kind, .strongPrompt)
    }

    // MARK: - Actions

    func testStrongPromptIncludesAllActions() {
        let state = FocusCoachPromptState(
            promptCountThisSession: 1,
            consecutiveHighRiskWindows: 3,
            snoozedUntil: nil
        )
        let decision = policy.decide(now: Date(), risk: .highRisk, state: state, promptBudget: 4)
        XCTAssertTrue(decision.suggestedActions.contains(.returnNow))
        XCTAssertTrue(decision.suggestedActions.contains(.cleanRestart5m))
        XCTAssertTrue(decision.suggestedActions.contains(.snooze10m))
    }
}
