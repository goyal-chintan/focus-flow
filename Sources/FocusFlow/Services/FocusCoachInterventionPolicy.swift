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

    var displayName: String {
        switch self {
        case .returnNow: "Return Now"
        case .startFocusNow: "Start Focus Now"
        case .cleanRestart5m: "Clean Restart (5m)"
        case .snooze10m: "Snooze 10m"
        case .skipCheck: "Skip this check"
        }
    }
}

/// The decision kinds: none means no intervention needed
enum FocusCoachDecisionKind: String, Sendable {
    case none
    case softStrip
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

    init(
        kind: FocusCoachDecisionKind,
        suggestedActions: [FocusCoachQuickAction],
        message: String?,
        context: FocusCoachContext? = nil
    ) {
        self.kind = kind
        self.suggestedActions = suggestedActions
        self.message = message
        self.context = context
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

        // Gate 2: budget exhausted — only allow soft strip (non-prompt)
        if state.promptCountThisSession >= promptBudget {
            if risk == .highRisk {
                return FocusCoachDecision(
                    kind: .softStrip,
                    suggestedActions: [],
                    message: "You've used all coach prompts this session."
                )
            }
            return .none
        }

        // Gate 3: cooldown — too soon since last prompt
        if let lastPrompt = state.lastPromptAt,
           now.timeIntervalSince(lastPrompt) < cooldownSeconds {
            if risk == .highRisk {
                return FocusCoachDecision(
                    kind: .softStrip,
                    suggestedActions: [],
                    message: nil
                )
            }
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
                message: "Drift detected — quick recovery?"
            )

        case .highRisk:
            if state.consecutiveHighRiskWindows >= 2 {
                return FocusCoachDecision(
                    kind: .strongPrompt,
                    suggestedActions: [.returnNow, .cleanRestart5m, .snooze10m],
                    message: "Sustained drift — consider a clean restart or return now."
                )
            }
            return FocusCoachDecision(
                kind: .quickPrompt,
                suggestedActions: [.returnNow, .cleanRestart5m, .snooze10m],
                message: "High drift risk — take action?"
            )
        }
    }
}
