import SwiftUI

struct SessionDotsView: View {
    let completed: Int
    let total: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<total, id: \.self) { index in
                Circle()
                    .fill(index < completed ? Color.blue : Color.primary.opacity(0.12))
                    .frame(width: index < completed ? 8 : 7, height: index < completed ? 8 : 7)
                    .scaleEffect(index < completed ? 1 : 0.92)
                    .animation(
                        .spring(response: 0.25, dampingFraction: 0.85)
                            .delay(Double(index) * 0.03),
                        value: completed
                    )
            }
        }
    }
}
