import SwiftUI

struct BarChartView: View {
    let data: [(label: String, value: Double)]
    let accentColor: Color

    private var maxValue: Double {
        data.map(\.value).max() ?? 1
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(data.indices, id: \.self) { index in
                VStack(spacing: 6) {
                    if data[index].value > 0 {
                        Text(formattedHours(data[index].value))
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("")
                            .font(.system(size: 10))
                    }

                    RoundedRectangle(cornerRadius: 6)
                        .fill(accentColor.gradient)
                        .opacity(data[index].value > 0 ? 1 : 0.15)
                        .frame(height: max(4, CGFloat(data[index].value / maxValue) * 120))
                        .animation(.spring(response: 0.5, dampingFraction: 0.75).delay(Double(index) * 0.05), value: data[index].value)

                    Text(data[index].label)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 160)
    }

    private func formattedHours(_ seconds: Double) -> String {
        let hours = seconds / 3600
        if hours >= 1 { return String(format: "%.1fh", hours) }
        let mins = Int(seconds / 60)
        return "\(mins)m"
    }
}
