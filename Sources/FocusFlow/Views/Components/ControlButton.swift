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
                .font(.system(size: 14, weight: .semibold))
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, FFSpacing.md)
        .padding(.vertical, FFSpacing.sm + 1)

        if role == .primary {
            Button(action: action) { label }
                .buttonStyle(.glassProminent)
                .tint(buttonTint)
        } else {
            Button(action: action) { label }
                .buttonStyle(.glass)
                .tint(buttonTint)
        }
    }

    private var buttonTint: Color? {
        switch role {
        case .primary: FFColor.focus
        case .secondary: nil
        case .destructive: FFColor.danger
        }
    }
}
