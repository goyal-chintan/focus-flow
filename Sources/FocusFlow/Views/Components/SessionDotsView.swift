import SwiftUI

struct SessionDotsView: View {
    let completed: Int
    let total: Int

    var body: some View {
        HStack(spacing: FFSpacing.sm) {
            HStack(spacing: FFSpacing.xs) {
                ForEach(0..<total, id: \.self) { index in
                    Circle()
                        .fill(index < completed ? FFColor.focus : Color.primary.opacity(0.12))
                        .frame(width: 8, height: 8)
                }
            }
            Text("Cycle \(completed + 1) of \(total)")
                .font(FFType.meta)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, FFSpacing.md)
        .padding(.vertical, FFSpacing.xs)
        .background(Color.white.opacity(0.05), in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(Color.white.opacity(0.12))
        }
    }
}
