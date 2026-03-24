import SwiftUI

/// Compact horizontal strip showing current focus risk status.
/// Renders below the timer ring during active sessions. Color interpolates
/// between green → amber → red based on risk level with smooth spring animation.
struct FocusCoachStripView: View {
    let model: FocusCoachPresentationMapper.StripModel
    let onTap: (() -> Void)?

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(model: FocusCoachPresentationMapper.StripModel, onTap: (() -> Void)? = nil) {
        self.model = model
        self.onTap = onTap
    }

    var body: some View {
        Button(action: { onTap?() }) {
            stripContent
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(reduceMotion ? .linear(duration: 0.01) : FFMotion.warning) {
                isHovered = hovering
            }
        }
        .animation(reduceMotion ? nil : FFMotion.warning, value: model.tone)
        .accessibilityLabel("Focus status: \(model.title)")
        .accessibilityValue(model.subtitle ?? "")
    }

    @ViewBuilder
    private var stripContent: some View {
        HStack(spacing: LiquidDesignTokens.Spacing.small) {
            Image(systemName: model.iconName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(model.color)

            VStack(alignment: .leading, spacing: 1) {
                Text(model.title)
                    .font(LiquidDesignTokens.Typography.labelSmall)
                    .foregroundStyle(model.color)

                if let subtitle = model.subtitle {
                    Text(subtitle)
                        .font(.system(size: 9, weight: .regular, design: .rounded))
                        .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)
                }
            }

            Spacer()

            if model.tone != .green {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)
            }
        }
        .padding(.horizontal, LiquidDesignTokens.Spacing.medium)
        .padding(.vertical, LiquidDesignTokens.Spacing.small)
        .background {
            RoundedRectangle(cornerRadius: LiquidDesignTokens.CornerRadius.sm)
                .fill(model.color.opacity(isHovered ? 0.15 : 0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: LiquidDesignTokens.CornerRadius.sm)
                        .strokeBorder(model.color.opacity(0.2), lineWidth: 0.5)
                )
        }
        .scaleEffect(isHovered ? 1.01 : 1.0)
    }
}
