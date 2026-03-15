import SwiftUI

struct BarChartView: View {
    let data: [(label: String, value: Double)]
    let accentColor: Color

    private var maxValue: Double { data.map(\.value).max() ?? 1 }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(data.indices, id: \.self) { index in
                VStack(spacing: 4) {
                    if data[index].value > 0 {
                        Text(formattedHours(data[index].value))
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }

                    RoundedRectangle(cornerRadius: 4)
                        .fill(data[index].value > 0 ? accentColor : Color.primary.opacity(0.05))
                        .frame(height: max(2, CGFloat(data[index].value / maxValue) * 100))

                    Text(data[index].label)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 140)
    }

    private func formattedHours(_ seconds: Double) -> String {
        let hours = seconds / 3600
        if hours >= 1 { return String(format: "%.1fh", hours) }
        return "\(Int(seconds / 60))m"
    }
}
