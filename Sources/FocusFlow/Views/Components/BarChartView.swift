import SwiftUI

struct BarChartView: View {
    let data: [(label: String, value: Double)]
    let accentColor: Color

    private let chartHeight: CGFloat = 112
    private var maxValue: Double { max(data.map(\.value).max() ?? 0, 1) }

    var body: some View {
        HStack(alignment: .bottom, spacing: LiquidDesignTokens.Spacing.small) {
            ForEach(Array(data.enumerated()), id: \.offset) { _, item in
                chartBar(item)
            }
        }
        .frame(height: 154)
        .padding(.horizontal, 2)
    }

    private func chartBar(_ item: (label: String, value: Double)) -> some View {
        VStack(spacing: 6) {
            Text(item.value > 0 ? formattedHours(item.value) : "")
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(.tertiary)
                .frame(height: 12)

            ZStack(alignment: .bottom) {
                Capsule(style: .continuous)
                    .fill(.primary.opacity(0.07))

                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                accentColor.opacity(0.42),
                                accentColor.opacity(item.value > 0 ? 0.95 : 0.08)
                            ],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(height: max(4, CGFloat(item.value / maxValue) * chartHeight))
            }
            .frame(height: chartHeight)

            Text(item.label)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(height: 12)
        }
        .frame(maxWidth: .infinity)
    }

    private func formattedHours(_ seconds: Double) -> String {
        let hours = seconds / 3600
        if hours >= 1 { return String(format: "%.1fh", hours) }
        return "\(Int(seconds / 60))m"
    }
}
