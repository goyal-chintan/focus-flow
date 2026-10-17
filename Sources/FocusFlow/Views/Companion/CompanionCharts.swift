import SwiftUI
import Charts

// Swift Charts used by the companion screens. Each chart owns its hover state so hovering never
// re-renders the whole page, grows in from its baseline (FFReveal), and shows exact values on hover.

// MARK: - Daily focus (History, Projects)

struct DailyFocusChart: View {
    let days: [FocusAnalytics.DayTotal]
    let goal: TimeInterval
    let colors: ProjectColorScale
    /// Single-series colour (Projects detail). When set, bars are not split by project.
    var singleColor: Color? = nil
    /// The goal line and goal-met dots describe total daily focus; off for per-project charts.
    var showGoal: Bool = true
    @Binding var selectedDay: Date?
    var height: CGFloat = 220

    @State private var hoveredDay: Date?
    @State private var reveal = 0.0
    @Environment(\.calendar) private var calendar

    private var yMax: Double {
        let peak = days.map(\.seconds).max() ?? 0
        let hours = max(peak * 1.1, showGoal ? goal * 1.2 : 0) / 3600
        return max(1, (hours * 2).rounded(.up) / 2)
    }

    private var yStride: Double {
        yMax <= 3 ? 1 : (yMax <= 8 ? 2 : 4)
    }

    var body: some View {
        Chart {
            ForEach(days) { day in
                dayMarks(day)
            }
            if showGoal {
            RuleMark(y: .value("Goal", goal / 3600))
                .foregroundStyle(Color.secondary.opacity(0.8))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .annotation(position: .trailing, spacing: 4) {
                    Text("Goal \(FFFormat.duration(goal))").ffText(.caption).fixedSize()
                }
            }
        }
        .chartPlotStyle { plot in plot.padding(.trailing, showGoal ? 64 : 0) }
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
        .accessibilityLabel(accessibilitySummary)
    }

    @ChartContentBuilder
    private func dayMarks(_ day: FocusAnalytics.DayTotal) -> some ChartContent {
        let dimmed = (hoveredDay ?? selectedDay).map { !calendar.isDate($0, inSameDayAs: day.day) } ?? false
        let opacity = dimmed ? 0.4 : 1.0
        let met = day.seconds >= goal
        if let singleColor {
            BarMark(
                x: .value("Day", day.day, unit: .day),
                y: .value("Hours", day.seconds / 3600 * reveal),
                width: .ratio(0.62)
            )
            .foregroundStyle(singleColor)
            .cornerRadius(3)
            .opacity(opacity)
            .annotation(position: .top, spacing: 3) { goalDot(met) }
        } else {
            ForEach(Array(day.byProject.enumerated()), id: \.element.project.id) { index, slice in
                BarMark(
                    x: .value("Day", day.day, unit: .day),
                    y: .value("Hours", slice.seconds / 3600 * reveal),
                    width: .ratio(0.62)
                )
                .foregroundStyle(by: .value("Project", slice.project.name))
                .opacity(opacity)
                .annotation(position: .top, spacing: 3) {
                    if index == day.byProject.count - 1 { goalDot(met) }
                }
            }
        }
    }

    @ViewBuilder
    private func goalDot(_ met: Bool) -> some View {
        if met && showGoal {
            Circle()
                .fill(FFPalette.goal)
                .frame(width: 6, height: 6)
                .opacity(reveal)
                .accessibilityHidden(true)
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
                        case .active(let location):
                            hoveredDay = day(at: location, proxy: proxy, plot: plot)
                        case .ended:
                            hoveredDay = nil
                        }
                    }
                    .onTapGesture { location in
                        guard let day = day(at: location, proxy: proxy, plot: plot) else { return }
                        selectedDay = day
                    }

