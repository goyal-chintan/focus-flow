import Foundation

// Priorities, goals and the honest breakdown (docs/plans/2026-10-28-priorities-goals-design.md §3).
// Pure value types and functions; the views and TimerViewModel feed them from SwiftData.

// MARK: - Goal pacing (§3.2)

enum GoalPaceStatus: String, Sendable, Equatable {
    case done
    case ahead
    case onTrack
    case behind
    /// Past the deadline and not done.
    case overdue
    /// Before the start date.
    case notStarted

    var title: String {
        switch self {
        case .done: "Done"
        case .ahead: "Ahead"
        case .onTrack: "On track"
        case .behind: "Behind"
        case .overdue: "Overdue"
        case .notStarted: "Not started"
        }
    }

    /// Worse statuses sort first (behind before on track).
    var severity: Int {
        switch self {
        case .overdue: 0
        case .behind: 1
        case .onTrack: 2
        case .notStarted: 3
        case .ahead: 4
        case .done: 5
        }
    }
}

/// "2.6/day", or "1 every 3 days" when the rate is below one a day.
enum PaceFormat {
    static func rate(_ perDay: Double) -> String {
        guard perDay > 0 else { return "nothing more needed" }
        if perDay >= 0.95 { return String(format: perDay.rounded() == perDay ? "%.0f/day" : "%.1f/day", perDay) }
        let every = max(2, Int((1 / perDay).rounded()))
        return "1 every \(every) days"
    }
}

struct KeyResultPace: Sendable, Equatable {
    let target: Double
    let done: Double
    /// Where you should be by now if the work were spread evenly from start to deadline.
    let expected: Double
    let status: GoalPaceStatus
    /// Remaining ÷ days left (nil when done or overdue).
    let neededPerDay: Double?
    /// Finish date at the rate so far (nil with no progress or when done).
    let projectedFinish: Date?
    let daysLeft: Double

    var fraction: Double { target > 0 ? min(1, done / target) : 0 }
    var expectedFraction: Double { target > 0 ? min(1, expected / target) : 0 }
    var remaining: Double { max(0, target - done) }
    /// done − expected (negative = behind).
    var delta: Double { done - expected }
}

enum GoalPacing {
    /// On track down to this share of the expected amount.
    static let onTrackTolerance = 0.9
    /// Ahead from this share of the expected amount (and at least one unit).
    static let aheadMargin = 1.1

    static func timeFraction(start: Date, deadline: Date, now: Date) -> Double {
        let total = deadline.timeIntervalSince(start)
        guard total > 0 else { return now >= deadline ? 1 : 0 }
        return min(1, max(0, now.timeIntervalSince(start) / total))
    }

    static func pace(target: Double, done: Double, start: Date, deadline: Date, now: Date) -> KeyResultPace {
        let fraction = timeFraction(start: start, deadline: deadline, now: now)
        let expected = target * fraction
        let daysLeft = max(0, deadline.timeIntervalSince(now) / 86_400)
        let remaining = max(0, target - done)
        let status: GoalPaceStatus
        if done >= target {
            status = .done
        } else if now >= deadline {
            status = .overdue
        } else if now < start {
            status = .notStarted
        } else if done >= max(expected * aheadMargin, expected + 1) {
            status = .ahead
        } else if done >= expected * onTrackTolerance || expected - done < 0.5 {
            status = .onTrack
        } else {
            status = .behind
        }
        let elapsedDays = max(0, now.timeIntervalSince(start) / 86_400)
        var projected: Date?
        if status != .done, done > 0, elapsedDays > 0 {
            let rate = done / elapsedDays
            projected = now.addingTimeInterval(remaining / rate * 86_400)
        }
        let needed: Double? = (status == .done || status == .overdue) ? nil : remaining / max(daysLeft, 1.0 / 24)
        return KeyResultPace(
            target: target, done: done, expected: expected, status: status,
            neededPerDay: needed, projectedFinish: projected, daysLeft: daysLeft
        )
    }

    struct GoalSummary: Sendable, Equatable {
        let fraction: Double
        let expectedFraction: Double
        let status: GoalPaceStatus
        let daysLeft: Double
        let keyResults: [KeyResultPace]

        /// "18 days left", "Due today", "3 days overdue".
        var deadlineLabel: String {
            if status == .done { return "Done" }
            let days = Int(daysLeft.rounded(.up))
            if daysLeft <= 0 { return "Past the deadline" }
            if days <= 1 { return "Due today" }
            return "\(days) days left"
        }
    }

