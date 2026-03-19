import SwiftUI

struct ProjectTimeBar: View {
    let name: String
    let duration: TimeInterval
    let maxDuration: TimeInterval
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)

                Text(name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text(duration.formattedFocusTime)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()

                Text("\(percentage)%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(.primary.opacity(0.07))

                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.45), color],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(4, geo.size.width * ratio))
                }
            }
            .frame(height: 8)
        }
    }

    private var ratio: Double {
        guard maxDuration > 0 else { return 0 }
        return min(1, duration / maxDuration)
    }

    private var percentage: Int {
        guard maxDuration > 0 else { return 0 }
        return Int((duration / maxDuration * 100).rounded())
    }
}
