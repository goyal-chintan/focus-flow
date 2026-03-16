import SwiftUI

struct SessionDotsView: View {
    let completed: Int
    let total: Int

    var body: some View {
        HStack(spacing: FFSpacing.xs) {
            ForEach(0..<total, id: \.self) { index in
                Circle()
                    .fill(index < completed ? FFColor.focus : Color.primary.opacity(0.12))
                    .frame(width: 7, height: 7)
                    .scaleEffect(index < completed ? 1.0 : 0.84)
                    .animation(FFMotion.control.delay(Double(index) * 0.04), value: completed)
            }
        }
        .contentTransition(.interpolate)
    }
}
