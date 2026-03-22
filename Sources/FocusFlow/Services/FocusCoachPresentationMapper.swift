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
                subtitle: "Switching apps frequently",
                color: LiquidDesignTokens.Spectral.amber,
                iconName: "exclamationmark.triangle.fill"
            )
        case .highRisk:
            return StripModel(
                tone: .red,
                title: "Drift Alert",
                subtitle: score > 0.85 ? "Sustained drift — take action" : "High app switching detected",
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
                title: "Quick Recovery",
                message: decision.message ?? "Drift detected — quick recovery?",
                actions: decision.suggestedActions,
                isStrong: false
            )
        case .strongPrompt:
            return PromptModel(
                title: "Focus Check",
                message: decision.message ?? "Sustained drift — consider a clean restart.",
                actions: decision.suggestedActions,
                isStrong: true
            )
        }
    }
}
