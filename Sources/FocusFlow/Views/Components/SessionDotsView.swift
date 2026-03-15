import SwiftUI

struct SessionDotsView: View {
    let completed: Int
    let total: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { index in
                Circle()
                    .fill(index < completed ? Color.blue : Color.primary.opacity(0.12))
                    .frame(width: 6, height: 6)
            }
        }
    }
}
