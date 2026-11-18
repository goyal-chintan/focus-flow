import SwiftUI
import Charts

// Coach v8 §3.4: the sections of "Your week" (Insights). Read-only while drawing: every number comes
// from `TimerViewModel.yourWeek` and friends (cached, store reads only); answers run in actions.

/// The verdict: one sentence against your own last 4 weeks, and the week's own work.
struct WeekVerdictSection: View {
    let week: YourWeek

    private var color: Color {
        switch week.verdict {
        case .better: FFPalette.goal
        case .worse: FFPalette.atRisk
        case .same, .firstWeek: .secondary
        }
    }

    private var symbol: String {
        switch week.verdict {
        case .better: "arrow.up.right.circle.fill"
        case .worse: "arrow.down.right.circle.fill"
        case .same: "equal.circle.fill"
        case .firstWeek: "sparkles"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: FFSpace.m) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(color)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: FFSpace.xs) {
                Text(week.headline).ffText(.title3)
                Text(week.line).ffText(.callout).monospacedDigit()
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("yourWeek.verdict")
    }
}

/// Six measures, this week against your 4-week average, each with "better" defined for it.
struct WeekTrendStrip: View {
    let trends: [WeekTrend]

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: FFSpace.m, alignment: .top), count: 3), spacing: FFSpace.m) {
            ForEach(trends) { trend in tile(trend) }
        }
        .accessibilityIdentifier("yourWeek.trends")
    }

    private func tile(_ trend: WeekTrend) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(trend.title).ffText(.caption)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(trend.value).ffNumber(.title3)
                if let delta = trend.delta, trend.direction != .unknown {
                    Label(delta, systemImage: arrow(trend.direction))
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(color(trend.direction))
                        .monospacedDigit()
                }
            }
            Text(trend.baseline ?? "No baseline yet").ffText(.caption).monospacedDigit()
        }
        .padding(FFSpace.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: FFRadius.control, style: .continuous).fill(FFPalette.track.opacity(0.6)))
        .accessibilityElement(children: .combine)
    }

    private func arrow(_ d: WeekTrend.Direction) -> String {
        switch d {
        case .better: "arrow.up"
        case .worse: "arrow.down"
        case .same, .unknown: "equal"
        }
    }

    private func color(_ d: WeekTrend.Direction) -> Color {
        switch d {
        case .better: FFPalette.goal
        case .worse: FFPalette.atRisk
        case .same, .unknown: .secondary
        }
    }
}

/// The 7 days: plan × outcome, with the day type. Selecting a day shows its timeline.
struct WeekDaysStrip: View {
    let days: [DayEntry]
    @Binding var selected: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: FFSpace.s) {
            HStack(spacing: FFSpace.s) {
                ForEach(days) { day in
                    Button { selected = selected == day.day ? nil : day.day } label: { chip(day) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(Self.weekday(day.day)): \(day.type.title), \(day.verdict.title), \(FFFormat.duration(day.ownMinutes * 60)) own work")
                }
            }
            HStack(spacing: FFSpace.m) {
                ForEach([DayVerdict.plannedDone, .unplannedDid, .plannedMissed, .unplannedLost], id: \.self) { verdict in
                    Label(verdict.title, systemImage: Self.symbol(verdict))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityIdentifier("yourWeek.days")
    }

    private func chip(_ day: DayEntry) -> some View {
        let isSelected = selected == day.day
        return VStack(spacing: 4) {
            Text(Self.weekday(day.day)).ffText(.caption)
            Image(systemName: Self.symbol(day.verdict))
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Self.color(day.verdict))
            Text(FFFormat.compactDuration(day.ownMinutes * 60)).ffText(.caption).monospacedDigit()
            Text(Self.typeMark(day.type)).font(.system(size: 9.5, weight: .semibold)).foregroundStyle(.secondary)
        }
        .padding(.vertical, FFSpace.s)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: FFRadius.control, style: .continuous)
            .fill(isSelected ? FFPalette.rowSelected : FFPalette.track.opacity(0.5)))
        .contentShape(Rectangle())
    }

    static func weekday(_ date: Date) -> String {
        ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][Calendar.current.component(.weekday, from: date) - 1]
    }

    static func typeMark(_ type: DayType) -> String {
        switch type {
        case .workday: " "
        case .leave: "LEAVE"
        case .weekend: "WEEKEND"
        case .holiday: "HOLIDAY"
        case .sick: "SICK"
        }
    }

    static func symbol(_ verdict: DayVerdict) -> String {
        switch verdict {
        case .plannedDone: "circle.fill"
        case .unplannedDid: "circle.lefthalf.filled"
        case .plannedMissed: "circle"
        case .unplannedLost: "xmark.circle"
        case .rest: "moon"
        case .open: "circle.dotted"
        }
    }

    static func color(_ verdict: DayVerdict) -> Color {
        switch verdict {
        case .plannedDone, .unplannedDid: FFPalette.goal
        case .plannedMissed, .unplannedLost: FFPalette.atRisk
        case .rest, .open: .secondary
        }
    }
}

