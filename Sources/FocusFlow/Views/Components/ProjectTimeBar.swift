import SwiftUI

struct ProjectTimeBar: View {
    let name: String
    let duration: TimeInterval
    let maxDuration: TimeInterval
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(name)
                    .font(.subheadline)
                Spacer()
                Text(duration.formattedFocusTime)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.primary.opacity(0.06))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color)
                        .frame(width: max(2, geo.size.width * ratio))
                }
            }
            .frame(height: 4)
        }
    }

    private var ratio: Double {
        guard maxDuration > 0 else { return 0 }
        return min(1, duration / maxDuration)
    }
}
