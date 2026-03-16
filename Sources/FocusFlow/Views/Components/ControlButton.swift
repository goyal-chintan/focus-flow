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
        let label = Label {
            Text(title)
                .font(FFType.callout)
        } icon: {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, FFSpacing.md)
        .padding(.vertical, FFSpacing.sm + 2)

        Button(action: action) { label }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .tint(buttonTint)
    }

    private var buttonTint: Color {
        switch role {
        case .primary: FFColor.focus
        case .secondary: .white.opacity(0.5)
        case .destructive: FFColor.danger
        }
    }

    private var isProminent: Bool {
        role == .primary
    }
}
