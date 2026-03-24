import SwiftUI

struct SessionDotsView: View {
    let completed: Int
    let total: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { index in
                Circle()
                    .fill(index < completed
                        ? LiquidDesignTokens.Spectral.electricBlue
                        : Color.white.opacity(0.12))
                    .frame(width: 6, height: 6)
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.85), value: completed)
    }
}
