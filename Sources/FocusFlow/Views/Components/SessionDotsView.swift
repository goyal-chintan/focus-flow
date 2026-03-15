import SwiftUI

struct SessionDotsView: View {
    let completed: Int
    let total: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<total, id: \.self) { index in
                Capsule()
                    .fill(index < completed ? Color.accentColor : Color.secondary.opacity(0.25))
                    .frame(width: index < completed ? 18 : 10, height: 5)
                    .shadow(
                        color: index < completed ? Color.accentColor.opacity(0.45) : .clear,
                        radius: 4, x: 0, y: 0
                    )
                    .animation(.spring(response: 0.4, dampingFraction: 0.7), value: completed)
            }
        }
    }
}