/// One day, hour by hour: blocks, calls, away, pulls and other laptop time, plus a day-type fix.
struct DayTimelineView: View {
    let entry: DayEntry
    let timeline: DayTimeline
    let setType: (DayType) -> Void

    private static let kinds: [(String, Color)] = [
        ("Own work", FFPalette.accent), ("Work blocks", Color.blue.opacity(0.55)), ("Calls", Color.purple.opacity(0.7)),
        ("Pulls", FFPalette.atRisk), ("Other", Color.gray.opacity(0.45)), ("Away", Color.gray.opacity(0.2)),
    ]

    private struct Segment: Identifiable {
        let hour: Int
        let kind: String
        let minutes: Double
        var id: String { "\(hour)-\(kind)" }
    }

    private var segments: [Segment] {
        let range = timeline.activeRange ?? 8...22
        return timeline.hours.filter { range.contains($0.hour) }.flatMap { h in
            [("Own work", h.own), ("Work blocks", h.work), ("Calls", h.call), ("Pulls", h.pull), ("Other", h.other), ("Away", h.away)]
                .filter { $0.1 > 0 }
                .map { Segment(hour: h.hour, kind: $0.0, minutes: $0.1) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: FFSpace.s) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Self.title(entry.day)).ffText(.headline)
                    Text(summary).ffText(.caption).monospacedDigit()
                }
                Spacer()
                Menu {
                    ForEach(DayType.allCases, id: \.self) { type in
                        Button(type.title) { setType(type) }
                    }
                } label: {
                    Text("\(entry.type.title)\(entry.classification.source == .inferred ? " (my guess)" : "")")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help(entry.classification.reason)
                .accessibilityIdentifier("yourWeek.dayType")
            }
            if segments.isEmpty {
                FFEmptyState(systemImage: "clock", message: "Nothing recorded this day")
            } else {
                Chart(segments) { segment in
                    BarMark(x: .value("Hour", segment.hour), y: .value("Minutes", segment.minutes), width: .ratio(0.8))
                        .foregroundStyle(by: .value("Kind", segment.kind))
                }
                .chartForegroundStyleScale(domain: Self.kinds.map(\.0), range: Self.kinds.map(\.1))
                .chartYScale(domain: 0...60)
                .chartYAxis { AxisMarks(values: [0, 30, 60]) { AxisGridLine(); AxisValueLabel() } }
                .chartXAxis { AxisMarks(values: .stride(by: 2)) { value in AxisValueLabel { Text(FFFormat.hourLabel(value.as(Int.self) ?? 0)) } } }
                .chartLegend(position: .bottom, alignment: .leading)
                .frame(height: 150)
                if !timeline.hasRollup {
                    Text("Blocks only: this day is older than the hourly record of calls, away time and pulls.").ffText(.caption)
                }
            }
        }
        .accessibilityIdentifier("yourWeek.timeline")
    }

    private var summary: String {
        var parts = ["\(FFFormat.duration(entry.ownMinutes * 60)) own work of \(DayTargets.label(entry.targetMinutes))", entry.verdict.title.lowercased()]
        if timeline.hasRollup {
            if timeline.callMinutes >= 1 { parts.append("\(FFFormat.duration(timeline.callMinutes * 60)) in calls") }
            if timeline.pullMinutes >= 1 { parts.append("\(FFFormat.duration(timeline.pullMinutes * 60)) on pulls") }
            if timeline.awayMinutes >= 1 { parts.append("\(FFFormat.duration(timeline.awayMinutes * 60)) away") }
        }
        return parts.joined(separator: " · ")
    }

    static func title(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "EEEE d MMM"
        return f.string(from: date)
    }
}

/// "Do this next": evidence, impact, one Apply, and "Not now".
struct LifeRecommendationCard: View {
    let index: Int
    let rec: LifeRecommendation
    let apply: () -> Void
    let dismiss: () -> Void
    @State private var applied = false

