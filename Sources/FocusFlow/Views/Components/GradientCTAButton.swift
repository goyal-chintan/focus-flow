import SwiftUI

struct GradientCTAButton: View {
    let title: String
    let icon: String
    let gradient: LinearGradient
    var foregroundColor: Color = .white
    let action: () -> Void

    @State private var isHovering = false
    @State private var isPressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(foregroundColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background {
                Capsule(style: .continuous)
                    .fill(gradient)
                    .overlay(
                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.28), .clear],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    )
            }
            .clipShape(Capsule(style: .continuous))
            .shadow(color: .black.opacity(0.2), radius: isHovering ? 8 : 4, y: isHovering ? 4 : 2)
            .scaleEffect(isPressed ? 0.97 : (isHovering ? 1.02 : 1.0))
            .brightness(isPressed ? -0.05 : (isHovering ? 0.05 : 0))
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7), value: isHovering)
            .animation(reduceMotion ? nil : .spring(response: 0.2, dampingFraction: 0.8), value: isPressed)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .accessibilityLabel(title)
    }
}
