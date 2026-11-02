import SwiftUI
import SwiftData
import Charts

// Shared pieces for goals and the honest breakdown (docs/plans/2026-10-28-priorities-goals-design.md §3.6).

extension GoalPaceStatus {
    var color: Color {
        switch self {
        case .done, .ahead: FFPalette.goal
        case .onTrack: FFPalette.accent
        case .behind: FFPalette.atRisk
        case .overdue: FFPalette.destructive
        case .notStarted: .secondary
        }
    }

    var symbol: String {
        switch self {
        case .done: "checkmark.circle.fill"
        case .ahead: "hare.fill"
        case .onTrack: "checkmark.seal.fill"
        case .behind: "exclamationmark.triangle.fill"
        case .overdue: "clock.badge.exclamationmark.fill"
        case .notStarted: "hourglass"
        }
    }
}

struct PaceStatusPill: View {
    let status: GoalPaceStatus

    var body: some View {
        Label(status.title, systemImage: status.symbol)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(status.color)
            .padding(.horizontal, 8)
            .frame(height: 20)
            .background(Capsule().fill(status.color.opacity(0.14)))
            .accessibilityLabel("Status: \(status.title)")
    }
}

/// Progress with a tick where you should be by now.
struct PaceBar: View {
    let fraction: Double
    let expected: Double
    var color: Color = FFPalette.accent
    var height: CGFloat = 8
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(FFPalette.track)
                Capsule()
                    .fill(color.gradient)
                    .frame(width: max(height, width * min(1, max(0, fraction))))
                    .opacity(fraction > 0 ? 1 : 0)
                if expected > 0 && expected < 1 {
                    Rectangle()
                        .fill(Color.primary.opacity(0.55))
                        .frame(width: 2, height: height + 6)
                        .offset(x: width * expected - 1)
                        .help("Where you should be today")
                }
            }
        }
        .frame(height: height)
        .animation(FFAnimation.gated(FFAnimation.chart, reduceMotion: reduceMotion), value: fraction)
        .accessibilityElement()
        .accessibilityLabel("\(Int((fraction * 100).rounded())) percent done, \(Int((expected * 100).rounded())) percent expected by now")
    }
}

// MARK: - Goal card

/// A goal, read top to bottom (Goals clarity 2026-11-02): what it is and when it's due, one
/// sentence on where you stand, then each number with +1. The overall bar shows only when there
/// are several numbers (with one, it repeats the number's own bar). A goal with nothing to count
/// says so and offers the two ways forward instead of a 0% bar.
struct GoalCard: View {
    let goal: ProjectGoal
    let project: Project?
    let now: Date
    var compact: Bool = false
    var onEdit: (() -> Void)?
    /// Pick reminders (the project's tasks) to count toward this goal; nil when its project has none.
    var onPickReminders: (() -> Void)?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showChart = false

    var body: some View {
        let summary = GoalDataBuilder.summary(goal, now: now)
        let tint = FFPalette.project(project?.color)
        let results = goal.sortedKeyResults
        VStack(alignment: .leading, spacing: FFSpace.m) {
            header(summary, tint: tint, hasMeasures: !results.isEmpty)
            if results.isEmpty {
                GoalFirstStep(onEdit: onEdit, onPickReminders: onPickReminders)
            } else {
                Text(GoalPlainLanguage.verdict(
                    status: summary.status,
                    measures: Array(zip(results.map(\.title), summary.keyResults)),
                    start: goal.startDate,
                    deadline: goal.deadline
                ))
                .ffText(.body)
                .fixedSize(horizontal: false, vertical: true)
                if results.count > 1 {
                    overallBar(summary)
                }
                VStack(spacing: 14) {
                    ForEach(Array(zip(results, summary.keyResults)), id: \.0.id) { pair in
                        KeyResultRow(keyResult: pair.0, pace: pair.1, compact: compact)
                    }
                }
                if !compact {
                    HStack(alignment: .top) {
                        chartToggle(summary)
                        if let onPickReminders {
                            Button(action: onPickReminders) {
                                Label("Add from Reminders…", systemImage: "checklist")
                            }
                            .buttonStyle(.borderless)
                            .help("Pick reminders that count toward this goal")
                        }
                    }
                }
            }
        }
        .padding(FFSpace.l)
        .ffSurface()
    }

