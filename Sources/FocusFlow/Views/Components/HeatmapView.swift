import SwiftUI

struct HeatmapView: View {
    let data: [(label: String, value: Double)]
    let maxValue: Double

    var body: some View {
        HStack(spacing: 3) {
            ForEach(data.indices, id: \.self) { index in
                let intensity = maxValue > 0 ? data[index].value / maxValue : 0

                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(heatColor(intensity: intensity))
                        .frame(height: 22)

                    if data.count <= 7 {
                        Text(data[index].label)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func heatColor(intensity: Double) -> Color {
        if intensity <= 0 { return Color.white.opacity(0.04) }
        if intensity < 0.25 { return Color(hex: 0x3DA86A).opacity(0.2) }
        if intensity < 0.50 { return Color(hex: 0x3DA86A).opacity(0.4) }
        if intensity < 0.75 { return Color(hex: 0x3DA86A).opacity(0.6) }
        return Color(hex: 0x3DA86A).opacity(0.85)
    }
}