    /// A goal's progress is the mean of its key results; its status compares that with the time elapsed.
    static func summary(keyResults: [(target: Double, done: Double)], start: Date, deadline: Date, now: Date) -> GoalSummary {
        let paces = keyResults.map { pace(target: $0.target, done: $0.done, start: start, deadline: deadline, now: now) }
        let fraction = paces.isEmpty ? 0 : paces.map(\.fraction).reduce(0, +) / Double(paces.count)
        let expectedFraction = timeFraction(start: start, deadline: deadline, now: now)
        let daysLeft = max(0, deadline.timeIntervalSince(now) / 86_400)
        let status: GoalPaceStatus
        if !paces.isEmpty && paces.allSatisfy({ $0.status == .done }) {
            status = .done
        } else if now >= deadline {
            status = .overdue
        } else if now < start {
            status = .notStarted
        } else if paces.isEmpty {
            status = .onTrack
        } else if fraction >= expectedFraction * aheadMargin && fraction > expectedFraction + 0.02 {
            status = .ahead
        } else if fraction >= expectedFraction * onTrackTolerance {
            status = .onTrack
        } else {
            status = .behind
        }
        return GoalSummary(fraction: fraction, expectedFraction: expectedFraction, status: status, daysLeft: daysLeft, keyResults: paces)
    }

    /// Cumulative done after each entry, for the pace chart: (date, done).
    static func cumulative(_ entries: [(at: Date, amount: Double)], start: Date) -> [(date: Date, done: Double)] {
        var total = 0.0
        var points: [(date: Date, done: Double)] = [(start, 0)]
        for entry in entries.sorted(by: { $0.at < $1.at }) {
            total = max(0, total + entry.amount)
            points.append((entry.at, total))
        }
        return points
    }
}

// MARK: - The honest breakdown (§3.3)

/// One project's day (or period), in priority order.
struct PriorityRow: Sendable, Equatable, Identifiable {
    let id: String
    let name: String
    let colorName: String?
    let rank: Int?
    let area: ProjectArea
    let seconds: TimeInterval
    /// Target for the period (nil when unset).
    let targetSeconds: TimeInterval?

    var targetFraction: Double? { targetSeconds.map { $0 > 0 ? seconds / $0 : 0 } }
}

struct PriorityAllocation: Sendable, Equatable {
    struct ProjectInfo: Sendable, Equatable {
        let id: String
        let name: String
        let colorName: String?
        let rank: Int?
        let area: ProjectArea
        /// Target for the whole period.
        let targetSeconds: TimeInterval?
    }

    let rows: [PriorityRow]
    let totalSeconds: TimeInterval
    let ownWorkSeconds: TimeInterval
    let top: PriorityRow?

    var ownWorkShare: Double { totalSeconds > 0 ? ownWorkSeconds / totalSeconds : 0 }

    /// `seconds` maps project id → tracked seconds (splits already attributed). Ids missing from
    /// `projects` (unassigned time, labels) are reported as one "Unassigned" row.
    static func compute(projects: [ProjectInfo], seconds: [String: TimeInterval]) -> PriorityAllocation {
        var rows: [PriorityRow] = projects.map { info in
            PriorityRow(
                id: info.id, name: info.name, colorName: info.colorName, rank: info.rank, area: info.area,
                seconds: seconds[info.id] ?? 0, targetSeconds: info.targetSeconds
            )
        }
        let known = Set(projects.map(\.id))
        let other = seconds.filter { !known.contains($0.key) }.values.reduce(0, +)
        if other > 0 {
            rows.append(PriorityRow(id: "unassigned", name: "Unassigned", colorName: nil, rank: nil, area: .other, seconds: other, targetSeconds: nil))
        }
        rows.sort(by: order)
        let total = rows.reduce(0) { $0 + $1.seconds }
        let own = rows.filter { $0.area.isOwnWork }.reduce(0) { $0 + $1.seconds }
        let top = rows.first { $0.rank != nil }
        return PriorityAllocation(rows: rows, totalSeconds: total, ownWorkSeconds: own, top: top)
    }

    /// Ranked first (1, 2, …), then unranked by time, then unassigned last.
    static func order(_ lhs: PriorityRow, _ rhs: PriorityRow) -> Bool {
        if (lhs.id == "unassigned") != (rhs.id == "unassigned") { return rhs.id == "unassigned" }
        switch (lhs.rank, rhs.rank) {
        case let (l?, r?): return l != r ? l < r : lhs.name < rhs.name
        case (_?, nil): return true
        case (nil, _?): return false
        case (nil, nil): return lhs.seconds != rhs.seconds ? lhs.seconds > rhs.seconds : lhs.name < rhs.name
        }
    }