    private func overallBar(_ summary: GoalPacing.GoalSummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            PaceBar(fraction: summary.fraction, expected: summary.expectedFraction, color: summary.status.color, height: 8)
            HStack {
                Text("Overall \(Int((summary.fraction * 100).rounded()))% done").ffText(.caption).monospacedDigit()
                Spacer()
                Text("Today's mark │ \(Int((summary.expectedFraction * 100).rounded()))%")
                    .ffText(.caption)
                    .monospacedDigit()
                    .help("The tick on the bar is where steady progress would put you today")
            }
        }
    }

    /// The whole row opens and closes the chart, not only its chevron.
    private func chartToggle(_ summary: GoalPacing.GoalSummary) -> some View {
        VStack(alignment: .leading, spacing: FFSpace.s) {
            Button {
                withAnimation(FFAnimation.gated(FFAnimation.control, reduceMotion: reduceMotion)) { showChart.toggle() }
            } label: {
                HStack(spacing: FFSpace.s) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .rotationEffect(.degrees(showChart ? 90 : 0))
                        .accessibilityHidden(true)
                    Text(showChart ? "Hide progress over time" : "Show progress over time").ffText(.callout)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.secondary)
                .frame(minHeight: 30)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if showChart {
                GoalPaceChart(goal: goal, now: now, tint: summary.status.color)
                    .frame(height: 150)
                    .transition(.opacity)
                Text("Solid line: what you've done. Dashed: a steady pace from start to deadline.").ffText(.caption)
            }
        }
    }

    private func header(_ summary: GoalPacing.GoalSummary, tint: Color, hasMeasures: Bool) -> some View {
        HStack(alignment: .top, spacing: FFSpace.m) {
            Image(systemName: goal.isBossFight ? "star.fill" : "scope")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(Circle().fill(tint.opacity(0.15)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: FFSpace.s) {
                    Text(goal.title).ffText(.headline).lineLimit(2)
                    if goal.isBossFight {
                        Label("Main goal", systemImage: "star.fill")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(tint)
                            .padding(.horizontal, 6)
                            .frame(height: 18)
                            .background(Capsule().fill(tint.opacity(0.12)))
                            .help("Your one main goal: today's suggestions and the coach lean on it first")
                    }
                }
                Text(subtitle(summary)).ffText(.caption).lineLimit(1)
            }
            Spacer(minLength: FFSpace.s)
            if hasMeasures {
                PaceStatusPill(status: summary.status)
            }
            if let onEdit {
                Button("Edit", action: onEdit)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Edit goal")
                    .accessibilityLabel("Edit \(goal.title)")
            }
        }
    }

    private func subtitle(_ summary: GoalPacing.GoalSummary) -> String {
        var parts: [String] = []
        if let project { parts.append(project.name) }
        parts.append("Due \(goal.deadline.formatted(.dateTime.day().month(.abbreviated)))")
        parts.append(summary.deadlineLabel)
        return parts.joined(separator: " · ")
    }
}

/// A goal with nothing to count: the ways to give it a number, not a 0% bar. A goal is never
/// turned into a task (2026-11-02: "Add to Today's Tasks" made the goal a task and a reminder);
/// tasks and reminders only count toward a goal's numbers.
private struct GoalFirstStep: View {
    var onEdit: (() -> Void)?
    var onPickReminders: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: FFSpace.s) {
            Text("Nothing to count yet")
                .ffText(.body)
            Text(onPickReminders == nil
                 ? "Add a number to see if you're on pace, like “3 sections written”."
                 : "Add a number to see if you're on pace, like “3 sections written”, or pick the reminders that make up this goal: each one done adds 1.")
                .ffText(.caption)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: FFSpace.s) {
                if let onEdit {
                    Button("Add a Number", action: onEdit)
                        .buttonStyle(.bordered)
                }
                if let onPickReminders {
                    Button(action: onPickReminders) {
                        Label("Add from Reminders…", systemImage: "checklist")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(FFSpace.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: FFRadius.control, style: .continuous).fill(FFPalette.track))
    }
}

/// One number: progress against the steady pace, what keeps it on time, and +1 / −1.
struct KeyResultRow: View {
    let keyResult: GoalKeyResult
    let pace: KeyResultPace
    var compact: Bool = false
    var sessionID: UUID?

    @Environment(\.modelContext) private var modelContext
    @State private var bump = 0

    var body: some View {
        HStack(alignment: .center, spacing: FFSpace.m) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: FFSpace.s) {
                    Text(keyResult.title).ffText(.body).lineLimit(1)
                    Spacer(minLength: FFSpace.s)
                    Text("\(Self.number(pace.done)) of \(Self.number(pace.target))\(keyResult.unit.map { " \($0)" } ?? "")")
                        .ffText(.headline)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                PaceBar(fraction: pace.fraction, expected: pace.expectedFraction, color: pace.status.color, height: 6)
                if !compact {
                    Text(GoalPlainLanguage.measureCaption(pace)).ffText(.caption).monospacedDigit()
                }
            }
            HStack(spacing: 4) {
                Button { log(-1) } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(FFPalette.track))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(pace.done <= 0)
                .help("Take back 1")
                .accessibilityLabel("Take back 1: \(keyResult.title)")
                Button { log(1) } label: {
                    Text("+1")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .padding(.horizontal, 12)
                        .frame(minWidth: 44, minHeight: 30)
                        .background(Capsule().fill(FFPalette.accent.opacity(0.16)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(FFPalette.accent)
                .help("Log 1 \(keyResult.unit ?? keyResult.title)")
                .accessibilityLabel("Log 1: \(keyResult.title)")
            }
        }
        .sensoryFeedback(.increase, trigger: bump)
    }