                if let hoveredDay, let total = days.first(where: { calendar.isDate($0.day, inSameDayAs: hoveredDay) }),
                   let x = proxy.position(forX: total.day.addingTimeInterval(43_200)) {
                    let lines = total.byProject.prefix(4).map { "\($0.project.name)  \(FFFormat.duration($0.seconds))" }
                    FFChartTooltip(
                        title: "\(total.day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))) · \(FFFormat.duration(total.seconds))",
                        lines: showGoal && total.seconds >= goal ? lines + ["Goal met"] : lines
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

    private var accessibilitySummary: String {
        let met = days.filter { $0.seconds >= goal }.count
        let total = days.reduce(0) { $0 + $1.seconds }
        return "Daily focus over \(days.count) days, \(FFFormat.duration(total)) total, goal met on \(met) days."
    }
}

// MARK: - Consistency calendar heatmap (History)

struct ConsistencyHeatmap: View {
    let days: [FocusAnalytics.DayTotal]
    let goal: TimeInterval
    let analytics: FocusAnalytics
    let now: Date
    @Binding var selectedDay: Date?

    @State private var hovered: Date?
    @State private var reveal = 0.0
    private let cellSize: CGFloat = 16
    private let gap: CGFloat = 4

    private struct Cell: Identifiable {
        let day: Date
        /// Week column key, e.g. "W0", ordered oldest → newest.
        let column: String
        let weekStart: Date
        let weekday: String
        let level: Int
        let seconds: TimeInterval
        var id: Date { day }
    }

    private var weekStarts: [Date] {
        Array(Set(days.map { analytics.weekInterval(containing: $0.day).start })).sorted()
    }

    private var cells: [Cell] {
        let today = analytics.calendar.startOfDay(for: now)
        let weeks = weekStarts
        return days.filter { $0.day <= today }.map { day in
            let weekStart = analytics.weekInterval(containing: day.day).start
            return Cell(
                day: day.day,
                column: "W\(weeks.firstIndex(of: weekStart) ?? 0)",
                weekStart: weekStart,
                weekday: FFFormat.weekdayShort[analytics.mondayFirstWeekdayIndex(of: day.day)],
                level: level(for: day.seconds),
                seconds: day.seconds
            )
        }
    }

    private var columns: [String] { weekStarts.indices.map { "W\($0)" } }

    /// 0 = none, 1–3 = thirds of the goal, 4 = goal met (drawn in green).
    private func level(for seconds: TimeInterval) -> Int {
        guard seconds > 0 else { return 0 }
        if seconds >= goal { return 4 }
        return min(3, Int(seconds / (goal / 3)) + 1)
    }

    static func color(for level: Int) -> Color {
        level >= 4 ? FFPalette.goal : FFPalette.heat(level)
    }

    var body: some View {
        let cells = self.cells
        let weeks = weekStarts
        let pitch = cellSize + gap
        return HStack(alignment: .top, spacing: FFSpace.s) {
            VStack(alignment: .trailing, spacing: 0) {
                ForEach(FFFormat.weekdayShort.indices, id: \.self) { index in
                    Text(index % 2 == 0 ? FFFormat.weekdayShort[index] : "")
                        .ffText(.caption)
                        .frame(height: pitch)
                }
            }
            VStack(alignment: .leading, spacing: FFSpace.xs) {
                Chart(cells) { cell in
                    RectangleMark(
                        x: .value("Week", cell.column),
                        y: .value("Day", cell.weekday),
                        width: .fixed(cellSize),
                        height: .fixed(cellSize)
                    )
                    .foregroundStyle(Self.color(for: cell.level))
                    .cornerRadius(3.5)
                    .opacity(isHighlighted(cell) ? reveal : 0.35 * reveal)
                }
                .chartXScale(domain: columns)
                .chartYScale(domain: FFFormat.weekdayShort)
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartPlotStyle { $0.frame(width: CGFloat(max(weeks.count, 1)) * pitch, height: 7 * pitch) }
                .chartOverlay { proxy in overlay(proxy, cells: cells) }
                .frame(width: CGFloat(max(weeks.count, 1)) * pitch, height: 7 * pitch)

                // Month labels under the first week of each month.
                HStack(spacing: 0) {
                    ForEach(weeks.indices, id: \.self) { index in
                        Text(monthLabel(weeks: weeks, index: index))
                            .ffText(.caption)
                            .fixedSize()
                            .frame(width: pitch, alignment: .leading)
                    }
                }
            }
        }
        .ffReveal($reveal, trigger: days.map(\.day))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Consistency calendar, goal met on \(cells.filter { $0.level == 4 }.count) of \(cells.count) days")
    }

    private func monthLabel(weeks: [Date], index: Int) -> String {
        let calendar = analytics.calendar
        let month = calendar.component(.month, from: weeks[index].addingTimeInterval(6 * 86_400))
        if index == 0 { return weeks[index].addingTimeInterval(6 * 86_400).formatted(.dateTime.month(.abbreviated)) }
        let previous = calendar.component(.month, from: weeks[index - 1].addingTimeInterval(6 * 86_400))
        guard month != previous, index >= 2 || weeks.count < 6 else { return "" }
        return weeks[index].addingTimeInterval(6 * 86_400).formatted(.dateTime.month(.abbreviated))
    }

    static var legend: some View {
        HStack(spacing: FFSpace.xs) {
            Text("Less").ffText(.caption)
            ForEach(0..<4) { level in
                RoundedRectangle(cornerRadius: 2.5).fill(color(for: level)).frame(width: 10, height: 10)
            }
            Text("More").ffText(.caption)
        }
        .accessibilityHidden(true)
    }

    private func isHighlighted(_ cell: Cell) -> Bool {
        guard let focus = hovered ?? selectedDay else { return true }
        return analytics.calendar.isDate(focus, inSameDayAs: cell.day)
    }

    private func overlay(_ proxy: ChartProxy, cells: [Cell]) -> some View {
        GeometryReader { geo in
            let plot = proxy.plotFrame.map { geo[$0] } ?? .zero
            ZStack(alignment: .topLeading) {
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location): hovered = cellDay(at: location, proxy: proxy, plot: plot, cells: cells)
                        case .ended: hovered = nil
                        }
                    }
                    .onTapGesture { location in
                        if let day = cellDay(at: location, proxy: proxy, plot: plot, cells: cells) { selectedDay = day }
                    }
                if let hovered, let cell = cells.first(where: { $0.day == hovered }),
                   let x = proxy.position(forX: cell.column), let y = proxy.position(forY: cell.weekday) {
                    FFChartTooltip(
                        title: cell.day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)),
                        lines: [cell.seconds > 0 ? FFFormat.duration(cell.seconds) + (cell.level == 4 ? " · goal met" : "") : "No focus"]
                    )
                    .offset(x: plot.minX + x + 12, y: plot.minY + y - 10)
                }
            }
        }
    }

    private func cellDay(at location: CGPoint, proxy: ChartProxy, plot: CGRect, cells: [Cell]) -> Date? {
        let local = CGPoint(x: location.x - plot.minX, y: location.y - plot.minY)
        guard let column: String = proxy.value(atX: local.x), let weekday: String = proxy.value(atY: local.y) else { return nil }
        return cells.first { $0.column == column && $0.weekday == weekday }?.day
    }
}

