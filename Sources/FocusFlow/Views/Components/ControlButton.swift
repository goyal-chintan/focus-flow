import SwiftUI

struct ControlButton: View {
    let title: String
    let icon: String
    let role: Role
    let action: () -> Void

    enum Role {
        case primary, secondary, destructive
    }

    var body: some View {
        LiquidActionButton(
            title: title,
            icon: icon,
            role: liquidRole,
            action: action
        )
    }

    private var liquidRole: LiquidActionRole {
        switch role {
        case .primary: .primary
        case .secondary: .secondary
        case .destructive: .destructive
        }
    }
}
