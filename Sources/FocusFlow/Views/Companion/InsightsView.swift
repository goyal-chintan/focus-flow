import SwiftUI
import SwiftData

struct InsightsView: View {
    @Query(sort: \FocusSession.startedAt) private var allSessions: [FocusSession]
    @Query private var allSettings: [AppSettings]
    @Query(sort: \AppUsageRecord.date) private var usageRecords: [AppUsageRecord]
    @State private var selectedHour: Int? = nil

    private var dailyGoal: TimeInterval {
        allSettings.first?.dailyFocusGoal ?? 7200
    }

    private var focusSessions: [FocusSession] {
        allSessions.filter { $0.type == .focus }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerSection
                productiveHoursSection
                durationDistributionSection
                breakBehaviorSection
                weeklyTrendSection
                scienceTipsSection
            }
            .padding(24)
        }
        .background(.ultraThinMaterial)
        .animation(FFMotion.section, value: selectedHour)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Insights")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(LiquidDesignTokens.Surface.onSurface)

            Text("Patterns and productivity analysis from your focus sessions.")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(LiquidDesignTokens.Surface.onSurfaceMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Productive Hours

    private var productiveHoursSection: some View {
        LiquidGlassPanel {
            VStack(alignment: .leading, spacing: 14) {
                LiquidSectionHeader(
                    "Productive Hours",
                    subtitle: bestHourSummary
                )

                VStack(spacing: 2) {
                    ForEach(hourlyData, id: \.hour) { item in
                        productiveHourBar(item)
                    }
                }
            }
            .padding(16)
        }
    }

    private struct HourData: Identifiable {
        let hour: Int
        let totalMinutes: Double
        var id: Int { hour }

        var label: String {
            let formatter = DateFormatter()
            formatter.dateFormat = "ha"
            let date = Calendar.current.date(from: DateComponents(hour: hour))!
            return formatter.string(from: date).lowercased()
        }
    }

    private var hourlyData: [HourData] {
        var buckets = [Int: TimeInterval]()
        for session in focusSessions {
            let hour = Calendar.current.component(.hour, from: session.startedAt)
            buckets[hour, default: 0] += session.actualDuration
        }
        // Show hours 5am to midnight (typical productive range)
        return (5..<24).compactMap { hour in
            let minutes = (buckets[hour] ?? 0) / 60
            // Only show hours that have data or are in work hours (8-20)
            guard minutes > 0 || (hour >= 8 && hour <= 20) else { return nil }
            return HourData(hour: hour, totalMinutes: minutes)
        }
    }

    private var maxHourlyMinutes: Double {
        max(hourlyData.map(\.totalMinutes).max() ?? 1, 1)
    }

    private var bestHourSummary: String {
        guard let best = hourlyData.max(by: { $0.totalMinutes < $1.totalMinutes }),
              best.totalMinutes > 0 else {
            return "Complete sessions to reveal your peak hours"
        }
        return "Your peak is \(best.label) · \(Int(best.totalMinutes))m total"
    }

    private func productiveHourBar(_ item: HourData) -> some View {
        let isSelected = selectedHour == item.hour
        let width = item.totalMinutes / maxHourlyMinutes

        return HStack(spacing: 8) {
            Text(item.label)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .frame(width: 36, alignment: .trailing)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.white.opacity(0.04))

                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    LiquidDesignTokens.Spectral.primaryContainer.opacity(0.6),
                                    LiquidDesignTokens.Spectral.electricBlue.opacity(0.8)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(2, geo.size.width * width))
                        .shadow(color: isSelected ? LiquidDesignTokens.Spectral.primaryContainer.opacity(0.3) : .clear, radius: 4)
                }
            }
            .frame(height: 14)

            if item.totalMinutes > 0 {
                Text("\(Int(item.totalMinutes))m")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .frame(width: 30, alignment: .leading)
            } else {
                Color.clear.frame(width: 30)
            }
        }
        .frame(height: 30)
        .contentShape(Rectangle())
        .onTapGesture { selectedHour = selectedHour == item.hour ? nil : item.hour }
        .accessibilityLabel("\(item.label), \(Int(item.totalMinutes)) minutes total")
        .accessibilityHint("Double-tap to toggle selection")
    }

    // MARK: - Duration Distribution

    private var durationDistributionSection: some View {
        LiquidGlassPanel {
            VStack(alignment: .leading, spacing: 14) {
                LiquidSectionHeader(
                    "Session Lengths",
                    subtitle: averageDurationSummary
                )

                HStack(spacing: 4) {
                    ForEach(durationBuckets, id: \.label) { bucket in
                        VStack(spacing: 6) {
                            Text("\(bucket.count)")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(bucket.count > 0 ? .primary : .tertiary)

                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(bucketColor(bucket.index))
                                .frame(height: max(4, CGFloat(bucket.count) / CGFloat(maxBucketCount) * 80))

                            Text(bucket.label)
                                .font(.system(size: 9, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 120)
                .padding(.horizontal, 4)
            }
            .padding(16)
        }
    }

    private struct DurationBucket {
        let label: String
        let count: Int
        let index: Int
    }

    private var durationBuckets: [DurationBucket] {
        let ranges: [(String, (TimeInterval, TimeInterval))] = [
            ("<10m", (0, 600)),
            ("10-20m", (600, 1200)),
            ("20-30m", (1200, 1800)),
            ("30-45m", (1800, 2700)),
            ("45-60m", (2700, 3600)),
            ("60m+", (3600, .infinity))
        ]
        return ranges.enumerated().map { idx, range in
            let count = focusSessions.filter { d in
                let dur = d.actualDuration
                return dur >= range.1.0 && dur < range.1.1
            }.count
            return DurationBucket(label: range.0, count: count, index: idx)
        }
    }

    private var maxBucketCount: Int {
        max(durationBuckets.map(\.count).max() ?? 1, 1)
    }

    private var averageDurationSummary: String {
        guard !focusSessions.isEmpty else { return "No sessions yet" }
        let avg = focusSessions.reduce(0.0) { $0 + $1.actualDuration } / Double(focusSessions.count)
        return "Average session: \(Int(avg / 60))m across \(focusSessions.count) sessions"
    }

    private func bucketColor(_ index: Int) -> Color {
        let colors: [Color] = [
            Color(hex: 0x3E90FF).opacity(0.3),
            Color(hex: 0x3E90FF).opacity(0.45),
            Color(hex: 0x3E90FF).opacity(0.6),
            Color(hex: 0x3E90FF).opacity(0.7),
            Color(hex: 0x3E90FF).opacity(0.8),
            Color(hex: 0x3E90FF).opacity(0.9)
        ]
        return colors[min(index, colors.count - 1)]
    }

    // MARK: - Break Behavior

    private var breakBehaviorSection: some View {
        LiquidGlassPanel {
            VStack(alignment: .leading, spacing: 14) {
                LiquidSectionHeader(
                    "Break Analysis",
                    subtitle: "How well you take breaks"
                )

                HStack(spacing: 12) {
                    StatCard(
                        title: "Avg Break",
                        value: averageBreakLength,
                        icon: "cup.and.saucer.fill",
                        color: .green,
                        subtitle: totalBreaks > 0 ? "\(totalBreaks) breaks" : nil
                    )
                    StatCard(
                        title: "Break Rate",
                        value: breakRate,
                        icon: "arrow.triangle.branch",
                        color: .teal,
                        subtitle: breakRateSubtitle
                    )
                    StatCard(
                        title: "Best Day",
                        value: bestDay.formattedFocusTime,
                        icon: "star.fill",
                        color: .yellow,
                        subtitle: bestDayLabel
                    )
                }
            }
            .padding(16)
        }
    }

    private var totalBreaks: Int {
        allSessions.filter { $0.type != .focus }.count
    }

    private var averageBreakLength: String {
        let breaks = allSessions.filter { $0.type != .focus }
        guard !breaks.isEmpty else { return "—" }
        let avg = breaks.reduce(0.0) { $0 + $1.actualDuration } / Double(breaks.count)
        return "\(Int(avg / 60))m"
    }

    private var breakRate: String {
        let totalFocusSessions = focusSessions.filter(\.completed).count
        guard totalFocusSessions > 0 else { return "—" }
        let ratio = Double(totalBreaks) / Double(totalFocusSessions)
        return String(format: "%.0f%%", ratio * 100)
    }

    private var breakRateSubtitle: String {
        totalBreaks > 0 ? "Breaks/sessions" : "No data"
    }

    private var bestDay: TimeInterval {
        let calendar = Calendar.current
        var dailyTotals = [Date: TimeInterval]()
        for session in focusSessions {
            let day = calendar.startOfDay(for: session.startedAt)
            dailyTotals[day, default: 0] += session.actualDuration
        }
        return dailyTotals.values.max() ?? 0
    }

    private var bestDayLabel: String {
        let calendar = Calendar.current
        var dailyTotals = [Date: TimeInterval]()
        for session in focusSessions {
            let day = calendar.startOfDay(for: session.startedAt)
            dailyTotals[day, default: 0] += session.actualDuration
        }
        guard let best = dailyTotals.max(by: { $0.value < $1.value }) else { return "" }
        return best.key.formatted(.dateTime.month(.abbreviated).day())
    }

    // MARK: - Weekly Trend (Sparkline)

    private var weeklyTrendSection: some View {
        LiquidGlassPanel {
            VStack(alignment: .leading, spacing: 14) {
                LiquidSectionHeader(
                    "30-Day Trend",
                    subtitle: trendSummary
                )

                SparklineView(data: last30DaysData)
                    .frame(height: 60)
            }
            .padding(16)
        }
    }

    private var last30DaysData: [Double] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<30).map { offset in
            let day = calendar.date(byAdding: .day, value: -(29 - offset), to: today)!
            let nextDay = calendar.date(byAdding: .day, value: 1, to: day)!
            return focusSessions.reduce(0.0) { sum, session in
                let sessionEnd = session.endedAt ?? session.startedAt.addingTimeInterval(session.actualDuration)
                guard sessionEnd > day && session.startedAt < nextDay else { return sum }
                let overlapStart = max(session.startedAt, day)
                let overlapEnd = min(sessionEnd, nextDay)
                return sum + max(0, overlapEnd.timeIntervalSince(overlapStart))
            }
        }
    }

    private var trendSummary: String {
        let data = last30DaysData
        let firstHalf = data.prefix(15).reduce(0, +)
        let secondHalf = data.suffix(15).reduce(0, +)
        guard firstHalf > 0 else {
            return secondHalf > 0 ? "Getting started — keep building the habit!" : "No data yet"
        }
        let change = ((secondHalf - firstHalf) / firstHalf) * 100
        if change > 10 {
            return "Trending up \(Int(change))% — great momentum!"
        } else if change < -10 {
            return "Down \(Int(abs(change)))% from earlier — a fresh start awaits"
        }
        return "Steady pace — consistency is key"
    }

    // MARK: - Science Tips

    private var scienceTipsSection: some View {
        LiquidGlassPanel {
            VStack(alignment: .leading, spacing: 14) {
                LiquidSectionHeader(
                    "Focus Science",
                    subtitle: "Research-backed tips for your patterns"
                )

                VStack(spacing: 10) {
                    ForEach(contextualTips, id: \.title) { tip in
                        scienceTipCard(tip)
                    }
                }
            }
            .padding(16)
        }
    }

    private struct ScienceTip {
        let icon: String
        let title: String
        let body: String
        let color: Color
    }

    private var contextualTips: [ScienceTip] {
        var tips = [ScienceTip]()

        // Tip based on average session length
        let avgDuration = focusSessions.isEmpty ? 0 : focusSessions.reduce(0.0) { $0 + $1.actualDuration } / Double(focusSessions.count)
        if avgDuration > 0 && avgDuration < 1500 {
            tips.append(ScienceTip(
                icon: "timer",
                title: "Build Up Gradually",
                body: "Your avg session is \(Int(avgDuration/60))m. Research shows working up to 25–50 min sessions maximizes deep work capacity.",
                color: .blue
            ))
        } else if avgDuration >= 2700 {
            tips.append(ScienceTip(
                icon: "brain",
                title: "Long Sessions Champion",
                body: "Sessions over 45m can deplete cognitive resources. Consider splitting into focused sprints with short breaks.",
                color: .purple
            ))
        }

        // Tip based on break behavior
        let breakTakenRatio = focusSessions.isEmpty ? 0 : Double(totalBreaks) / Double(focusSessions.count)
        if breakTakenRatio < 0.5 && focusSessions.count > 3 {
            tips.append(ScienceTip(
                icon: "cup.and.saucer.fill",
                title: "Take More Breaks",
                body: "You skip breaks often. The Pomodoro Technique works best with regular rest — it prevents mental fatigue and boosts creativity.",
                color: .green
            ))
        }

        // Tip based on consistency
        let activeDaysLast7 = last30DaysData.suffix(7).filter { $0 > 0 }.count
        if activeDaysLast7 >= 5 {
            tips.append(ScienceTip(
                icon: "flame.fill",
                title: "Consistency Superstar",
                body: "You've focused \(activeDaysLast7)/7 days this week. Consistency matters more than intensity for building lasting habits.",
                color: .orange
            ))
        } else if activeDaysLast7 <= 2 && focusSessions.count > 5 {
            tips.append(ScienceTip(
                icon: "calendar.badge.exclamationmark",
                title: "Build the Habit",
                body: "Try to focus at least 4 days a week. Even a single short session maintains your habit loop.",
                color: .red
            ))
        }

        // Always include a general tip if we have few contextual ones
        if tips.count < 2 {
            tips.append(ScienceTip(
                icon: "lightbulb.fill",
                title: "The 2-Minute Rule",
                body: "If you're procrastinating, commit to just 2 minutes of work. Starting is the hardest part — momentum follows.",
                color: .yellow
            ))
        }

        return Array(tips.prefix(3))
    }

    private func scienceTipCard(_ tip: ScienceTip) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: tip.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tip.color)
                .frame(width: 28, height: 28)
                .background(tip.color.opacity(0.15), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(tip.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(tip.body)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Sparkline

private struct SparklineView: View {
    let data: [Double]

    var body: some View {
        GeometryReader { geo in
            let maxVal = max(data.max() ?? 1, 1)
            let points = data.enumerated().map { index, value in
                CGPoint(
                    x: geo.size.width * CGFloat(index) / CGFloat(max(data.count - 1, 1)),
                    y: geo.size.height * (1 - CGFloat(value / maxVal))
                )
            }

            ZStack {
                // Fill area
                Path { path in
                    guard !points.isEmpty else { return }
                    path.move(to: CGPoint(x: points[0].x, y: geo.size.height))
                    path.addLine(to: points[0])
                    for point in points.dropFirst() {
                        path.addLine(to: point)
                    }
                    path.addLine(to: CGPoint(x: points.last!.x, y: geo.size.height))
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [
                            LiquidDesignTokens.Spectral.primaryContainer.opacity(0.2),
                            LiquidDesignTokens.Spectral.primaryContainer.opacity(0.02)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                // Line
                Path { path in
                    guard !points.isEmpty else { return }
                    path.move(to: points[0])
                    for point in points.dropFirst() {
                        path.addLine(to: point)
                    }
                }
                .stroke(
                    LinearGradient(
                        colors: [
                            LiquidDesignTokens.Spectral.primaryContainer,
                            LiquidDesignTokens.Spectral.electricBlue
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                )

                // End dot
                if let lastPoint = points.last {
                    Circle()
                        .fill(LiquidDesignTokens.Spectral.electricBlue)
                        .frame(width: 6, height: 6)
                        .position(lastPoint)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("30-day focus trend, ranging from \(Int((data.min() ?? 0) / 60)) to \(Int((data.max() ?? 0) / 60)) minutes per day")
    }
}