    /// One short line for small surfaces: "6h 40m tracked · 55m on your #1 · 14% own work".
    func shortVerdict(format: (TimeInterval) -> String) -> String {
        guard totalSeconds > 0 else { return "Nothing tracked yet." }
        var parts = ["\(format(totalSeconds)) tracked"]
        if let top { parts.append("\(format(top.seconds)) on your #\(top.rank ?? 1)") }
        parts.append("\(Int((ownWorkShare * 100).rounded()))% own work")
        return parts.joined(separator: " · ")
    }

    /// "6h 40m tracked · 55m on Learning, your #1 (target 4h) · 14% your own work".
    func verdict(format: (TimeInterval) -> String) -> String {
        guard totalSeconds > 0 else {
            if let top { return "Nothing tracked yet. Your #1 is \(top.name)." }
            return "Nothing tracked yet."
        }
        var parts = ["\(format(totalSeconds)) tracked"]
        if let top {
            var line = "\(format(top.seconds)) on \(top.name), your #\(top.rank ?? 1)"
            if let target = top.targetSeconds, target > 0 { line += " (target \(format(target)))" }
            parts.append(line)
        }
        parts.append("\(Int((ownWorkShare * 100).rounded()))% your own work")
        return parts.joined(separator: " · ")
    }
}

// MARK: - Drift report: said vs did (§3.4)

struct DriftReport: Sendable, Equatable {
    struct Line: Sendable, Equatable, Identifiable {
        let id: String
        let name: String
        let colorName: String?
        let rank: Int?
        let area: ProjectArea
        /// Average per day over the period.
        let actualPerDay: TimeInterval
        let targetPerDay: TimeInterval?

        var share: Double? { targetPerDay.map { $0 > 0 ? actualPerDay / $0 : 0 } }
        /// actual − target per day (negative = under).
        var gapPerDay: TimeInterval? { targetPerDay.map { actualPerDay - $0 } }
    }

    struct Day: Sendable, Equatable, Identifiable {
        let day: Date
        let total: TimeInterval
        let ownWork: TimeInterval
        var id: Date { day }
        var ownShare: Double { total > 0 ? ownWork / total : 0 }
    }

    let days: Int
    let lines: [Line]
    let daily: [Day]

    /// Lines in priority order. `perDay` holds one allocation per day of the period.
    static func compute(perDay: [(day: Date, allocation: PriorityAllocation)]) -> DriftReport {
        let n = max(1, perDay.count)
        var byID: [String: (row: PriorityRow, seconds: TimeInterval, target: TimeInterval, targetDays: Int)] = [:]
        for (_, allocation) in perDay {
            for row in allocation.rows {
                var entry = byID[row.id] ?? (row, 0, 0, 0)
                entry.seconds += row.seconds
                if let target = row.targetSeconds {
                    entry.target += target
                    entry.targetDays += 1
                }
                entry.row = row
                byID[row.id] = entry
            }
        }
        let lines = byID.values
            .map { entry in
                Line(
                    id: entry.row.id, name: entry.row.name, colorName: entry.row.colorName, rank: entry.row.rank, area: entry.row.area,
                    actualPerDay: entry.seconds / Double(n),
                    targetPerDay: entry.targetDays > 0 ? entry.target / Double(n) : nil
                )
            }
            .filter { $0.actualPerDay > 0 || ($0.targetPerDay ?? 0) > 0 }
            .sorted { lhs, rhs in
                PriorityAllocation.order(
                    PriorityRow(id: lhs.id, name: lhs.name, colorName: nil, rank: lhs.rank, area: lhs.area, seconds: lhs.actualPerDay, targetSeconds: nil),
                    PriorityRow(id: rhs.id, name: rhs.name, colorName: nil, rank: rhs.rank, area: rhs.area, seconds: rhs.actualPerDay, targetSeconds: nil)
                )
            }
        let daily = perDay.map { Day(day: $0.day, total: $0.allocation.totalSeconds, ownWork: $0.allocation.ownWorkSeconds) }
        return DriftReport(days: perDay.count, lines: lines, daily: daily)
    }

    /// The ranked project furthest under its target (the biggest drift), if any is under.
    var biggestGap: Line? {
        lines.filter { ($0.gapPerDay ?? 0) < 0 }.min { ($0.gapPerDay ?? 0) < ($1.gapPerDay ?? 0) }
    }

    var ownWorkShare: Double {
        let total = daily.reduce(0) { $0 + $1.total }
        return total > 0 ? daily.reduce(0) { $0 + $1.ownWork } / total : 0
    }

