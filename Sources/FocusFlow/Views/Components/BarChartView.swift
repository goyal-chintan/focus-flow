import SwiftUI

struct BarChartView: View {
    let data: [(label: String, value: Double)]
    let accentColor: Color

    private var maxValue: Double { data.map(\.value).max() ?? 1 }

    var body: some View {
        HStack(alignment: .bottom, spacing: FFSpacing.sm) {
            ForEach(data.indices, id: \.self) { index in
                VStack(spacing: FFSpacing.xs) {
                    if data[index].value > 0 {
                        Text(formattedHours(data[index].value))
                            .font(FFType.micro)
                            .foregroundStyle(.tertiary)
                    }

                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.primary.opacity(0.05))

                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(
                                data[index].value > 0
                                ? LinearGradient(colors: [accentColor.opacity(0.45), accentColor], startPoint: .top, endPoint: .bottom)
                                : LinearGradient(colors: [Color.primary.opacity(0.05)], startPoint: .top, endPoint: .bottom)
                            )
                            .frame(height: max(8, CGFloat(data[index].value / maxValue) * 120))
                    }
                    .frame(height: 128)

                    Text(data[index].label)
                        .font(FFType.meta)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 176)
    }

    private func formattedHours(_ seconds: Double) -> String {
        let hours = seconds / 3600
        if hours >= 1 { return String(format: "%.1fh", hours) }
        return "\(Int(seconds / 60))m"
    }
}
