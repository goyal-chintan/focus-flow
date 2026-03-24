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
                subtitle: "Context mismatch spotted",
                color: LiquidDesignTokens.Spectral.amber,
                iconName: "exclamationmark.triangle.fill"
            )
        case .highRisk:
            return StripModel(
                tone: .red,
                title: "Drift Alert",
                subtitle: score > 0.85 ? "Sustained mismatch — decide now" : "Repeated mismatch detected",
                color: LiquidDesignTokens.Spectral.salmon,
                iconName: "exclamationmark.octagon.fill"
            )
        }
    }

    // MARK: - Decision → Prompt

    static func mapDecision(_ decision: FocusCoachDecision) -> PromptModel? {
        switch decision.kind {
        case .none, .softStrip:
            return nil
        case .quickPrompt:
            return PromptModel(
                title: "Planned or Drift?",
                message: decision.message ?? "Current context looks off-plan. Choose the next step.",
                actions: decision.suggestedActions,
                isStrong: false
            )
        case .strongPrompt:
            return PromptModel(
                title: "Guardrail Check",
                message: decision.message ?? "Sustained off-plan behavior detected. Choose a corrective action.",
                actions: decision.suggestedActions,
                isStrong: true
            )
        }
    }
}