    /// Plain-language findings, most important first.
    func findings(format: (TimeInterval) -> String) -> [String] {
        var result: [String] = []
        if let top = lines.first(where: { $0.rank == 1 }), let target = top.targetPerDay, target > 0 {
            let pct = Int(((top.share ?? 0) * 100).rounded())
            result.append("Your #1, \(top.name), got \(format(top.actualPerDay)) a day: \(pct)% of the \(format(target)) you planned.")
        }
        if let gap = biggestGap, gap.rank != 1, let target = gap.targetPerDay {
            result.append("\(gap.name) is \(format(target - gap.actualPerDay)) a day under its target.")
        }
        let over = lines.filter { ($0.share ?? 0) > 1.2 && !$0.area.isOwnWork }
        for line in over.prefix(1) {
            result.append("\(line.name) took \(Int(((line.share ?? 0) * 100).rounded()))% of its target, more than planned.")
        }
        let total = daily.reduce(0) { $0 + $1.total }
        if total > 0 {
            result.append("\(Int((ownWorkShare * 100).rounded()))% of your tracked time was your own work.")
        }
        return result
    }
}

// MARK: - Today's levers (§3.5)

/// Up to three concrete actions for today, from the key results furthest behind pace.
/// Dan Koe's "daily levers"; implementation-intention sized ("2 LeetCode questions").
struct DailyLever: Sendable, Equatable, Identifiable {
    let id: UUID
    let goalTitle: String
    let projectID: UUID?
    /// "2 LeetCode questions", "Apply for jobs".
    var action: String
    /// "need 2.1/day · 18 days left".
    let reason: String
    let status: GoalPaceStatus
    let urgency: Double
    /// How much today's action adds to the key result (3 for "3 LeetCode questions").
    var amount: Double = 1
    /// The thing being counted, for a counted task: "LeetCode questions", "Problems solved".
    var countedName: String? = nil

    /// The title for "add as a task". A counted task names what you count; its counter shows how
    /// many ("Problems solved 0 of 3"). A one-off keeps the action.
    var taskTitle: String { amount > 1 ? (countedName ?? action) : action }
}

enum DailyLevers {
    struct KeyResultInput: Sendable {
        let id: UUID
        let title: String
        let unit: String?
        let target: Double
        let done: Double
        let doneToday: Double
        let goalTitle: String
        let projectID: UUID?
        let start: Date
        let deadline: Date
        /// The month's main goal: its levers come first.
        var isBossFight: Bool = false
        /// Own work and your ★ #1 project come before other projects' goals (`GoalDataBuilder`).
        var priorityBoost: Double = 0
    }

    static let maxLevers = 3

    /// "questions" → "question" for one (English plural heuristic: a trailing "s").
    static func unit(_ unit: String, count: Int) -> String {
        guard count == 1, unit.count > 2, unit.hasSuffix("s"), !unit.hasSuffix("ss") else { return unit }
        return String(unit.dropLast())
    }

    static func levers(_ inputs: [KeyResultInput], now: Date) -> [DailyLever] {
        inputs.compactMap { input -> DailyLever? in
            let pace = GoalPacing.pace(target: input.target, done: input.done, start: input.start, deadline: input.deadline, now: now)
            guard pace.status != .done, pace.status != .notStarted else { return nil }
            // A result of 1 is a one-off step: it belongs in tasks, never a daily ask.
            guard input.target > 1 else { return nil }
            let daysLeft = Int(pace.daysLeft.rounded(.up))
            let needed = pace.neededPerDay ?? pace.remaining
            // Round up, but not for clock noise: 3.0000001 a day is 3.
            let quota = (needed - 0.01).rounded(.up)
            let todayAsk = max(1, Int(quota) - Int(input.doneToday))
            guard input.doneToday < quota else { return nil }
            // "3 LeetCode questions" with a unit; "Referral asks: 1 today" without one.
            let action = input.unit.map { "\(todayAsk) \(input.title) \(DailyLevers.unit($0, count: todayAsk))" }
                ?? "\(input.title): \(todayAsk) today"
            return DailyLever(
                id: input.id, goalTitle: input.goalTitle, projectID: input.projectID,
                action: action,
                reason: pace.status == .overdue
                    ? "overdue · \(Int(pace.remaining.rounded())) left"
                    : "need \(PaceFormat.rate(needed)) · \(daysLeft) day\(daysLeft == 1 ? "" : "s") left",
                status: pace.status,
                urgency: (pace.status == .overdue ? 100 : 0) + (input.isBossFight ? 50 : 0) + input.priorityBoost
                    + max(0, -pace.delta) / max(1, input.target) * 10 + needed / max(1, input.target),
                amount: Double(todayAsk),
                countedName: input.unit.map { "\(input.title) \($0)" } ?? input.title
            )
        }
        // Most urgent first: overdue and the boss fight carry large bonuses, then how far behind.
        .sorted { lhs, rhs in
            lhs.urgency != rhs.urgency ? lhs.urgency > rhs.urgency : lhs.status.severity < rhs.status.severity
        }
        .prefix(maxLevers)
        .map { $0 }
    }
}
