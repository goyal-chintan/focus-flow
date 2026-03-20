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
            VStack(spacing: 20) {
                periodSection
                chartSection
                summarySection
            }
            .padding(24)
        }
        .background(.ultraThinMaterial)
        .animation(FFMotion.section, value: selectedPeriod)
    }

    private var periodSection: some View {
        LiquidGlassPanel {
            VStack(alignment: .leading, spacing: 12) {
                LiquidSectionHeader(
                    "Trends",
                    subtitle: "Track consistency and workload over time"
                )

                HStack(spacing: 6) {
                    ForEach(Period.allCases, id: \.self) { period in
                        Button {
                            selectedPeriod = period
                        } label: {
                            Text(period.rawValue)
                                .font(.system(size: 13, weight: selectedPeriod == period ? .semibold : .medium))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                        }
                        .if(selectedPeriod == period) { view in
                            view.buttonStyle(.glassProminent)
                                .tint(LiquidDesignTokens.Spectral.primaryContainer)
                        }
                        .if(selectedPeriod != period) { view in
                            view.buttonStyle(.glass)
                        }
                        .buttonBorderShape(.capsule)
                    }
                }
            }
            .padding(16)
        }
    }

    private var chartSection: some View {
        LiquidGlassPanel {
            VStack(alignment: .leading, spacing: 14) {
                LiquidSectionHeader(
                    selectedPeriod == .week ? "This Week" : "Last 30 Days",
                    subtitle: chartSubtitle
                )

                BarChartView(data: chartData, accentColor: .blue)
            }
            .padding(16)
        }
    }

    private var summarySection: some View {
        HStack(spacing: 12) {
            StatCard(
                title: "Daily Average",
                value: dailyAverage.formattedFocusTime,
                icon: "chart.line.uptrend.xyaxis",
                color: .purple,
                subtitle: activeDays > 0 ? "\(activeDays) active day\(activeDays == 1 ? "" : "s")" : nil
            )
            StatCard(
                title: "Best Day",
                value: bestDayDuration.formattedFocusTime,
                icon: "star.fill",
                color: .yellow,
                subtitle: bestDayLabel.isEmpty ? nil : bestDayLabel
            )
            StatCard(
                title: "Total",
                value: periodTotal.formattedFocusTime,
                icon: "sum",
                color: .blue,
                subtitle: "\(selectedPeriod == .week ? "7" : "30") day period"
            )
        }
    }

    private var activeDays: Int {
        chartData.filter { $0.value > 0 }.count
    }

    private var chartSubtitle: String {
        if bestDayDuration <= 0 {
            return "No focus time logged in this period"
        }
        return "Best day: \(bestDayLabel) · \(bestDayDuration.formattedFocusTime)"
    }

    private var days: Int { selectedPeriod == .week ? 7 : 30 }

    private var chartData: [(label: String, value: Double)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let focusSessions = allSessions.filter { $0.type == .focus }

        return (0..<days).map { offset in
            let day = calendar.date(byAdding: .day, value: -(days - 1 - offset), to: today)!
            let nextDay = calendar.date(byAdding: .day, value: 1, to: day)!
            // Attribute time correctly for sessions spanning midnight
            let total = focusSessions.reduce(0.0) { sum, session in
                let sessionStart = session.startedAt
                let sessionEnd = session.endedAt ?? sessionStart.addingTimeInterval(session.actualDuration)
                // Skip sessions that don't overlap this day at all
                guard sessionEnd > day && sessionStart < nextDay else { return sum }
                // Clamp to this day's boundaries
                let overlapStart = max(sessionStart, day)
                let overlapEnd = min(sessionEnd, nextDay)
                return sum + overlapEnd.timeIntervalSince(overlapStart)
            }

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
