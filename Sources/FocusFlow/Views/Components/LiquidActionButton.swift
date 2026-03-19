import SwiftUI

enum LiquidActionRole {
    case primary
    case secondary
    case destructive

    var tint: Color? {
        switch self {
        case .primary: LiquidDesignTokens.Tint.primary
        case .secondary: nil
        case .destructive: LiquidDesignTokens.Tint.destructive
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
    let action: () -> Void

    var body: some View {
        let label = Label(title, systemImage: icon)
            .font(LiquidDesignTokens.Typography.controlLabel)
            .frame(maxWidth: .infinity)
            .padding(.vertical, LiquidDesignTokens.Padding.controlVertical)

        if role.isProminent {
            Button(action: action) { label }
                .buttonStyle(.glassProminent)
                .tint(role.tint)
        } else {
            Button(action: action) { label }
                .buttonStyle(.glass)
                .tint(role.tint)
        }
    }
}
