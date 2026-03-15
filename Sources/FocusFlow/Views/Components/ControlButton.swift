import SwiftUI

struct ControlButton: View {
    let title: String
    let icon: String
    let role: Role
    let action: () -> Void

    enum Role {
        case primary, secondary, destructive
    }

    @State private var isPressed = false

    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                isPressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                    isPressed = false
                }
            }
            action()
        }) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(background, in: RoundedRectangle(cornerRadius: 10))
            .foregroundStyle(foregroundColor)
            .scaleEffect(isPressed ? 0.94 : 1.0)
        }
        .buttonStyle(.plain)
    }

    private var background: AnyShapeStyle {
        switch role {
        case .primary: AnyShapeStyle(.tint)
        case .secondary: AnyShapeStyle(.ultraThinMaterial)
        case .destructive: AnyShapeStyle(Color.red.opacity(0.12))
        }
    }

    private var foregroundColor: Color {
        switch role {
        case .primary: .white
        case .secondary: .primary
        case .destructive: .red
        }
    }
}
