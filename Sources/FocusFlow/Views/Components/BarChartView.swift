import SwiftUI

struct BarChartView: View {
    let data: [(label: String, value: Double)]
    let accentColor: Color

    @State private var appeared = false

    private var maxValue: Double {
        data.map(\.value).max() ?? 1
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(data.indices, id: \.self) { index in
                let isToday = index == data.count - 1
                VStack(spacing: 6) {
                    if data[index].value > 0 {
                        Text(formattedHours(data[index].value))
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("")
                            .font(.system(size: 10))
                    }

                    UnevenRoundedRectangle(
                        topLeadingRadius: 8,
                        bottomLeadingRadius: 3,
                        bottomTrailingRadius: 3,
                        topTrailingRadius: 8
                    )
                    .fill(
                        LinearGradient(
                            colors: [
                                (isToday ? accentColor : accentColor).opacity(0.3),
                                isToday ? accentColor : accentColor.opacity(0.85)
                            ],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .opacity(data[index].value > 0 ? 1 : 0.15)
                    .frame(
                        height: appeared
                            ? max(4, CGFloat(data[index].value / maxValue) * 120)
                            : 4
                    )
                    .shadow(
                        color: isToday ? accentColor.opacity(0.3) : .clear,
                        radius: 4, x: 0, y: 0
                    )

                    Text(data[index].label)
                        .font(.system(size: 11, weight: isToday ? .bold : .medium, design: .rounded))
                        .foregroundStyle(isToday ? .primary : .secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 160)
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.75)) {
                appeared = true
            }
        }
    }

    private func formattedHours(_ seconds: Double) -> String {
        let hours = seconds / 3600
        if hours >= 1 { return String(format: "%.1fh", hours) }
        let mins = Int(seconds / 60)
        return "\(mins)m"
    }
}
