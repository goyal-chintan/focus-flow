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

struct GoalCard: View {
    let goal: ProjectGoal
    let project: Project?
    let now: Date
    var compact: Bool = false
    var onEdit: (() -> Void)?

    @Environment(\.modelContext) private var modelContext
    @State private var showChart = false

    var body: some View {
        let summary = GoalDataBuilder.summary(goal, now: now)
        let tint = FFPalette.project(project?.color)
        VStack(alignment: .leading, spacing: FFSpace.m) {
            header(summary, tint: tint)
            VStack(alignment: .leading, spacing: 4) {
                PaceBar(fraction: summary.fraction, expected: summary.expectedFraction, color: summary.status.color, height: 10)
                HStack {
                    Text("\(Int((summary.fraction * 100).rounded()))% done").ffText(.caption).monospacedDigit()
                    Spacer()
                    Text("Should be \(Int((summary.expectedFraction * 100).rounded()))% by today").ffText(.caption).monospacedDigit()
                }
            }
            if !goal.keyResults.isEmpty {
                VStack(spacing: 14) {
                    ForEach(Array(zip(goal.sortedKeyResults, summary.keyResults)), id: \.0.id) { pair in
                        KeyResultRow(keyResult: pair.0, pace: pair.1, compact: compact)
                    }
                }
            }
            if !compact {
                DisclosureGroup(isExpanded: $showChart) {
                    GoalPaceChart(goal: goal, now: now, tint: summary.status.color)
                        .frame(height: 150)
                        .padding(.top, FFSpace.s)
                } label: {
                    Text("Pace chart · actual vs ideal").ffText(.callout)
                }
            }
        }
        .padding(FFSpace.l)
        .ffSurface()
    }

