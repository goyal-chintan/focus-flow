import Foundation

/// Decides which UI surface should present a coach intervention.
/// Keeps presentation-routing policy pure and testable.
struct FocusCoachInterventionPlanner: Sendable {
    enum Surface: Equatable {
        case none
        case quickPrompt
        case strongWindow
    }

    struct ActiveDecisionRoute {
        let quickPromptDecision: FocusCoachDecision?
        let strongWindowDecision: FocusCoachDecision?
        let didConsumeStrongBudget: Bool
    }

    struct IdleStarterRoute {
        let shouldPresent: Bool
        let decision: FocusCoachDecision?
    }

    func surfaceForActiveDecision(
        decisionKind: FocusCoachDecisionKind,
        mode: FocusCoachInterventionMode,
        riskScore: Double,
        strongShownCount: Int,
        maxStrongPrompts: Int
    ) -> Surface {
        switch decisionKind {
        case .none, .softStrip:
            return .none
        case .quickPrompt:
            if mode == .adaptiveStrict && riskScore >= 0.75 && strongShownCount < maxStrongPrompts {
                return .strongWindow
            }
            return .quickPrompt
        case .strongPrompt:
            if strongShownCount < maxStrongPrompts {
                return .strongWindow
            }
            return .quickPrompt
        }
    }

    func shouldShowIdleStarter(
        driftConfidence: Double,
        focusOpportunity: Double,
        mode: FocusCoachInterventionMode
    ) -> Bool {
        let confidenceThreshold: Double
        let opportunityThreshold: Double

        switch mode {
        case .balanced:
            confidenceThreshold = 0.55
            opportunityThreshold = 0.45
        case .adaptiveStrict:
            confidenceThreshold = 0.60
            opportunityThreshold = 0.50
        case .sessionRescue:
            confidenceThreshold = 0.65
            opportunityThreshold = 0.40
        }

        return driftConfidence >= confidenceThreshold && focusOpportunity >= opportunityThreshold
    }

    func routeActiveDecision(
        _ decision: FocusCoachDecision,
        mode: FocusCoachInterventionMode,
        riskScore: Double,
        strongShownCount: Int,
        maxStrongPrompts: Int,
        allowSkipAction: Bool = false,
        engagementMode: GuardianEngagementMode = .adaptive
    ) -> ActiveDecisionRoute {
        // Passive mode: suppress all popover and hard dialog interventions
        if engagementMode == .passive {
            return ActiveDecisionRoute(
                quickPromptDecision: nil,
                strongWindowDecision: nil,
                didConsumeStrongBudget: false
            )
        }

        let surface = surfaceForActiveDecision(
            decisionKind: decision.kind,
            mode: mode,
            riskScore: riskScore,
            strongShownCount: strongShownCount,
            maxStrongPrompts: maxStrongPrompts
        )

        switch surface {
        case .none:
            return ActiveDecisionRoute(
                quickPromptDecision: nil,
                strongWindowDecision: nil,
                didConsumeStrongBudget: false
            )
        case .quickPrompt:
            let quickDecision: FocusCoachDecision
            if decision.kind == .quickPrompt {
                quickDecision = withOptionalSkip(decision, allowSkipAction: allowSkipAction)
            } else {
                quickDecision = withOptionalSkip(FocusCoachDecision(
                    kind: .quickPrompt,
                    suggestedActions: decision.suggestedActions,
                    message: decision.message,
                    context: decision.context
                ), allowSkipAction: allowSkipAction)
            }
            return ActiveDecisionRoute(
                quickPromptDecision: quickDecision,
                strongWindowDecision: nil,
                didConsumeStrongBudget: false
            )
        case .strongWindow:
            let strongDecision = decision.kind == .strongPrompt ? decision : FocusCoachDecision(
                kind: .strongPrompt,
                suggestedActions: decision.suggestedActions,
                message: decision.message,
                context: decision.context
            )
            return ActiveDecisionRoute(
                quickPromptDecision: nil,
                strongWindowDecision: withOptionalSkip(strongDecision, allowSkipAction: allowSkipAction),
                didConsumeStrongBudget: true
            )
        }
    }

    func routeIdleStarter(
        driftConfidence: Double,
        focusOpportunity: Double,
        mode: FocusCoachInterventionMode,
        allowSkipAction: Bool,
        engagementMode: GuardianEngagementMode = .adaptive
    ) -> IdleStarterRoute {
        // Passive mode: suppress idle starter — ambient ring only
        if engagementMode == .passive {
            return IdleStarterRoute(shouldPresent: false, decision: nil)
        }

        guard shouldShowIdleStarter(
            driftConfidence: driftConfidence,
            focusOpportunity: focusOpportunity,
            mode: mode
        ) else {
            return IdleStarterRoute(shouldPresent: false, decision: nil)
        }

        var actions: [FocusCoachQuickAction] = [.startFocusNow, .cleanRestart5m, .snooze10m]
        if allowSkipAction {
            actions.append(.skipCheck)
        }

        return IdleStarterRoute(
            shouldPresent: true,
            decision: FocusCoachDecision(
                kind: .quickPrompt,
                suggestedActions: actions,
                message: "Good window to start focus now."
            )
        )
    }

    private func withOptionalSkip(
        _ decision: FocusCoachDecision,
        allowSkipAction: Bool
    ) -> FocusCoachDecision {
        guard allowSkipAction else { return decision }
        if decision.suggestedActions.contains(.skipCheck) {
            return decision
        }
        return FocusCoachDecision(
            kind: decision.kind,
            suggestedActions: decision.suggestedActions + [.skipCheck],
            message: decision.message,
            context: decision.context
        )
    }
}