    private func log(_ amount: Double) {
        guard amount != 0 else { return }
        let entry = GoalProgressEntry(amount: amount, sessionID: sessionID)
        modelContext.insert(entry)
        keyResult.entries.append(entry)
        try? modelContext.save()
        if amount > 0 { bump += 1 }
    }

    static func number(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }
}

/// Cumulative progress (all key results, as a share) against the straight line to the deadline.
struct GoalPaceChart: View {
    let goal: ProjectGoal
    let now: Date
    let tint: Color

    var body: some View {
        let points = series
        Chart {
            LineMark(x: .value("Day", goal.startDate), y: .value("Ideal", 0), series: .value("Line", "Ideal"))
                .foregroundStyle(FFPalette.comparison)
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            LineMark(x: .value("Day", goal.deadline), y: .value("Ideal", 100), series: .value("Line", "Ideal"))
                .foregroundStyle(FFPalette.comparison)
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                LineMark(x: .value("Day", point.date), y: .value("Done", point.percent), series: .value("Line", "Actual"))
                    .interpolationMethod(.stepEnd)
                    .foregroundStyle(tint)
                AreaMark(x: .value("Day", point.date), y: .value("Done", point.percent), series: .value("Line", "Actual"))
                    .interpolationMethod(.stepEnd)
                    .foregroundStyle(tint.opacity(0.12))
            }
            RuleMark(x: .value("Today", min(now, goal.deadline)))
                .foregroundStyle(Color.primary.opacity(0.25))
                .annotation(position: .top, alignment: .leading) {
                    Text("Today").font(.system(size: 10)).foregroundStyle(.secondary)
                }
        }
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(values: [0, 50, 100]) { value in
                AxisGridLine().foregroundStyle(FFPalette.gridLine)
                AxisValueLabel { Text("\(value.as(Int.self) ?? 0)%").font(.system(size: 10)) }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: .dateTime.day().month(.abbreviated)).font(.system(size: 10))
            }
        }
        .accessibilityLabel("Progress over time against the ideal pace to the deadline")
    }

    /// Overall percent after each logged entry (the mean of key-result shares).
    private var series: [(date: Date, percent: Double)] {
        let krs = goal.sortedKeyResults
        guard !krs.isEmpty else { return [(goal.startDate, 0)] }
        var done: [UUID: Double] = [:]
        var points: [(date: Date, percent: Double)] = [(goal.startDate, 0)]
        let entries = krs.flatMap { kr in kr.entries.map { (kr: kr, entry: $0) } }.sorted { $0.entry.at < $1.entry.at }
        for item in entries {
            done[item.kr.id, default: 0] = max(0, (done[item.kr.id] ?? 0) + item.entry.amount)
            let share = krs.map { min(1, (done[$0.id] ?? 0) / max(1, $0.target)) }.reduce(0, +) / Double(krs.count)
            points.append((item.entry.at, share * 100))
        }
        if let last = points.last, last.date < now { points.append((min(now, goal.deadline), last.percent)) }
        return points
    }
}

// MARK: - Honest breakdown

/// Where the time went, in priority order, against each project's target.
struct PriorityBreakdownView: View {
    let allocation: PriorityAllocation
    var showVerdict: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: FFSpace.m) {
            if showVerdict {
                Text(allocation.verdict(format: FFFormat.duration))
                    .ffText(.headline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: FFSpace.s) {
                ForEach(allocation.rows) { row in
                    rowView(row)
                }
            }
        }
    }

    private func rowView(_ row: PriorityRow) -> some View {
        HStack(spacing: FFSpace.m) {
            rankBadge(row)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: FFSpace.s) {
                    Text(row.name).ffText(.body).lineLimit(1)
                    // "Learning · Learning" says nothing: the kind shows only when it adds information.
                    if row.area.title.caseInsensitiveCompare(row.name) != .orderedSame {
                        Label(row.area.title, systemImage: row.area.symbol)
                            .labelStyle(.titleAndIcon)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: FFSpace.s)
                    Text(amountText(row)).ffText(.headline).monospacedDigit()
                }
                if let target = row.targetSeconds, target > 0 {
                    PaceBar(fraction: min(1, row.seconds / target), expected: 0, color: FFPalette.project(row.colorName), height: 6)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func rankBadge(_ row: PriorityRow) -> some View {
        Text(row.rank.map { "#\($0)" } ?? "")
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(row.rank == 1 ? Color.white : .secondary)
            .frame(width: 28, height: 22)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(row.rank == nil ? Color.clear : row.rank == 1 ? FFPalette.project(row.colorName) : FFPalette.track)
            )
            .help(row.rank.map { "Priority \($0)" } ?? "No priority")
            .accessibilityLabel(row.rank.map { "Priority \($0)" } ?? "Unranked")
    }

    private func amountText(_ row: PriorityRow) -> String {
        guard let target = row.targetSeconds, target > 0 else { return FFFormat.duration(row.seconds) }
        return "\(FFFormat.duration(row.seconds)) / \(FFFormat.duration(target))"
    }
}

// MARK: - Session complete

