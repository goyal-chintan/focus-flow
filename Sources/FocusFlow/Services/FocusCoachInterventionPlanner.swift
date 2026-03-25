import Foundation

// MARK: - Work Intent Window

/// Signals that indicate the user is in an active work context (not off-duty).
struct WorkIntentSignal: Sendable {
    /// User opened FocusFlow within the last 15 minutes.
    var openedAppRecently: Bool
    /// User selected or viewed a project within the last 15 minutes.
    var selectedProjectRecently: Bool
    /// User had a session start attempt that was abandoned or delayed.
    var recentlyAbandonedStart: Bool
    /// Current time falls within the user's typical work hours pattern.
    var withinTypicalWorkHours: Bool
    /// Current context matches a repeated historical missed-start pattern.
    var matchesHistoricalMissedStart: Bool

    /// Returns true when enough signals indicate user is in a work-intent context.
    var isWorkIntentWindow: Bool {
        let score = [
            openedAppRecently,
            selectedProjectRecently,
            recentlyAbandonedStart,
            withinTypicalWorkHours,
            matchesHistoricalMissedStart
        ].filter { $0 }.count
        // Require at least 1 signal so outside-session prompts don't stay silent for hours.
        return score >= 1
    }
}

/// Evaluates whether the current moment is a "work intent window" for outside-session challenges.
struct WorkIntentWindowDetector: Sendable {
    /// Evaluate work intent signals from available context.
    func evaluate(
        appLastOpenedAt: Date?,
        projectLastSelectedAt: Date?,
        lastAbandonedStartAt: Date?,
        matchesHistoricalMissedStart: Bool,
        currentHour: Int = Calendar.current.component(.hour, from: Date()),
        historicalWorkHours: ClosedRange<Int> = 9...18
    ) -> WorkIntentSignal {
        let now = Date()
        let fifteenMinutes: TimeInterval = 15 * 60

        let openedRecently = appLastOpenedAt.map { now.timeIntervalSince($0) < fifteenMinutes } ?? false
        let selectedRecently = projectLastSelectedAt.map { now.timeIntervalSince($0) < fifteenMinutes } ?? false
        let abandonedRecently = lastAbandonedStartAt.map { now.timeIntervalSince($0) < fifteenMinutes } ?? false
        let withinWorkHours = historicalWorkHours.contains(currentHour)

        return WorkIntentSignal(
            openedAppRecently: openedRecently,
            selectedProjectRecently: selectedRecently,
            recentlyAbandonedStart: abandonedRecently,
            withinTypicalWorkHours: withinWorkHours,
            matchesHistoricalMissedStart: matchesHistoricalMissedStart
        )
    }
}

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

    /// Returns true when an outside-session hard challenge should fire.
    /// All three gates must pass: not in release window, not passive, guardian is in challenge
    /// state, and a work-intent window is detected.
    func shouldTriggerOutsideSessionChallenge(
        guardianState: FocusCoachGuardianState,
        isInReleaseWindow: Bool,
        workIntentSignal: WorkIntentSignal,
        hasHighConfidenceDrift: Bool,
        repeatedProjectPattern: Bool,
        engagementMode: GuardianEngagementMode
    ) -> Bool {
        guard !isInReleaseWindow else { return false }
        guard engagementMode != .passive else { return false }
        guard guardianState == .challenge else { return false }
        guard hasHighConfidenceDrift || repeatedProjectPattern else { return false }
        guard workIntentSignal.isWorkIntentWindow else { return false }
        return true
    }

    func routeIdleStarter(
        driftConfidence: Double,
        focusOpportunity: Double,
        mode: FocusCoachInterventionMode,
        allowSkipAction: Bool,
        engagementMode: GuardianEngagementMode = .adaptive,
        guardianState: FocusCoachGuardianState = .observe,
        isInReleaseWindow: Bool = false,
        workIntentSignal: WorkIntentSignal? = nil,
        repeatedProjectPattern: Bool = false
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

        // Work-intent gate: when guardian is in challenge state, require an active work-intent
        // window before firing the hard dialog. If signals are absent, downgrade to watchful
        // (ambient ring only — no popover or dialog).
        if let signal = workIntentSignal,
           guardianState == .challenge,
           !shouldTriggerOutsideSessionChallenge(
                guardianState: guardianState,
                isInReleaseWindow: isInReleaseWindow,
                workIntentSignal: signal,
                hasHighConfidenceDrift: driftConfidence >= engagementMode.outsideSessionChallengeThreshold,
                repeatedProjectPattern: repeatedProjectPattern,
                engagementMode: engagementMode
            ) {
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
