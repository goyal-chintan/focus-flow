import SwiftUI

enum LiquidActionRole {
    case primary
    case secondary
    case destructive

    var tint: Color? {
        switch self {
        case .primary: LiquidDesignTokens.Spectral.primaryContainer
        case .secondary: nil
        case .destructive: LiquidDesignTokens.Spectral.destructive
        }
    }

    var isProminent: Bool {
        self == .primary
    }
}

struct LiquidActionButton: View {
    @Environment(\.focusFlowEvidenceRendering) private var isEvidenceRendering
    let title: String
    let icon: String
    let role: LiquidActionRole
    let fillsWidth: Bool
    let tint: Color?
    let action: () -> Void

    init(
        title: String,
        icon: String,
        role: LiquidActionRole,
        fillsWidth: Bool = true,
        tint: Color? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.role = role
        self.fillsWidth = fillsWidth
        self.tint = tint
        self.action = action
    }

    @ViewBuilder
    var body: some View {
        if isEvidenceRendering {
            evidenceButton
        } else if role.isProminent {
            Button(action: action) {
                buttonLabel(foreground: LiquidDesignTokens.Surface.onProminent)
            }
            .buttonStyle(.glassProminent)
            .tint(tint ?? role.tint ?? LiquidDesignTokens.Spectral.primaryContainer)
            .buttonBorderShape(.capsule)
        } else {
            Button(action: action) {
                buttonLabel(
                    foreground: role == .destructive
                        ? LiquidDesignTokens.Spectral.destructive
                        : LiquidDesignTokens.Surface.onSurface
                )
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
        }
    }

    private var evidenceButton: some View {
        Button(action: action) {
            buttonLabel(
                foreground: role.isProminent
                    ? LiquidDesignTokens.Surface.onProminent
                    : (role == .destructive ? LiquidDesignTokens.Spectral.destructive : LiquidDesignTokens.Surface.onSurface)
            )
            .background {
                evidenceBackground
            }
        }
        .buttonStyle(.plain)
        .contentShape(Capsule(style: .continuous))
        .shadow(
            color: role.isProminent ? primaryTint.opacity(0.18) : .clear,
            radius: role.isProminent ? 8 : 0,
            y: role.isProminent ? 3 : 0
        )
    }

    private func buttonLabel(foreground: Color) -> some View {
        Label(title, systemImage: icon)
            .font(LiquidDesignTokens.Typography.controlLabel)
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
            .minimumScaleFactor(0.9)
            .foregroundStyle(foreground)
            .frame(maxWidth: fillsWidth ? .infinity : nil, minHeight: 44)
            .padding(.horizontal, LiquidDesignTokens.Padding.controlHorizontal)
    }

    @ViewBuilder
    private var evidenceBackground: some View {
        if role.isProminent {
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [primaryTint.opacity(0.96), primaryTint.opacity(0.78)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.22), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                )
        } else {
            Capsule(style: .continuous)
                .fill(ObsidianGradients.glassPanel())
                .overlay(
                    Capsule(style: .continuous)
                        .fill(role == .destructive ? LiquidDesignTokens.Spectral.destructive.opacity(0.08) : .clear)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(
                            role == .destructive
                                ? LiquidDesignTokens.Spectral.destructive.opacity(0.22)
                                : LiquidDesignTokens.Surface.glassStroke,
                            lineWidth: 0.5
                        )
                )
        }
    }

    private var primaryTint: Color {
        tint ?? role.tint ?? LiquidDesignTokens.Spectral.primaryContainer
    }
}
