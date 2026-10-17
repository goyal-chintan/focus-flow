import SwiftUI

/// Maps risk scoring output to visual presentation values for coach UI components.
/// Pure mapping — no side effects, fully testable.
struct FocusCoachPresentationMapper {

    enum Tone: String {
        case green, amber, red
    }

    struct StripModel {
        let tone: Tone
        let title: String
        let subtitle: String?
        let color: Color
        let iconName: String
    }

    struct PromptModel {
        let title: String
        let message: String
        let actions: [FocusCoachQuickAction]
        let isStrong: Bool
        /// Composed label for the primary action ("Start 25m on X", "Back to it").
        var primaryTitle: String? = nil
    }

    // MARK: - Risk → Strip

    static func map(level: FocusCoachRiskLevel, score: Double) -> StripModel {
        switch level {
        case .stable:
            return StripModel(
                tone: .green,
                title: "Focus Stable",
                subtitle: nil,
                color: LiquidDesignTokens.Spectral.mint,
                iconName: "checkmark.circle.fill"
            )
        case .driftRisk:
            return StripModel(
                tone: .amber,
                title: "Drift Detected",
                subtitle: "Looks off-plan",
                color: LiquidDesignTokens.Spectral.amber,
                iconName: "exclamationmark.triangle.fill"
            )
        case .highRisk:
            return StripModel(
                tone: .red,
                title: "Drift Alert",
                subtitle: score > 0.85 ? "Off-plan for a while" : "Off-plan again",
                color: LiquidDesignTokens.Spectral.salmon,
                iconName: "exclamationmark.octagon.fill"
            )
        }
    }

    // MARK: - Decision → Prompt

    /// Popover card for a decision. The words come from `CoachMessageComposer` via
    /// `decision.composed`; this mapper only picks the visual intensity.
    static func mapDecision(_ decision: FocusCoachDecision) -> PromptModel? {
        switch decision.kind {
        case .none:
            return nil
        case .quickPrompt, .strongPrompt:
            let copy = decision.composed
                ?? CoachMessageComposer.neutralFallback(isInSession: decision.context?.isInActiveSession ?? false)
            return PromptModel(
                title: copy.hook,
                message: copy.detail?.text ?? "",
                actions: decision.suggestedActions,
                isStrong: decision.kind == .strongPrompt,
                primaryTitle: copy.primaryTitle
            )
        }
    }
}
