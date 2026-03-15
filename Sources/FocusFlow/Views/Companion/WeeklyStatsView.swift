import SwiftUI
import SwiftData

struct WeeklyStatsView: View {
    @Query(sort: \FocusSession.startedAt) private var allSessions: [FocusSession]
    @State private var selectedPeriod: Period = .week

    enum Period: String, CaseIterable {
        case week = "7 Days"
        case month = "30 Days"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Period picker
                Picker("Period", selection: $selectedPeriod) {
                    ForEach(Period.allCases, id: \.self) { period in
                        Text(period.rawValue).tag(period)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)
                .frame(maxWidth: .infinity, alignment: .trailing)

                // Bar chart
                VStack(alignment: .leading, spacing: 14) {
                    Text(selectedPeriod == .week ? "This Week" : "Last 30 Days")
                        .font(.headline)

                    BarChartView(data: chartData, accentColor: .blue)
                }

                // Summary cards
                HStack(spacing: 12) {
                    StatCard(
                        title: "Daily Average",
                        value: dailyAverage.formattedFocusTime,
                        icon: "chart.line.uptrend.xyaxis",
                        color: .purple
                    )
                    StatCard(
                        title: "Best Day",
                        value: bestDayDuration.formattedFocusTime,
                        icon: "star.fill",
                        color: .yellow
                    )
                    StatCard(
                        title: "Total",
                        value: periodTotal.formattedFocusTime,
                        icon: "sum",
                        color: .blue
                    )
                }
            }
            .padding(24)
        }
        .background(.background)
        .animation(.smooth, value: selectedPeriod)
    }

    private var days: Int { selectedPeriod == .week ? 7 : 30 }

    private var chartData: [(label: String, value: Double)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let focusSessions = allSessions.filter { $0.type == .focus && $0.completed }

        return (0..<days).map { offset in
            let day = calendar.date(byAdding: .day, value: -(days - 1 - offset), to: today)!
            let nextDay = calendar.date(byAdding: .day, value: 1, to: day)!
            let total = focusSessions
                .filter { $0.startedAt >= day && $0.startedAt < nextDay }
                .reduce(0.0) { $0 + $1.actualDuration }

            let label: String
            if days == 7 {
                label = day.formatted(.dateTime.weekday(.abbreviated))
            } else {
                label = day.formatted(.dateTime.day())
            }
            return (label: label, value: total)
        }
    }

    private var periodTotal: TimeInterval {
        chartData.reduce(0) { $0 + $1.value }
    }

    private var dailyAverage: TimeInterval {
        let nonZeroDays = chartData.filter { $0.value > 0 }.count
        guard nonZeroDays > 0 else { return 0 }
        return periodTotal / Double(nonZeroDays)
    }

    private var bestDayDuration: TimeInterval {
        chartData.map(\.value).max() ?? 0
    }

    private var bestDayLabel: String {
        guard let bestIdx = chartData.indices.max(by: { chartData[$0].value < chartData[$1].value }) else { return "" }
        return chartData[bestIdx].label
    }

}
