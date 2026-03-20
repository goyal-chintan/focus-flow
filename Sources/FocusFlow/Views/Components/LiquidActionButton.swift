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
    let title: String
    let icon: String
    let role: LiquidActionRole
    let tint: Color?
    let action: () -> Void

    init(
        title: String,
        icon: String,
        role: LiquidActionRole,
        tint: Color? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.role = role
        self.tint = tint
        self.action = action
    }

    var body: some View {
        let label = Label(title, systemImage: icon)
            .font(LiquidDesignTokens.Typography.controlLabel)
            .frame(maxWidth: .infinity)
            .padding(.vertical, LiquidDesignTokens.Padding.controlVertical)

        if role.isProminent {
            Button(action: action) { label }
                .buttonStyle(.glassProminent)
                .tint(tint ?? role.tint)
                .buttonBorderShape(.capsule)
        } else {
            Button(action: action) { label }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
        }
    }
}
