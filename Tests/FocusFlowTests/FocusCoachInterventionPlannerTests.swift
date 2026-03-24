import XCTest
@testable import FocusFlow

final class FocusCoachInterventionPlannerTests: XCTestCase {

    private let planner = FocusCoachInterventionPlanner()

    func testBalancedQuickPromptStaysQuick() {
        let surface = planner.surfaceForActiveDecision(
            decisionKind: .quickPrompt,
            mode: .balanced,
            riskScore: 0.7,
            strongShownCount: 0,
            maxStrongPrompts: 2
        )
        XCTAssertEqual(surface, .quickPrompt)
    }

    func testAdaptiveStrictElevatesHighQuickToStrong() {
        let surface = planner.surfaceForActiveDecision(
            decisionKind: .quickPrompt,
            mode: .adaptiveStrict,
            riskScore: 0.8,
            strongShownCount: 0,
            maxStrongPrompts: 2
        )
        XCTAssertEqual(surface, .strongWindow)
    }

    func testStrongDecisionFallsBackToQuickWhenStrongBudgetExhausted() {
        let surface = planner.surfaceForActiveDecision(
            decisionKind: .strongPrompt,
            mode: .balanced,
            riskScore: 0.9,
            strongShownCount: 2,
            maxStrongPrompts: 2
        )
        XCTAssertEqual(surface, .quickPrompt)
    }

    func testIdleStarterRequiresBothConfidenceAndOpportunity() {
        XCTAssertTrue(planner.shouldShowIdleStarter(
            driftConfidence: 0.78,
            focusOpportunity: 0.72,
            mode: .balanced
        ))
        XCTAssertFalse(planner.shouldShowIdleStarter(
            driftConfidence: 0.78,
            focusOpportunity: 0.3,
            mode: .balanced
        ))
        XCTAssertFalse(planner.shouldShowIdleStarter(
            driftConfidence: 0.4,
            focusOpportunity: 0.8,
            mode: .balanced
        ))
    }

    func testRouteStrongDecisionToStrongWindow() {
        let routing = planner.routeActiveDecision(
            FocusCoachDecision(
                kind: .strongPrompt,
                suggestedActions: [.returnNow, .cleanRestart5m, .snooze10m],
                message: "Sustained drift"
            ),
            mode: .balanced,
            riskScore: 0.88,
            strongShownCount: 0,
            maxStrongPrompts: 2
        )

        XCTAssertEqual(routing.quickPromptDecision?.kind, nil)
        XCTAssertEqual(routing.strongWindowDecision?.kind, .strongPrompt)
        XCTAssertTrue(routing.didConsumeStrongBudget)
    }

    func testRouteStrongDecisionFallsBackToQuickWhenStrongBudgetIsExhausted() {
        let routing = planner.routeActiveDecision(
            FocusCoachDecision(
                kind: .strongPrompt,
                suggestedActions: [.returnNow, .cleanRestart5m, .snooze10m],
                message: "Sustained drift"
            ),
            mode: .balanced,
            riskScore: 0.91,
            strongShownCount: 2,
            maxStrongPrompts: 2
        )

        XCTAssertEqual(routing.quickPromptDecision?.kind, .quickPrompt)
        XCTAssertNil(routing.strongWindowDecision)
        XCTAssertFalse(routing.didConsumeStrongBudget)
    }

    func testRouteIdleStarterIncludesStartAndSkipActionsWhenEnabled() {
        let route = planner.routeIdleStarter(
            driftConfidence: 0.82,
            focusOpportunity: 0.78,
            mode: .balanced,
            allowSkipAction: true
        )

        XCTAssertTrue(route.shouldPresent)
        XCTAssertEqual(route.decision?.kind, .quickPrompt)
        XCTAssertTrue(route.decision?.suggestedActions.contains(.startFocusNow) == true)
        XCTAssertTrue(route.decision?.suggestedActions.contains(.skipCheck) == true)
    }

    func testRouteIdleStarterChallengeSuppressesWithoutConfidenceOrPattern() {
        let route = planner.routeIdleStarter(
            driftConfidence: 0.72,
            focusOpportunity: 0.78,
            mode: .balanced,
            allowSkipAction: true,
            engagementMode: .adaptive,
            guardianState: .challenge,
            isInReleaseWindow: false,
            workIntentSignal: WorkIntentSignal(
                openedAppRecently: true,
                selectedProjectRecently: true,
                recentlyAbandonedStart: false,
                withinTypicalWorkHours: false,
                matchesHistoricalMissedStart: false
            ),
            repeatedProjectPattern: false
        )

        XCTAssertFalse(route.shouldPresent)
        XCTAssertNil(route.decision)
    }

    func testRouteIdleStarterChallengeAllowsRepeatedPatternEvenWithoutHighDrift() {
        let route = planner.routeIdleStarter(
            driftConfidence: 0.72,
            focusOpportunity: 0.78,
            mode: .balanced,
            allowSkipAction: true,
            engagementMode: .adaptive,
            guardianState: .challenge,
            isInReleaseWindow: false,
            workIntentSignal: WorkIntentSignal(
                openedAppRecently: true,
                selectedProjectRecently: true,
                recentlyAbandonedStart: false,
                withinTypicalWorkHours: false,
                matchesHistoricalMissedStart: false
            ),
            repeatedProjectPattern: true
        )

        XCTAssertTrue(route.shouldPresent)
        XCTAssertEqual(route.decision?.kind, .quickPrompt)
    }

    func testRouteActiveDecisionAddsSkipActionWhenEnabled() {
        let route = planner.routeActiveDecision(
            FocusCoachDecision(
                kind: .quickPrompt,
                suggestedActions: [.returnNow, .snooze10m],
                message: "Recover?"
            ),
            mode: .balanced,
            riskScore: 0.7,
            strongShownCount: 0,
            maxStrongPrompts: 2,
            allowSkipAction: true
        )

        XCTAssertTrue(route.quickPromptDecision?.suggestedActions.contains(.skipCheck) == true)
    }
}
