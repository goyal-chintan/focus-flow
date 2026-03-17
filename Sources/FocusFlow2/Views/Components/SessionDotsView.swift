import SwiftUI

struct SessionDotsView: View {
    let completed: Int
    let total: Int

    var body: some View {
        HStack(spacing: FFSpacing.sm) {
            ForEach(0..<total, id: \.self) { index in
                Circle()
                    .fill(index < completed ? FFColor.focus : Color.primary.opacity(0.10))
                    .frame(width: 8, height: 8)
                    .scaleEffect(index < completed ? 1.0 : 0.84)
                    .animation(FFMotion.control.delay(Double(index) * 0.04), value: completed)
            }
        }
        .contentTransition(.interpolate)
    }
}
