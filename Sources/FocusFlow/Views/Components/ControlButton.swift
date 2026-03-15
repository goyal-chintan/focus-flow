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
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .glassEffect(role == .primary ? .regular.tint(buttonTint ?? .blue).interactive() : .regular.interactive())
        .tint(buttonTint)
    }

    private var buttonTint: Color? {
        switch role {
        case .primary: .blue
        case .secondary: nil
        case .destructive: .red
        }
    }
}
