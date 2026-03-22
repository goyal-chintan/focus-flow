import SwiftUI

/// Quick-action prompt that appears when the coach detects drift.
/// Shows 1–3 recovery actions as tappable capsule buttons.
/// Two visual intensities: normal (amber tint) and strong (salmon/red tint).
struct FocusCoachQuickPromptView: View {
    let model: FocusCoachPresentationMapper.PromptModel
    let onAction: (FocusCoachQuickAction) -> Void
    let onDismiss: () -> Void

    @State private var appear = false
    @State private var hoveredAction: FocusCoachQuickAction?

    private var accentColor: Color {
        model.isStrong ? LiquidDesignTokens.Spectral.salmon : LiquidDesignTokens.Spectral.amber
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LiquidDesignTokens.Spacing.medium) {
            // Header
            HStack(spacing: LiquidDesignTokens.Spacing.small) {
                Image(systemName: model.isStrong ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(accentColor)
                    .symbolEffect(.pulse, options: model.isStrong ? .repeating : .nonRepeating, value: appear)

                VStack(alignment: .leading, spacing: 1) {
                    Text(model.title)
                        .font(LiquidDesignTokens.Typography.labelMedium)
                        .foregroundStyle(LiquidDesignTokens.Surface.onSurface)

                    Text(model.message)
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)
                }

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss coach prompt")
            }

            // Action buttons
            HStack(spacing: LiquidDesignTokens.Spacing.small) {
                ForEach(model.actions, id: \.rawValue) { action in
                    actionButton(for: action)
                }
            }
        }
        .padding(LiquidDesignTokens.Spacing.medium)
        .background {
            RoundedRectangle(cornerRadius: LiquidDesignTokens.CornerRadius.card)
                .fill(accentColor.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: LiquidDesignTokens.CornerRadius.card)
                        .strokeBorder(accentColor.opacity(0.15), lineWidth: 0.5)
                )
        }
        .opacity(appear ? 1 : 0)
        .offset(y: appear ? 0 : 8)
        .onAppear {
            withAnimation(FFMotion.popover) {
                appear = true
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Coach prompt: \(model.title)")
    }

    @ViewBuilder
    private func actionButton(for action: FocusCoachQuickAction) -> some View {
        let isPrimary = action == .returnNow
        let isHovered = hoveredAction == action

        Button(action: { onAction(action) }) {
            HStack(spacing: 4) {
                Image(systemName: iconName(for: action))
                    .font(.system(size: 10, weight: .semibold))
                Text(action.displayName)
                    .font(LiquidDesignTokens.Typography.labelSmall)
            }
            .padding(.horizontal, LiquidDesignTokens.Spacing.medium)
            .padding(.vertical, LiquidDesignTokens.Spacing.small)
            .background {
                Capsule()
                    .fill(isPrimary
                        ? accentColor.opacity(isHovered ? 0.25 : 0.15)
                        : Color.white.opacity(isHovered ? 0.08 : 0.04))
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                isPrimary ? accentColor.opacity(0.3) : Color.white.opacity(0.08),
                                lineWidth: 0.5
                            )
                    )
            }
            .foregroundStyle(isPrimary ? accentColor : LiquidDesignTokens.Surface.onSurface)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(FFMotion.control) {
                hoveredAction = hovering ? action : nil
            }
        }
        .accessibilityLabel(action.displayName)
    }

    private func iconName(for action: FocusCoachQuickAction) -> String {
        switch action {
        case .returnNow: "arrow.uturn.backward"
        case .cleanRestart5m: "arrow.clockwise"
        case .snooze10m: "moon.zzz"
        }
    }
}
