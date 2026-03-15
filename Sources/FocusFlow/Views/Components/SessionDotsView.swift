import SwiftUI

struct SessionDotsView: View {
    let completed: Int
    let total: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<total, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(index < completed ? Color.accentColor : Color.secondary.opacity(0.25))
                    .frame(width: index < completed ? 16 : 8, height: 4)
                    .animation(.spring(response: 0.4, dampingFraction: 0.7), value: completed)
            }
        }
    }
}
