import SwiftUI
import SwiftData
import Charts

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
    @Query(filter: #Predicate<Project> { !$0.archived }) private var projects: [Project]
    @Environment(\.companionNowOverride) private var nowOverride

    @State private var range: Range
    @State private var selectedDay: Date?
    @State private var editingSession: FocusSession?

    init(initialRange: Range = .week) {
        _range = State(initialValue: initialRange)
    }

    var body: some View {
        let snapshot = CompanionSnapshot(sessions: sessions, settings: allSettings.first, projects: projects, now: nowOverride ?? Date())
        let days = snapshot.analytics.dailyTotals(snapshot.samples, trailing: range.dayCount, endingAt: snapshot.now)
        // Goal marks count own work once a project is marked Work: office time never meets the goal.
        let goalDays = snapshot.goalDays(days.map(\.day))
        let goalMet = Set(goalDays.filter { $0.seconds >= snapshot.goal }.map(\.day))
        let summary = snapshot.analytics.rangeSummary(days, goal: snapshot.goal)
        let colors = ProjectColorScale(days.flatMap { $0.byProject.map(\.project) }, faded: snapshot.workKeys)

        ScrollView {
            VStack(alignment: .leading, spacing: FFSpace.sectionGap) {
                FFPageHeader("History", subtitle: rangeSubtitle(days)) {
                    FFSegmentedPicker(title: "Range", options: Range.allCases, selection: $range) { $0.rawValue }
                }

                summaryRow(summary, goalMetDays: goalMet.count, goal: snapshot.goal, scope: snapshot.goalScope)

                FFSection("Daily focus", subtitle: snapshot.ownWorkOnly
                          ? "Stacked by project, Work faded. A dot marks days \(snapshot.goalScope.phrase) met the goal."
                          : "Stacked by project. A dot marks days you met your goal.") {
                    legend(colors)
                } content: {
                    HistoryFocusChart(days: days, goal: snapshot.goal, goalMet: goalMet, colors: colors, selectedDay: $selectedDay, height: 230)
                }

                if range != .week {
                    FFSection("Consistency", subtitle: snapshot.ownWorkOnly
                              ? "Each square is a day of \(snapshot.goalScope.phrase). Green means it met your \(FFFormat.duration(snapshot.goal)) goal."
                              : "Each square is a day. Green means you met your \(FFFormat.duration(snapshot.goal)) goal.") {
                        HStack(alignment: .top, spacing: FFSpace.xl) {
                            ConsistencyHeatmap(days: goalDays, goal: snapshot.goal, analytics: snapshot.analytics, now: snapshot.now, selectedDay: $selectedDay)
                            consistencyFacts(days: goalDays, active: days.filter { $0.seconds > 0 }.count, goal: snapshot.goal, analytics: snapshot.analytics)
                        }
                    }
                    .transition(.opacity)
                }

                dayDetail(snapshot: snapshot, days: days, goalMet: goalMet)
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

    private func summaryRow(_ summary: FocusAnalytics.RangeSummary, goalMetDays: Int, goal: TimeInterval, scope: GoalScope) -> some View {
        HStack(alignment: .top, spacing: FFSpace.l) {
            FFStat(label: "Total", value: FFFormat.duration(summary.totalSeconds))
            Divider()
            FFStat(label: "Daily average", value: FFFormat.duration(summary.dailyAverageSeconds), caption: "Goal \(FFFormat.duration(goal))")
            Divider()
            FFStat(
                label: "Days goal met",
                value: "\(goalMetDays)/\(summary.dayCount)",
                caption: scope.isFiltered ? "On \(scope.phrase)" : nil,
                valueColor: goalMetDays > 0 ? FFPalette.goal : nil
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

    /// `days` are goal days (own work once configured); `active` counts days with any focus.
    private func consistencyFacts(days: [FocusAnalytics.DayTotal], active: Int, goal: TimeInterval, analytics: FocusAnalytics) -> some View {
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

    private func dayDetail(snapshot: CompanionSnapshot, days: [FocusAnalytics.DayTotal], goalMet: Set<Date>) -> some View {
        let calendar = snapshot.calendar
        // Today has its own tab: by default show the most recent earlier day with focus.
        let day = selectedDay
            ?? days.last(where: { $0.seconds > 0 && !calendar.isDate($0.day, inSameDayAs: snapshot.now) })?.day
            ?? snapshot.today.start
        let interval = snapshot.analytics.dayInterval(containing: day)
        let total = snapshot.analytics.dayTotal(snapshot.samples, on: day)
        let daySessions = sessions
            .filter { $0.type == .focus && $0.actualDuration >= 60 && $0.effectiveEnd > interval.start && $0.startedAt < interval.end }
            .sorted { $0.startedAt > $1.startedAt }
        let title = calendar.isDate(day, inSameDayAs: snapshot.now)
            ? "Today"
            : day.formatted(.dateTime.weekday(.wide).day().month(.wide))
        let subtitle = total.seconds > 0
            ? "\(FFFormat.duration(total.seconds)) · \(total.blocks) block\(total.blocks == 1 ? "" : "s")\(goalMet.contains(interval.start) ? " · goal met" : "")"
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

// MARK: - Daily focus chart

/// Daily focus stacked by project (Work faded via the colour scale), the goal line, and a dot on
/// days the goal was met, where "met" comes from `goalMet` (own work once a project is marked
/// Work) rather than the stacked total.
private struct HistoryFocusChart: View {
    let days: [FocusAnalytics.DayTotal]
    let goal: TimeInterval
    let goalMet: Set<Date>
    let colors: ProjectColorScale
    @Binding var selectedDay: Date?
    var height: CGFloat = 220

    @State private var hoveredDay: Date?
    @State private var reveal = 0.0
    @Environment(\.calendar) private var calendar

    private var yMax: Double {
        let peak = days.map(\.seconds).max() ?? 0
        let hours = max(peak * 1.1, goal * 1.2) / 3600
        return max(1, (hours * 2).rounded(.up) / 2)
    }

    private var yStride: Double { yMax <= 3 ? 1 : (yMax <= 8 ? 2 : 4) }

    private func isMet(_ day: FocusAnalytics.DayTotal) -> Bool {
        goalMet.contains { calendar.isDate($0, inSameDayAs: day.day) }
    }

    var body: some View {
        Chart {
            ForEach(days) { day in
                dayMarks(day)
            }
            RuleMark(y: .value("Goal", goal / 3600))
                .foregroundStyle(Color.secondary.opacity(0.8))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .annotation(position: .trailing, spacing: 4) {
                    Text("Goal \(FFFormat.duration(goal))").ffText(.caption).fixedSize()
                }
        }
        .chartPlotStyle { plot in plot.padding(.trailing, 64) }
        .chartForegroundStyleScale(domain: colors.domain, range: colors.range)
        .chartLegend(.hidden)
        .chartYScale(domain: 0...yMax)
        .chartYAxis {
            AxisMarks(position: .leading, values: .stride(by: yStride)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(FFPalette.gridLine)
                AxisValueLabel {
                    if let hours = value.as(Double.self) {
                        Text(hours == 0 ? "0" : "\(Int(hours))h").ffText(.caption).monospacedDigit()
                    }
                }
            }
        }
        .chartXAxis { xAxis }
        .chartOverlay { proxy in overlay(proxy) }
        .frame(height: height)
        .ffReveal($reveal, trigger: days.map(\.day))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Daily focus over \(days.count) days, \(FFFormat.duration(days.reduce(0) { $0 + $1.seconds })) total, goal met on \(goalMet.count) days.")
    }

    @ChartContentBuilder
    private func dayMarks(_ day: FocusAnalytics.DayTotal) -> some ChartContent {
        let dimmed = (hoveredDay ?? selectedDay).map { !calendar.isDate($0, inSameDayAs: day.day) } ?? false
        let met = isMet(day)
        ForEach(Array(day.byProject.enumerated()), id: \.element.project.id) { index, slice in
            BarMark(
                x: .value("Day", day.day, unit: .day),
                y: .value("Hours", slice.seconds / 3600 * reveal),
                width: .ratio(0.62)
            )
            .foregroundStyle(by: .value("Project", slice.project.name))
            .opacity(dimmed ? 0.4 : 1)
            .annotation(position: .top, spacing: 3) {
                if met && index == day.byProject.count - 1 {
                    Circle().fill(FFPalette.goal).frame(width: 6, height: 6).opacity(reveal).accessibilityHidden(true)
                }
            }
        }
    }

    private var xAxis: some AxisContent {
        let count = days.count
        return AxisMarks(values: .stride(by: .day, count: count <= 7 ? 1 : (count <= 31 ? 7 : 14))) { value in
            AxisValueLabel(centered: true) {
                if let date = value.as(Date.self) {
                    Text(count <= 7
                         ? date.formatted(.dateTime.weekday(.abbreviated))
                         : date.formatted(.dateTime.day().month(.abbreviated)))
                        .ffText(.caption)
                }
            }
        }
    }

    private func overlay(_ proxy: ChartProxy) -> some View {
        GeometryReader { geo in
            let plot = proxy.plotFrame.map { geo[$0] } ?? .zero
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location): hoveredDay = day(at: location, proxy: proxy, plot: plot)
                        case .ended: hoveredDay = nil
                        }
                    }
                    .onTapGesture { location in
                        if let day = day(at: location, proxy: proxy, plot: plot) { selectedDay = day }
                    }
                if let hoveredDay, let total = days.first(where: { calendar.isDate($0.day, inSameDayAs: hoveredDay) }),
                   let x = proxy.position(forX: total.day.addingTimeInterval(43_200)) {
                    let lines = total.byProject.prefix(4).map { "\($0.project.name)  \(FFFormat.duration($0.seconds))" }
                    FFChartTooltip(
                        title: "\(total.day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))) · \(FFFormat.duration(total.seconds))",
                        lines: isMet(total) ? lines + ["Goal met"] : lines
                    )
                    .offset(x: min(max(plot.minX + x - 70, 0), max(0, geo.size.width - 180)), y: plot.minY + 4)
                    .transition(.opacity)
                }
            }
        }
    }

    private func day(at location: CGPoint, proxy: ChartProxy, plot: CGRect) -> Date? {
        guard plot.contains(location), let date: Date = proxy.value(atX: location.x - plot.minX) else { return nil }
        return days.first { calendar.isDate($0.day, inSameDayAs: date) }?.day
    }
}
