import SwiftUI

struct ProjectTimeBar: View {
    let name: String
    let duration: TimeInterval
    let maxDuration: TimeInterval
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: FFSpacing.xs) {
            HStack {
                Text(name)
                    .font(FFType.body.weight(.medium))
                Spacer()
                Text(duration.formattedFocusTime)
                    .font(FFType.meta.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            LinearGradient(colors: [color.opacity(0.45), color], startPoint: .leading, endPoint: .trailing)
                        )
                        .frame(width: max(6, geo.size.width * ratio))
                }
            }
            .frame(height: 10)
        }
        .padding(.horizontal, FFSpacing.md)
        .padding(.vertical, FFSpacing.sm)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: FFRadius.card, style: .continuous))
    }

    private var ratio: Double {
        guard maxDuration > 0 else { return 0 }
        return min(1, duration / maxDuration)
    }
}