    private func header(_ summary: GoalPacing.GoalSummary, tint: Color) -> some View {
        HStack(alignment: .top, spacing: FFSpace.m) {
            Image(systemName: goal.isBossFight ? "flag.checkered" : "scope")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(Circle().fill(tint.opacity(0.15)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: FFSpace.s) {
                    Text(goal.title).ffText(.headline).lineLimit(2)
                    if goal.isBossFight {
                        Text("BOSS FIGHT")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .tracking(0.8)
                            .foregroundStyle(tint)
                            .padding(.horizontal, 6)
                            .frame(height: 18)
                            .background(Capsule().strokeBorder(tint.opacity(0.5), lineWidth: 1))
                            .help("This month's main goal")
                    }
                }
                Text(subtitle(summary)).ffText(.caption).lineLimit(1)
            }
            Spacer(minLength: FFSpace.s)
            PaceStatusPill(status: summary.status)
            if let onEdit {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
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

/// One key result: progress against the ideal, what is needed per day, and one-click logging.
struct KeyResultRow: View {
    let keyResult: GoalKeyResult
    let pace: KeyResultPace
    var compact: Bool = false
    var sessionID: UUID?

    @Environment(\.modelContext) private var modelContext
    @State private var bump = 0

    var body: some View {
        HStack(alignment: .center, spacing: FFSpace.m) {
            if keyResult.kind == .checkbox {
                Button {
                    log(pace.status == .done ? -keyResult.done : 1)
                } label: {
                    Image(systemName: pace.status == .done ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18))
                        .foregroundStyle(pace.status == .done ? FFPalette.goal : .secondary)
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(pace.status == .done ? "Mark \(keyResult.title) not done" : "Mark \(keyResult.title) done")
                Text(keyResult.title)
                    .ffText(.body)
                    .strikethrough(pace.status == .done, color: .secondary)
                Spacer(minLength: FFSpace.s)
                if pace.status == .overdue { PaceStatusPill(status: .overdue) }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: FFSpace.s) {
                        Text(keyResult.title).ffText(.body).lineLimit(1)
                        Spacer(minLength: FFSpace.s)
                        Text("\(Self.number(pace.done)) / \(Self.number(pace.target))\(keyResult.unit.map { " \($0)" } ?? "")")
                            .ffText(.headline)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }
                    PaceBar(fraction: pace.fraction, expected: pace.expectedFraction, color: pace.status.color, height: 6)
                    if !compact {
                        Text(caption).ffText(.caption).monospacedDigit()
                    }
                }
                HStack(spacing: 2) {
                    stepButton("minus", amount: -1, label: "Remove one")
                        .disabled(pace.done <= 0)
                    stepButton("plus", amount: 1, label: "Add one")
                }
            }
        }
        .sensoryFeedback(.increase, trigger: bump)
    }

    private var caption: String {
        switch pace.status {
        case .done: return "Done."
        case .overdue: return "Past the deadline · \(Self.number(pace.remaining)) left"
        case .notStarted: return "Starts later"
        default:
            let delta = pace.delta
            let position: String
            if abs(delta) < 0.5 {
                position = "On pace"
            } else if delta < 0 {
                position = -delta < 1 ? "Slightly behind" : "\(Int((-delta).rounded())) behind"
            } else {
                position = "\(Int(delta.rounded())) ahead"
            }
            return "\(position) · need \(PaceFormat.rate(pace.neededPerDay ?? 0))"
        }
    }

    private func stepButton(_ symbol: String, amount: Double, label: String) -> some View {
        Button {
            log(amount)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .frame(width: 30, height: 30)
                .background(Circle().fill(amount > 0 ? FFPalette.accent.opacity(0.16) : FFPalette.track))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(amount > 0 ? FFPalette.accent : .secondary)
        .help(label)
        .accessibilityLabel("\(label): \(keyResult.title)")
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

// MARK: - Levers

struct LeverRow: View {
    let lever: DailyLever

    var body: some View {
        HStack(spacing: FFSpace.m) {
            Image(systemName: lever.status == .overdue || lever.status == .behind ? "bolt.fill" : "arrow.forward.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(lever.status.color)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(lever.action).ffText(.headline)
                Text("\(lever.goalTitle) · \(lever.reason)").ffText(.caption).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
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
            stackedBar
            VStack(spacing: FFSpace.s) {
                ForEach(allocation.rows) { row in
                    rowView(row)
                }
            }
        }
    }

    private var stackedBar: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                if allocation.totalSeconds > 0 {
                    ForEach(allocation.rows.filter { $0.seconds > 0 }) { row in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(FFPalette.project(row.colorName).opacity(row.area.isOwnWork ? 1 : 0.45))
                            .frame(width: max(2, (geo.size.width - CGFloat(allocation.rows.count) * 2) * row.seconds / allocation.totalSeconds))
                            .help("\(row.name): \(FFFormat.duration(row.seconds))")
                    }
                } else {
                    RoundedRectangle(cornerRadius: 3).fill(FFPalette.track)
                }
            }
        }
        .frame(height: 14)
        .accessibilityLabel("Time split by project")
    }

    private func rowView(_ row: PriorityRow) -> some View {
        HStack(spacing: FFSpace.m) {
            rankBadge(row)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: FFSpace.s) {
                    Text(row.name).ffText(.body).lineLimit(1)
                    Label(row.area.title, systemImage: row.area.symbol)
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
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
        Text(row.rank.map { "#\($0)" } ?? "–")
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(row.rank == 1 ? Color.white : .secondary)
            .frame(width: 28, height: 22)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(row.rank == 1 ? FFPalette.project(row.colorName) : FFPalette.track)
            )
            .accessibilityLabel(row.rank.map { "Priority \($0)" } ?? "Unranked")
    }

    private func amountText(_ row: PriorityRow) -> String {
        guard let target = row.targetSeconds, target > 0 else { return FFFormat.duration(row.seconds) }
        return "\(FFFormat.duration(row.seconds)) / \(FFFormat.duration(target))"
    }
}

// MARK: - Session complete

/// "Progress on your goal": the session project's active key results with +1, logged against the
/// session (priorities-goals design §3.6). Recording progress is what makes monitoring work
/// (Harkin et al., 2016).
struct SessionGoalProgressView: View {
    let projectID: UUID?
    let sessionID: UUID?

    @Query(sort: \ProjectGoal.deadline) private var goals: [ProjectGoal]

    var body: some View {
        let relevant = goals.filter { $0.status == .active && $0.projectID != nil && $0.projectID == projectID }
        if !relevant.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("PROGRESS ON YOUR GOAL")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.8)
                    .foregroundStyle(.secondary)
                ForEach(relevant) { goal in
                    let summary = GoalDataBuilder.summary(goal, now: Date())
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(goal.title).font(.system(size: 12, weight: .semibold))
                            Spacer()
                            PaceStatusPill(status: summary.status)
                        }
                        ForEach(Array(zip(goal.sortedKeyResults, summary.keyResults)), id: \.0.id) { pair in
                            KeyResultRow(keyResult: pair.0, pace: pair.1, compact: true, sessionID: sessionID)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
