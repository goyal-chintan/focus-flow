import Foundation

/// Prompt state tracked per session to enforce budget, cooldown, and snooze.
struct FocusCoachPromptState: Sendable {
    var promptCountThisSession: Int
    var consecutiveHighRiskWindows: Int
    var snoozedUntil: Date?
    var lastPromptAt: Date?

    static let initial = FocusCoachPromptState(
        promptCountThisSession: 0,
        consecutiveHighRiskWindows: 0,
        snoozedUntil: nil,
        lastPromptAt: nil
    )
}

/// Quick recovery actions presented in prompts
enum FocusCoachQuickAction: String, Codable, CaseIterable {
    case returnNow
    case startFocusNow
    case cleanRestart5m
    case snooze10m
    case skipCheck
    case blockForProject
    case markOffDuty
    case isPlanned

    var displayName: String {
        switch self {
        case .returnNow: "Back to it"
        case .startFocusNow: "Start focus"
        case .cleanRestart5m: "Start 5m block"
        case .snooze10m: "Not now"
        case .skipCheck: "Skip this check"
        case .blockForProject: "Block for this project"
        case .markOffDuty: "Done for today"
        case .isPlanned: "It's part of the work"
        }
    }
}

/// The decision kinds: none means no intervention needed
enum FocusCoachDecisionKind: String, Sendable {
    case none
    case quickPrompt
    case strongPrompt
}

/// The output of the intervention policy: what to show and what actions to offer.
struct FocusCoachDecision: Sendable {
    let kind: FocusCoachDecisionKind
    let suggestedActions: [FocusCoachQuickAction]
    let message: String?
    /// Optional personalisation snapshot — populated when the intervention window is shown.
    let context: FocusCoachContext?
    /// Copy from `CoachMessageComposer`, the single source of coach words (Coach v2 §3 [4]).
    let composed: CoachComposedMessage?

    init(
        kind: FocusCoachDecisionKind,
        suggestedActions: [FocusCoachQuickAction],
        message: String?,
        context: FocusCoachContext? = nil,
        composed: CoachComposedMessage? = nil
    ) {
        self.kind = kind
        self.suggestedActions = suggestedActions
        self.message = message ?? composed?.accessibilityText
        self.context = context
        self.composed = composed
    }

    static let none = FocusCoachDecision(kind: .none, suggestedActions: [], message: nil)
}

/// Pure intervention policy. No side effects — takes risk level + prompt state, returns a decision.
///
/// Safeguards (from design doc):
/// - Honor snooze window (no prompts while snoozed)
/// - Respect per-session prompt budget
/// - 90-second cooldown between prompts
/// - Escalation ladder: stable→none, driftRisk→quickPrompt, repeated highRisk→strongPrompt
struct FocusCoachInterventionPolicy: Sendable {

    /// Minimum seconds between prompts
    private let cooldownSeconds: TimeInterval = 90

    func decide(
        now: Date,
        risk: FocusCoachRiskLevel,
        state: FocusCoachPromptState,
        promptBudget: Int
    ) -> FocusCoachDecision {

        // Gate 1: snooze active — suppress all interventions
        if let snoozedUntil = state.snoozedUntil, now < snoozedUntil {
            return .none
        }

        // Gate 2: budget exhausted. The live strip in the popover already shows the risk.
        if state.promptCountThisSession >= promptBudget {
            return .none
        }

        // Gate 3: cooldown — too soon since last prompt
        if let lastPrompt = state.lastPromptAt,
           now.timeIntervalSince(lastPrompt) < cooldownSeconds {
            return .none
        }

        // Decision based on risk level
        switch risk {
        case .stable:
            return .none

        case .driftRisk:
            return FocusCoachDecision(
                kind: .quickPrompt,
                suggestedActions: [.returnNow, .snooze10m],
                message: nil
            )

        case .highRisk:
            if state.consecutiveHighRiskWindows >= 2 {
                return FocusCoachDecision(
                    kind: .strongPrompt,
                    suggestedActions: [.returnNow, .cleanRestart5m, .snooze10m],
                    message: nil
                )
            }
            return FocusCoachDecision(
                kind: .quickPrompt,
                suggestedActions: [.returnNow, .cleanRestart5m, .snooze10m],
                message: nil
            )
        }
    }
}
