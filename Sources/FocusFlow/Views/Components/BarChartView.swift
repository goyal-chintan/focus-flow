import SwiftUI

struct BarChartView: View {
    let data: [(label: String, value: Double)]
    let accentColor: Color
    var selectedIndex: Int? = nil
    var onSelect: ((Int) -> Void)? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let chartHeight: CGFloat = 112
    private var maxValue: Double { max(data.map(\.value).max() ?? 0, 1) }

    var body: some View {
        HStack(alignment: .bottom, spacing: LiquidDesignTokens.Spacing.small) {
            ForEach(Array(data.enumerated()), id: \.offset) { index, item in
                chartBar(item, index: index)
            }
        }
        .frame(height: 154)
        .padding(.horizontal, 2)
    }

    private func chartBar(_ item: (label: String, value: Double), index: Int) -> some View {
        let isSelected = selectedIndex == index
        let dimmed = selectedIndex != nil && !isSelected

        return VStack(spacing: 6) {
            Text(item.value > 0 ? formattedHours(item.value) : "")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.tertiary)
                .frame(height: 12)

            ZStack(alignment: .bottom) {
                Capsule(style: .continuous)
                    .fill(.primary.opacity(0.07))
                    .frame(maxWidth: 14)

                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                accentColor.opacity(0.15),
                                accentColor.opacity(item.value > 0 ? 0.85 : 0.08)
                            ],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(maxWidth: 14)
                    .frame(height: max(4, CGFloat(item.value / maxValue) * chartHeight))
                    .shadow(color: isSelected ? accentColor.opacity(0.4) : .clear, radius: 6, y: 0)
            }
            .frame(height: chartHeight)

            Text(item.label)
                .font(.system(size: 10, weight: isSelected ? .semibold : .medium, design: .rounded))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(height: 12)
        }
        .frame(maxWidth: .infinity)
        .opacity(dimmed ? 0.6 : 1.0)
        .contentShape(Rectangle())
        .onTapGesture { onSelect?(index) }
        .animation(reduceMotion ? nil : FFMotion.control, value: selectedIndex)
    }

    private func formattedHours(_ seconds: Double) -> String {
        let hours = seconds / 3600
        if hours >= 1 { return String(format: "%.1fh", hours) }
        return "\(Int(seconds / 60))m"
    }
}