    var body: some View {
        HStack(alignment: .top, spacing: FFSpace.m) {
            Text("\(index)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(FFPalette.accent)
                .frame(width: 24, height: 24)
                .background(Circle().fill(FFPalette.accent.opacity(0.14)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(rec.title).ffText(.headline)
                Text(rec.evidence).ffText(.body).fixedSize(horizontal: false, vertical: true)
                Text(rec.impact).ffText(.caption).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: FFSpace.s) {
                    if applied {
                        Label("Done. I'll tell you next week whether it worked.", systemImage: "checkmark.circle.fill")
                            .ffText(.callout)
                            .foregroundStyle(FFPalette.goal)
                    } else {
                        Button(rec.actionTitle) { applied = true; apply() }
                            .buttonStyle(.glassProminent)
                            .accessibilityIdentifier("yourWeek.apply.\(rec.kind.rawValue)")
                        Button("Not now") { dismiss() }
                            .buttonStyle(.glass)
                    }
                }
                .controlSize(.regular)
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(FFSpace.m)
        .background(RoundedRectangle(cornerRadius: FFRadius.section, style: .continuous).fill(FFPalette.track.opacity(0.5)))
    }
}

/// "Is the coach helping?": does a prompt lead to a start, does the back-from-break panel bring
/// you back, and what became of each recommendation. The full report sits behind "Details".
struct CoachHelpingSection: View {
    let helping: TimerViewModel.CoachHelping
    @State private var showDetails = false

    var body: some View {
        FFSection("Is the coach helping?", subtitle: "Measured against the moments it stayed quiet, so a good week alone doesn't count as its win.") {
            VStack(alignment: .leading, spacing: FFSpace.m) {
                line(symbol: "bell.badge", title: "Start prompts", text: promptText)
                line(symbol: "cup.and.saucer", title: "Back from breaks", text: returnText)
                if helping.outcomes.isEmpty {
                    line(symbol: "list.bullet.clipboard", title: "Recommendations", text: "Apply one above; a week later this says whether it worked.")
                } else {
                    ForEach(Array(helping.outcomes.enumerated()), id: \.offset) { _, item in
                        line(symbol: item.outcome.symbol, title: item.record.title, text: outcomeText(item.outcome, record: item.record))
                    }
                }
                DisclosureGroup(isExpanded: $showDetails) {
                    CoachPerformanceView().padding(.top, FFSpace.s)
                } label: {
                    Text("Details: prompt → start, what stops you, the coach's log").ffText(.callout)
                }
                .accessibilityIdentifier("yourWeek.coachDetails")
            }
        }
        .accessibilityIdentifier("yourWeek.coachHelping")
    }

    private var promptText: String {
        guard let lift = helping.promptLift else { return "Not enough quiet moments to compare yet (it needs about 20 decisions)." }
        let delta = Int(((lift.withPrompt - lift.withoutPrompt) * 100).rounded())
        return "You start \(FFFormat.percent(lift.withPrompt)) of the time after a prompt, \(FFFormat.percent(lift.withoutPrompt)) without (\(delta >= 0 ? "+" : "")\(delta) pts, \(lift.decisions) moments)."
    }

    private var returnText: String {
        guard let r = helping.returnLift else { return "Still testing: the back-from-break panel needs about 10 breaks with and without it." }
        let delta = Int((r.lift * 100).rounded())
        return "Back within 10 min \(FFFormat.percent(r.treatedRate)) with the panel, \(FFFormat.percent(r.controlRate)) without (\(delta >= 0 ? "+" : "")\(delta) pts)."
    }

    private func outcomeText(_ outcome: LifeRecOutcome, record: LifeRecRecord) -> String {
        switch outcome {
        case .worked(let change): "Worked: \(change)."
        case .didnt(let change): "No change yet: \(change)."
        case .tooEarly: "Applied \(Self.dayLabel(record.appliedAt)). Judged after a week."
        case .applied: "Applied \(Self.dayLabel(record.appliedAt))."
        case .notTried: "Shown \(Self.dayLabel(record.firstShownAt)), not tried."
        }
    }

    static func dayLabel(_ date: Date?) -> String {
        guard let date else { return "" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "d MMM"
        return f.string(from: date)
    }

    private func line(symbol: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).ffText(.headline)
                Text(text).ffText(.body).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
