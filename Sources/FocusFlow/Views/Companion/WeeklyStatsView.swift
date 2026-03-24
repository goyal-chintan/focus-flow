import SwiftUI
import SwiftData

struct WeeklyStatsView: View {
    @Query(sort: \FocusSession.startedAt) private var allSessions: [FocusSession]
    @State private var selectedPeriod: Period = .week
    @State private var selectedDayIndex: Int? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Period: String, CaseIterable {
        case week = "7 Days"
        case month = "30 Days"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                periodSection
                chartSection
                heatmapSection
                summarySection
                streakSection
            }
            .padding(24)
        }
        .background(.ultraThinMaterial)
        .animation(reduceMotion ? nil : FFMotion.section, value: selectedPeriod)
        .animation(reduceMotion ? nil : FFMotion.section, value: selectedDayIndex)
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
                                .frame(minHeight: 44)
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
        guard let day = calendar.date(byAdding: .day, value: -(days - 1 - idx), to: today),
              let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else {
            return nil
        }

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
                title: "Peak Hour",
                value: peakHour,
                icon: "clock.fill",
                color: .orange,
                subtitle: peakHour != "—" ? "Most productive" : nil
            )
            StatCard(
                title: "Completion",
                value: completionRate,
                icon: "checkmark.seal.fill",
                color: .green,
                subtitle: periodSessionCount > 0 ? "\(periodCompletedCount)/\(periodSessionCount) sessions" : nil
            )
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Heatmap

    private var heatmapSection: some View {
        LiquidGlassPanel {
            VStack(alignment: .leading, spacing: 10) {
                LiquidSectionHeader(
                    "Focus Intensity",
                    subtitle: "Darker green = more focus time"
                )
                HeatmapView(
                    data: chartData,
                    maxValue: chartData.map(\.value).max() ?? 1
                )
            }
            .padding(16)
        }
    }

    // MARK: - Streak

    private var streakSection: some View {
        LiquidGlassPanel {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "flame.fill")
                            .foregroundStyle(.orange)
                            .font(.system(size: 16, weight: .semibold))
                        Text("\(currentStreak)")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                    }
                    Text("Day Streak")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                            .font(.system(size: 16, weight: .semibold))
                        Text("\(longestStreak)")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                    }
                    Text("Best Streak")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
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

        return (0..<days).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -(days - 1 - offset), to: today),
                  let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else {
                return nil
            }
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

    // MARK: - Peak Hour

    private var peakHour: String {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let periodStart = calendar.date(byAdding: .day, value: -(days - 1), to: today) else {
            return "—"
        }
        let focusSessions = allSessions.filter { session in
            session.type == .focus && session.startedAt >= periodStart
        }
        var hourBuckets = [Int: TimeInterval]()
        for session in focusSessions {
            let hour = calendar.component(.hour, from: session.startedAt)
            hourBuckets[hour, default: 0] += session.actualDuration
        }
        guard let bestHour = hourBuckets.max(by: { $0.value < $1.value })?.key else { return "—" }
        guard let date = calendar.date(from: DateComponents(year: 2001, month: 1, day: 1, hour: bestHour)) else {
            return "—"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "ha"
        return formatter.string(from: date).lowercased()
    }

    // MARK: - Completion Rate

    private var periodSessionCount: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let periodStart = calendar.date(byAdding: .day, value: -(days - 1), to: today) else { return 0 }
        return allSessions.filter { $0.type == .focus && $0.startedAt >= periodStart }.count
    }

    private var periodCompletedCount: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let periodStart = calendar.date(byAdding: .day, value: -(days - 1), to: today) else { return 0 }
        return allSessions.filter { $0.type == .focus && $0.completed && $0.startedAt >= periodStart }.count
    }

    private var completionRate: String {
        guard periodSessionCount > 0 else { return "—" }
        return "\(Int(Double(periodCompletedCount) / Double(periodSessionCount) * 100))%"
    }

    // MARK: - Streaks

    private var currentStreak: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var streak = 0
        var dayOffset = 0
        while true {
            guard let day = calendar.date(byAdding: .day, value: -dayOffset, to: today),
                  let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else {
                break
            }
            let hasFocus = allSessions.contains { session in
                session.type == .focus && session.completed &&
                session.startedAt >= day && session.startedAt < nextDay
            }
            if hasFocus {
                streak += 1
                dayOffset += 1
            } else if dayOffset == 0 {
                // Today might not have a session yet — check yesterday
                dayOffset += 1
            } else {
                break
            }
        }
        return streak
    }

    private var longestStreak: Int {
        let calendar = Calendar.current
        let focusSessions = allSessions.filter { $0.type == .focus && $0.completed }
        guard !focusSessions.isEmpty else { return 0 }
        let days = Set(focusSessions.map { calendar.startOfDay(for: $0.startedAt) }).sorted()
        guard !days.isEmpty else { return 0 }
        var maxStreak = 1
        var current = 1
        for i in 1..<days.count {
            let diff = calendar.dateComponents([.day], from: days[i-1], to: days[i]).day ?? 0
            if diff == 1 {
                current += 1
                maxStreak = max(maxStreak, current)
            } else {
                current = 1
            }
        }
        return maxStreak
    }

}