// MARK: - Hour of week (Insights)

struct HourOfWeekHeatmap: View {
    let matrix: FocusAnalytics.HourOfWeekMatrix
    let windows: [FocusAnalytics.FocusWindow]

    @State private var hovered: Bucket?
    @State private var reveal = 0.0

    private struct Bucket: Identifiable, Hashable {
        let weekday: Int
        let hour: Int
        let minutes: Double
        let startRate: Double
        var id: Int { weekday * 24 + hour }
        var dayLabel: String { FFFormat.weekdayShort[weekday] }
    }

    private var buckets: [Bucket] {
        (0..<7).flatMap { day in
            (0..<24).map { hour in
                Bucket(
                    weekday: day,
                    hour: hour,
                    minutes: matrix.averageMinutes(weekday: day, hour: hour),
                    startRate: matrix.startRate(weekday: day, hour: hour)
                )
            }
        }
    }

    private var peak: Double { max(1, matrix.maxAverageMinutes) }

    static func hourKey(_ hour: Int) -> String { String(format: "%02d", hour) }

    private var windowHours: [Int] {
        Array(Set(windows.flatMap { window in (0..<window.hourCount).map { (window.startHour + $0) % 24 } })).sorted()
    }

    private func level(_ minutes: Double) -> Int {
        guard minutes >= 0.5 else { return 0 }
        return min(4, Int(minutes / peak * 4) + 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: FFSpace.m) {
            HStack(alignment: .top, spacing: FFSpace.s) {
                VStack(alignment: .trailing, spacing: 0) {
                    ForEach(FFFormat.weekdayShort, id: \.self) { day in
                        Text(day).ffText(.caption).frame(height: 24)
                    }
                }
            Chart {
                ForEach(windowHours, id: \.self) { hour in
                    RectangleMark(x: .value("Hour", Self.hourKey(hour)), width: .ratio(1))
                        .foregroundStyle(FFPalette.accent.opacity(0.08))
                }
                ForEach(buckets) { bucket in
                    RectangleMark(
                        x: .value("Hour", Self.hourKey(bucket.hour)),
                        y: .value("Day", bucket.dayLabel),
                        width: .ratio(0.86),
                        height: .fixed(17)
                    )
                    .foregroundStyle(FFPalette.heat(level(bucket.minutes)))
                    .cornerRadius(3)
                    .opacity(hovered == nil || hovered == bucket ? reveal : 0.45 * reveal)
                }
            }
            .chartXScale(domain: (0..<24).map(Self.hourKey))
            .chartYScale(domain: FFFormat.weekdayShort)
            .chartXAxis {
                AxisMarks(values: stride(from: 0, to: 24, by: 3).map(Self.hourKey)) { _ in
                    AxisValueLabel().font(FFTextStyle.caption.font)
                }
            }
            .chartYAxis(.hidden)
            .chartPlotStyle { $0.frame(height: 7 * 24) }
            .chartOverlay { proxy in overlay(proxy) }
            .frame(height: 7 * 24 + 22)
            }
            .ffReveal($reveal, trigger: matrix)

            HStack(spacing: FFSpace.xs) {
                Text("Avg per week").ffText(.caption)
                Text("0").ffText(.caption).monospacedDigit()
                ForEach(0..<5) { level in
                    RoundedRectangle(cornerRadius: 2.5).fill(FFPalette.heat(level)).frame(width: 10, height: 10)
                }
                Text(FFFormat.duration(matrix.maxAverageMinutes * 60)).ffText(.caption).monospacedDigit()
                if !windows.isEmpty {
                    Spacer().frame(width: FFSpace.m)
                    FFLegendItem(color: FFPalette.accent.opacity(0.18), label: "Best windows")
                }
            }
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private func overlay(_ proxy: ChartProxy) -> some View {
        GeometryReader { geo in
            let plot = proxy.plotFrame.map { geo[$0] } ?? .zero
            ZStack(alignment: .topLeading) {
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            let local = CGPoint(x: location.x - plot.minX, y: location.y - plot.minY)
                            guard plot.contains(location),
                                  let hourKey: String = proxy.value(atX: local.x),
                                  let hourValue = Int(hourKey),
                                  let dayLabel: String = proxy.value(atY: local.y),
                                  let day = FFFormat.weekdayShort.firstIndex(of: dayLabel) else {
                                hovered = nil
                                return
                            }
                            let hour = min(23, max(0, hourValue))
                            hovered = buckets[day * 24 + hour]
                        case .ended:
                            hovered = nil
                        }
                    }
                if let hovered, let x = proxy.position(forX: Self.hourKey(hovered.hour)), let y = proxy.position(forY: hovered.dayLabel) {
                    let weeks = matrix.weeksObserved
                    let starts = Int((hovered.startRate * Double(weeks)).rounded())
                    FFChartTooltip(
                        title: "\(hovered.dayLabel) \(FFFormat.hourLabel(hovered.hour))–\(FFFormat.hourLabel(hovered.hour + 1))",
                        lines: [
                            "\(FFFormat.duration(hovered.minutes * 60)) focus per week",
                            "Started a block \(starts) of \(weeks) week\(weeks == 1 ? "" : "s")",
                        ]
                    )
                    .offset(x: min(plot.minX + x + 6, max(0, geo.size.width - 190)), y: max(0, plot.minY + y - 20))
                }
            }
        }
    }

