import SwiftUI
import SwiftData

/// History: how consistent am I over days, weeks and months? Merges the old Calendar and Week tabs.
struct HistoryView: View {
    enum Range: String, CaseIterable, Identifiable {
        case week = "Week"
        case month = "Month"
        case quarter = "3 Months"

        var id: String { rawValue }

        var dayCount: Int {
            switch self {
            case .week: 7
            case .month: 30
            case .quarter: 91
            }
        }
    }

    @Query(sort: \FocusSession.startedAt) private var sessions: [FocusSession]
    @Query private var allSettings: [AppSettings]
    @Environment(\.companionNowOverride) private var nowOverride

    @State private var range: Range
    @State private var selectedDay: Date?
    @State private var editingSession: FocusSession?

    init(initialRange: Range = .week) {
        _range = State(initialValue: initialRange)
    }

    var body: some View {
        let snapshot = CompanionSnapshot(sessions: sessions, settings: allSettings.first, now: nowOverride ?? Date())
        let days = snapshot.analytics.dailyTotals(snapshot.samples, trailing: range.dayCount, endingAt: snapshot.now)
        let summary = snapshot.analytics.rangeSummary(days, goal: snapshot.goal)
        let colors = ProjectColorScale(days.flatMap { $0.byProject.map(\.project) })

        ScrollView {
            VStack(alignment: .leading, spacing: FFSpace.sectionGap) {
                FFPageHeader("History", subtitle: rangeSubtitle(days)) {
                    FFSegmentedPicker(title: "Range", options: Range.allCases, selection: $range) { $0.rawValue }
                }

                summaryRow(summary, goal: snapshot.goal)

                FFSection("Daily focus", subtitle: "Stacked by project. A dot marks days you met your goal.") {
                    legend(colors)
                } content: {
                    DailyFocusChart(days: days, goal: snapshot.goal, colors: colors, selectedDay: $selectedDay, height: 230)
                }

                if range != .week {
                    FFSection("Consistency", subtitle: "Each square is a day. Green means you met your \(FFFormat.duration(snapshot.goal)) goal.") {
                        HStack(alignment: .top, spacing: FFSpace.xl) {
                            ConsistencyHeatmap(days: days, goal: snapshot.goal, analytics: snapshot.analytics, now: snapshot.now, selectedDay: $selectedDay)
                            consistencyFacts(days: days, goal: snapshot.goal, analytics: snapshot.analytics)
                        }
                    }
                    .transition(.opacity)
                }

                dayDetail(snapshot: snapshot, days: days)
            }
            .padding(FFSpace.page)
            .frame(maxWidth: 920, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(item: $editingSession) { session in
            SessionEditView(session: session)
        }
    }

    private func rangeSubtitle(_ days: [FocusAnalytics.DayTotal]) -> String {
        guard let first = days.first?.day, let last = days.last?.day else { return "" }
        let style = Date.FormatStyle.dateTime.day().month(.abbreviated)
        return "\(first.formatted(style)) – \(last.formatted(style))"
    }

    // MARK: - Summary

    private func summaryRow(_ summary: FocusAnalytics.RangeSummary, goal: TimeInterval) -> some View {
        HStack(alignment: .top, spacing: FFSpace.l) {
            FFStat(label: "Total", value: FFFormat.duration(summary.totalSeconds))
            Divider()
            FFStat(label: "Daily average", value: FFFormat.duration(summary.dailyAverageSeconds), caption: "Goal \(FFFormat.duration(goal))")
            Divider()
            FFStat(
                label: "Days goal met",
                value: "\(summary.goalMetDays)/\(summary.dayCount)",
                valueColor: summary.goalMetDays > 0 ? FFPalette.goal : nil
            )
            Divider()
            FFStat(
                label: "Best day",
                value: summary.bestDay.map { FFFormat.duration($0.seconds) } ?? "—",
                caption: summary.bestDay?.day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
            )
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(FFSpace.l)
        .ffSurface()
    }

    private func legend(_ colors: ProjectColorScale) -> some View {
        HStack(spacing: FFSpace.m) {
            ForEach(Array(zip(colors.domain, colors.range).prefix(5)), id: \.0) { name, color in
                FFLegendItem(color: color, label: name)
            }
            if colors.domain.count > 5 {
                Text("+\(colors.domain.count - 5)").ffText(.caption)
            }
        }
        .lineLimit(1)
    }

    // MARK: - Consistency facts

    private func consistencyFacts(days: [FocusAnalytics.DayTotal], goal: TimeInterval, analytics: FocusAnalytics) -> some View {
        let active = days.filter { $0.seconds > 0 }.count
        let met = days.filter { $0.seconds >= goal }
        var byWeekday = Array(repeating: 0, count: 7)
        for day in met { byWeekday[analytics.mondayFirstWeekdayIndex(of: day.day)] += 1 }
        let bestIndex = byWeekday.indices.max { byWeekday[$0] < byWeekday[$1] }
        var longest = 0
        var run = 0
        for day in days {
            run = day.seconds >= goal ? run + 1 : 0
            longest = max(longest, run)
        }
        return VStack(alignment: .leading, spacing: FFSpace.l) {
            Grid(alignment: .leading, horizontalSpacing: FFSpace.xl, verticalSpacing: FFSpace.l) {
                GridRow {
                    FFStat(label: "Goal met", value: "\(met.count) of \(days.count) days", valueColor: met.isEmpty ? nil : FFPalette.goal)
                    FFStat(label: "Days with any focus", value: "\(active)")
                }
                GridRow {
                    FFStat(label: "Longest run", value: longest == 1 ? "1 day" : "\(longest) days")
                    if let bestIndex, byWeekday[bestIndex] > 0 {
                        FFStat(label: "Most reliable day", value: FFFormat.weekdayShort[bestIndex], caption: "Goal met \(byWeekday[bestIndex]) times")
                    } else {
                        Color.clear.frame(height: 1)
                    }
                }
            }
            HStack(spacing: FFSpace.m) {
                ConsistencyHeatmap.legend
                FFLegendItem(color: FFPalette.goal, label: "Goal met")
            }
        }
        .frame(maxWidth: 380, alignment: .leading)
    }

    // MARK: - Day detail

    private func dayDetail(snapshot: CompanionSnapshot, days: [FocusAnalytics.DayTotal]) -> some View {
        let calendar = snapshot.calendar
        let day = selectedDay ?? days.last(where: { $0.seconds > 0 })?.day ?? snapshot.today.start
        let interval = snapshot.analytics.dayInterval(containing: day)
        let total = snapshot.analytics.dayTotal(snapshot.samples, on: day)
        let daySessions = sessions
            .filter { $0.type == .focus && $0.actualDuration >= 60 && $0.effectiveEnd > interval.start && $0.startedAt < interval.end }
            .sorted { $0.startedAt > $1.startedAt }
        let title = calendar.isDate(day, inSameDayAs: snapshot.now)
            ? "Today"
            : day.formatted(.dateTime.weekday(.wide).day().month(.wide))
        let subtitle = total.seconds > 0
            ? "\(FFFormat.duration(total.seconds)) · \(total.blocks) block\(total.blocks == 1 ? "" : "s")\(total.seconds >= snapshot.goal ? " · goal met" : "")"
            : "No focus blocks"

        return FFSection(title, subtitle: subtitle) {
            if selectedDay != nil {
                Button("Clear") { selectedDay = nil }
                    .buttonStyle(.link)
                    .font(FFTextStyle.callout.font)
            }
        } content: {
            if daySessions.isEmpty {
                FFEmptyState(systemImage: "calendar.badge.clock", message: "Nothing logged this day", detail: "Click any bar or square to see that day.")
            } else {
                VStack(spacing: 2) {
                    ForEach(daySessions) { session in
                        SessionRow(session: session) { editingSession = session }
                    }
                }
                .padding(.horizontal, -FFSpace.s)
            }
        }
        .id(interval.start)
        .transition(.opacity)
    }
}
