import SwiftUI
import SwiftData

struct WeeklyStatsView: View {
    @Query(sort: \FocusSession.startedAt) private var allSessions: [FocusSession]
    @State private var selectedPeriod: Period = .week
    @State private var selectedDayIndex: Int? = nil

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
        .animation(FFMotion.section, value: selectedDayIndex)
        .onChange(of: selectedPeriod) { _, _ in selectedDayIndex = nil }
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

                BarChartView(
                    data: chartData,
                    accentColor: .blue,
                    selectedIndex: selectedDayIndex,
                    onSelect: { index in
                        selectedDayIndex = selectedDayIndex == index ? nil : index
                    }
                )

                if let detail = selectedDayDetail {
                    dayDetailCard(detail)
                        .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                }
            }
            .padding(16)
        }
    }

    // MARK: - Day Detail Card

    private struct DayDetail {
        let dayLabel: String
        let totalFocus: TimeInterval
        let sessionCount: Int
        let averageLength: TimeInterval
    }

    private var selectedDayDetail: DayDetail? {
        guard let idx = selectedDayIndex, idx < chartData.count else { return nil }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let day = calendar.date(byAdding: .day, value: -(days - 1 - idx), to: today)!
        let nextDay = calendar.date(byAdding: .day, value: 1, to: day)!

        let focusSessions = allSessions.filter { $0.type == .focus }
        var totalSeconds: TimeInterval = 0
        var completedCount = 0

        for session in focusSessions {
            let sessionStart = session.startedAt
            let sessionEnd = session.endedAt ?? sessionStart.addingTimeInterval(session.actualDuration)
            guard sessionEnd > day && sessionStart < nextDay else { continue }
            let overlapStart = max(sessionStart, day)
            let overlapEnd = min(sessionEnd, nextDay)
            totalSeconds += overlapEnd.timeIntervalSince(overlapStart)
            if session.completed { completedCount += 1 }
        }

        let dayLabel = day.formatted(.dateTime.weekday(.wide).month(.wide).day())

        return DayDetail(
            dayLabel: dayLabel,
            totalFocus: totalSeconds,
            sessionCount: completedCount,
            averageLength: completedCount > 0 ? totalSeconds / Double(completedCount) : 0
        )
    }

    private func dayDetailCard(_ detail: DayDetail) -> some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(detail.dayLabel)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)

                Text(detail.totalFocus.formattedFocusTime)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(LiquidDesignTokens.Spectral.primaryContainer)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                Label("\(detail.sessionCount) session\(detail.sessionCount == 1 ? "" : "s")", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)

                Label("Avg \(detail.averageLength.formattedFocusTime)", systemImage: "timer")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
            let total = focusSessions.reduce(0.0) { sum, session in
                let sessionStart = session.startedAt
                let sessionEnd = session.endedAt ?? sessionStart.addingTimeInterval(session.actualDuration)
                guard sessionEnd > day && sessionStart < nextDay else { return sum }
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