    private var accessibilitySummary: String {
        if windows.isEmpty { return "Hour of week focus heatmap, not enough data yet" }
        return "Hour of week focus heatmap. Best windows " + FocusAnalytics.windowsSummary(windows)
    }
}

// MARK: - Today timeline

struct TodayTimelineChart: View {
    struct Block: Identifiable {
        let id: UUID
        let start: Date
        let end: Date
        let project: String
        let title: String
        let seconds: TimeInterval
    }

    let day: DateInterval
    let blocks: [Block]
    let windows: [FocusAnalytics.FocusWindow]
    let colors: ProjectColorScale
    let now: Date

    @State private var hovered: Block.ID?
    @State private var reveal = 0.0

    var body: some View {
        Chart {
            RectangleMark(
                xStart: .value("Start", day.start),
                xEnd: .value("End", day.end),
                y: .value("Lane", "Focus"),
                height: .fixed(28)
            )
            .foregroundStyle(FFPalette.track)
            .cornerRadius(6)

            // Full plot height, so a focus block sitting in the window does not hide the shading.
            ForEach(windowRanges, id: \.start) { range in
                RectangleMark(
                    xStart: .value("Start", range.start),
                    xEnd: .value("End", range.end),
                    y: .value("Lane", "Focus"),
                    height: .ratio(1)
                )
                .foregroundStyle(FFPalette.accent.opacity(0.10))
            }

            ForEach(blocks) { block in
                RectangleMark(
                    xStart: .value("Start", block.start),
                    xEnd: .value("End", block.start.addingTimeInterval(max(block.end.timeIntervalSince(block.start), 240) * reveal)),
                    y: .value("Lane", "Focus"),
                    height: .fixed(28)
                )
                .foregroundStyle(by: .value("Project", block.project))
                .cornerRadius(4)
                .opacity(hovered == nil || hovered == block.id ? 1 : 0.45)
            }

            if day.contains(now) {
                RuleMark(x: .value("Now", now))
                    .foregroundStyle(FFPalette.atRisk)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                    .annotation(position: .top, spacing: 2) {
                        Text("Now").font(FFTextStyle.caption.font).foregroundStyle(FFPalette.atRisk)
                    }
            }
        }
        .chartForegroundStyleScale(domain: colors.domain, range: colors.range)
        .chartLegend(.hidden)
        .chartXScale(domain: day.start...day.end)
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 3)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(FFPalette.gridLine)
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(FFFormat.hour(date)).ffText(.caption).monospacedDigit()
                    }
                }
            }
        }
        .chartOverlay { proxy in overlay(proxy) }
        .frame(height: 76)
        .ffReveal($reveal, trigger: blocks.map(\.id))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private struct Span { let start: Date; let end: Date }

    private var windowRanges: [Span] {
        let calendar = Calendar.current
        return windows.flatMap { window -> [Span] in
            guard let start = calendar.date(bySettingHour: window.startHour, minute: 0, second: 0, of: day.start),
                  let end = calendar.date(byAdding: .hour, value: window.hourCount, to: start) else { return [] }
            var ranges = [Span(start: start, end: min(end, day.end))]
            if end > day.end {
                // Wrapped window: the part after midnight belongs to the start of this day.
                ranges.append(Span(start: day.start, end: day.start.addingTimeInterval(end.timeIntervalSince(day.end))))
            }
            return ranges
        }
    }

    private func overlay(_ proxy: ChartProxy) -> some View {
        GeometryReader { geo in
            let plot = proxy.plotFrame.map { geo[$0] } ?? .zero
            ZStack(alignment: .topLeading) {
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            guard let date: Date = proxy.value(atX: location.x - plot.minX) else { hovered = nil; return }
                            hovered = blocks.first { $0.start <= date && date <= $0.end }?.id
                        case .ended:
                            hovered = nil
                        }
                    }
                if let hovered, let block = blocks.first(where: { $0.id == hovered }), let x = proxy.position(forX: block.start) {
                    FFChartTooltip(
                        title: block.title,
                        lines: ["\(FFFormat.clock(block.start))–\(FFFormat.clock(block.end)) · \(FFFormat.duration(block.seconds))"]
                    )
                    .offset(x: min(max(0, plot.minX + x), max(0, geo.size.width - 200)), y: -42)
                }
            }
        }
    }

    private var accessibilitySummary: String {
        if blocks.isEmpty { return "Today's timeline, no focus blocks yet" }
        let time = Date.FormatStyle.dateTime.hour().minute()
        return "Today's timeline: " + blocks.map { "\($0.project) \($0.start.formatted(time)) for \(FFFormat.duration($0.seconds))" }.joined(separator: ", ")
    }
}
