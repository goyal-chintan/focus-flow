import Foundation

/// Pure analytics for the companion window (Today, History, Insights, Projects).
///
/// Every function takes plain arrays plus an explicit `now`, and uses the injected
/// calendar for day/week/hour boundaries, so results are deterministic in tests.
/// Focus time is always pause-excluded active time (`FocusSample.activeSeconds`),
/// and a block that crosses midnight is split across both days by overlap.
struct FocusAnalytics: Sendable {
    let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    // MARK: - Calendar helpers

    func dayInterval(containing date: Date) -> DateInterval {
        calendar.dateInterval(of: .day, for: date)
            ?? DateInterval(start: calendar.startOfDay(for: date), duration: 86_400)
    }

    func weekInterval(containing date: Date) -> DateInterval {
        calendar.dateInterval(of: .weekOfYear, for: date) ?? dayInterval(containing: date)
    }

    /// Start-of-day dates for the `count` days ending with the day containing `now`, oldest first.
    func trailingDays(_ count: Int, endingAt now: Date) -> [Date] {
        let today = calendar.startOfDay(for: now)
        return (0..<max(0, count)).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
    }

    /// Monday-first weekday index (Mon = 0 … Sun = 6), independent of the calendar's `firstWeekday`.
    func mondayFirstWeekdayIndex(of date: Date) -> Int {
        (calendar.component(.weekday, from: date) + 5) % 7
    }

    // MARK: - Daily totals

    struct ProjectSlice: Hashable, Sendable {
        let project: AnalyticsProjectKey
        let seconds: TimeInterval
    }

    struct DayTotal: Hashable, Sendable, Identifiable {
        let day: Date
        let seconds: TimeInterval
        /// Focus blocks that overlap this day (a cross-midnight block counts on both days).
        let blocks: Int
        /// Per-project time, largest first.
        let byProject: [ProjectSlice]

        var id: Date { day }
    }

    func dayTotal(_ sessions: [FocusSample], on day: Date) -> DayTotal {
        let interval = dayInterval(containing: day)
        var seconds: TimeInterval = 0
        var blocks = 0
        var byProject: [AnalyticsProjectKey: TimeInterval] = [:]
        for session in sessions where session.isFocus {
            let overlap = session.overlap(with: interval)
            guard overlap > 0 else { continue }
            seconds += overlap
            blocks += 1
            for share in session.normalisedShares {
                byProject[share.project, default: 0] += overlap * share.fraction
            }
        }
        let slices: [ProjectSlice] = byProject
            .map { ProjectSlice(project: $0.key, seconds: $0.value) }
            .sorted(by: Self.largestFirst)
        return DayTotal(day: interval.start, seconds: seconds, blocks: blocks, byProject: slices)
    }

    private static func largestFirst(_ lhs: ProjectSlice, _ rhs: ProjectSlice) -> Bool {
        lhs.seconds == rhs.seconds ? lhs.project < rhs.project : lhs.seconds > rhs.seconds
    }

    func dailyTotals(_ sessions: [FocusSample], days: [Date]) -> [DayTotal] {
        let focus = sessions.filter(\.isFocus)
        return days.map { dayTotal(focus, on: $0) }
    }

    func dailyTotals(_ sessions: [FocusSample], trailing count: Int, endingAt now: Date) -> [DayTotal] {
        dailyTotals(sessions, days: trailingDays(count, endingAt: now))
    }

    // MARK: - Goal

    struct GoalProgress: Hashable, Sendable {
        let doneSeconds: TimeInterval
        let goalSeconds: TimeInterval
        let stretchSeconds: TimeInterval

        var remainingSeconds: TimeInterval { max(0, goalSeconds - doneSeconds) }
        var surplusSeconds: TimeInterval { max(0, doneSeconds - goalSeconds) }
        var isMet: Bool { goalSeconds > 0 && doneSeconds >= goalSeconds }
        var isStretchMet: Bool { stretchSeconds > 0 && doneSeconds >= stretchSeconds }
        /// 0…1 progress towards the goal (clamped).
        var fraction: Double { goalSeconds > 0 ? min(1, doneSeconds / goalSeconds) : 0 }
    }

    func goalProgress(_ sessions: [FocusSample], on day: Date, goal: TimeInterval, stretch: TimeInterval) -> GoalProgress {
        GoalProgress(doneSeconds: dayTotal(sessions, on: day).seconds, goalSeconds: goal, stretchSeconds: stretch)
    }

    // MARK: - Streaks

    enum NeverMissTwice: Hashable, Sendable {
        /// No focus history yet.
        case noHistory
        /// Yesterday met the goal (or today already has).
        case onTrack
        /// Yesterday was missed; today decides whether it becomes a pattern.
        case missedYesterday
        /// Yesterday and the day before were both missed.
        case missedTwice
    }

    struct StreakSummary: Hashable, Sendable {
        /// Consecutive goal-met days ending today (or yesterday, while today is still open).
        let current: Int
        /// Longest run of goal-met days in the history.
        let best: Int
        let todayMet: Bool
        let neverMissTwice: NeverMissTwice
    }

    func streak(_ sessions: [FocusSample], goal: TimeInterval, now: Date) -> StreakSummary {
        let focus = sessions.filter { $0.isFocus && $0.activeSeconds > 0 }
        guard goal > 0, let first = focus.map(\.start).min() else {
            return StreakSummary(current: 0, best: 0, todayMet: false, neverMissTwice: .noHistory)
        }

        let today = calendar.startOfDay(for: now)
        let firstDay = calendar.startOfDay(for: first)
        let dayCount = (calendar.dateComponents([.day], from: firstDay, to: today).day ?? 0) + 1
        let days = trailingDays(max(1, dayCount), endingAt: now)
        let met = dailyTotals(focus, days: days).map { $0.seconds >= goal }

        var best = 0
        var run = 0
        for value in met {
            run = value ? run + 1 : 0
            best = max(best, run)
        }

        let todayMet = met.last ?? false
        var current = 0
        var index = met.count - 1
        if !todayMet { index -= 1 }
        while index >= 0, met[index] {
            current += 1
            index -= 1
        }

        let status: NeverMissTwice
        if todayMet || met.count < 2 {
            status = .onTrack
        } else {
            let yesterdayMissed = !met[met.count - 2]
            let dayBeforeMissed = met.count >= 3 ? !met[met.count - 3] : false
            if yesterdayMissed && dayBeforeMissed {
                status = .missedTwice
            } else if yesterdayMissed {
                status = .missedYesterday
            } else {
                status = .onTrack
            }
        }

        return StreakSummary(current: current, best: best, todayMet: todayMet, neverMissTwice: status)
    }

    // MARK: - Range summary (History)

    struct RangeSummary: Hashable, Sendable {
        let totalSeconds: TimeInterval
        let dailyAverageSeconds: TimeInterval
        let goalMetDays: Int
        let dayCount: Int
        let bestDay: DayTotal?
    }

    func rangeSummary(_ days: [DayTotal], goal: TimeInterval) -> RangeSummary {
        let total = days.reduce(0) { $0 + $1.seconds }
        let best = days.filter { $0.seconds > 0 }.max { $0.seconds < $1.seconds }
        return RangeSummary(
            totalSeconds: total,
            dailyAverageSeconds: days.isEmpty ? 0 : total / Double(days.count),
            goalMetDays: goal > 0 ? days.filter { $0.seconds >= goal }.count : 0,
            dayCount: days.count,
            bestDay: best
        )
    }

    // MARK: - Week over week

    struct WeekComparison: Hashable, Sendable {
        let thisWeekSeconds: TimeInterval
        /// Last week up to the same weekday and time as `now`, so partial weeks compare fairly.
        let lastWeekSameSpanSeconds: TimeInterval
        let lastWeekSeconds: TimeInterval
        let thisWeekGoalDays: Int
        let lastWeekGoalDays: Int

        var deltaSeconds: TimeInterval { thisWeekSeconds - lastWeekSameSpanSeconds }
        /// Relative change vs the same span last week, `nil` when last week had nothing.
        var deltaFraction: Double? {
            lastWeekSameSpanSeconds > 0 ? deltaSeconds / lastWeekSameSpanSeconds : nil
        }
    }

    func weekOverWeek(_ sessions: [FocusSample], goal: TimeInterval, now: Date) -> WeekComparison {
        let focus = sessions.filter(\.isFocus)
        let thisWeek = weekInterval(containing: now)
        let lastWeekStart = calendar.date(byAdding: .weekOfYear, value: -1, to: thisWeek.start) ?? thisWeek.start
        let lastWeek = weekInterval(containing: lastWeekStart)
        let elapsed = max(0, now.timeIntervalSince(thisWeek.start))
        let lastSpan = DateInterval(start: lastWeek.start, duration: min(elapsed, lastWeek.duration))
        let thisSpan = DateInterval(start: thisWeek.start, end: max(thisWeek.start, min(now, thisWeek.end)))

        func seconds(in interval: DateInterval) -> TimeInterval {
            focus.reduce(0) { $0 + $1.overlap(with: interval) }
        }

        func goalDays(in interval: DateInterval, upTo limit: Date) -> Int {
            guard goal > 0 else { return 0 }
            var count = 0
            var day = interval.start
            while day < interval.end, day <= limit {
                if dayTotal(focus, on: day).seconds >= goal { count += 1 }
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
            return count
        }

        return WeekComparison(
            thisWeekSeconds: seconds(in: thisSpan),
            lastWeekSameSpanSeconds: seconds(in: lastSpan),
            lastWeekSeconds: seconds(in: lastWeek),
            thisWeekGoalDays: goalDays(in: thisWeek, upTo: now),
            lastWeekGoalDays: goalDays(in: lastWeek, upTo: lastWeek.end)
        )
    }

    // MARK: - Projects

    struct ProjectTotal: Hashable, Sendable, Identifiable {
        let project: AnalyticsProjectKey
        let seconds: TimeInterval
        let sessions: Int
        var id: String { project.id }
    }

    func projectTotals(_ sessions: [FocusSample], in interval: DateInterval) -> [ProjectTotal] {
        var seconds: [AnalyticsProjectKey: TimeInterval] = [:]
        var counts: [AnalyticsProjectKey: Int] = [:]
        for session in sessions where session.isFocus {
            let overlap = session.overlap(with: interval)
            guard overlap > 0 else { continue }
            for share in session.normalisedShares {
                seconds[share.project, default: 0] += overlap * share.fraction
                counts[share.project, default: 0] += 1
            }
        }
        let totals: [ProjectTotal] = seconds.map { ProjectTotal(project: $0.key, seconds: $0.value, sessions: counts[$0.key] ?? 0) }
        return totals.sorted { lhs, rhs in
            lhs.seconds == rhs.seconds ? lhs.project < rhs.project : lhs.seconds > rhs.seconds
        }
    }

    // MARK: - Weekly priorities

    struct PriorityTotal: Hashable, Sendable, Identifiable {
        let priority: PrioritySample
        let seconds: TimeInterval
        let sessions: Int
        var id: UUID { priority.id }
    }

    struct PriorityBreakdown: Hashable, Sendable {
        /// This week's priorities in their set order, with focus time tagged to each.
        let priorities: [PriorityTotal]
        /// Focus time this week not tagged to one of this week's priorities.
        let untaggedSeconds: TimeInterval
        let totalSeconds: TimeInterval
    }

    func priorityBreakdown(_ sessions: [FocusSample], priorities: [PrioritySample], now: Date) -> PriorityBreakdown {
        let week = weekInterval(containing: now)
        let thisWeeks = priorities
            .filter { week.contains($0.weekStart) || calendar.isDate($0.weekStart, equalTo: now, toGranularity: .weekOfYear) }
            .sorted { (lhs: PrioritySample, rhs: PrioritySample) -> Bool in
                lhs.order == rhs.order ? lhs.title < rhs.title : lhs.order < rhs.order
            }
        let ids = Set(thisWeeks.map(\.id))
        var seconds: [UUID: TimeInterval] = [:]
        var counts: [UUID: Int] = [:]
        var untagged: TimeInterval = 0
        var total: TimeInterval = 0
        for session in sessions where session.isFocus {
            let overlap = session.overlap(with: week)
            guard overlap > 0 else { continue }
            total += overlap
            if let id = session.priorityID, ids.contains(id) {
                seconds[id, default: 0] += overlap
                counts[id, default: 0] += 1
            } else {
                untagged += overlap
            }
        }
        return PriorityBreakdown(
            priorities: thisWeeks.map { PriorityTotal(priority: $0, seconds: seconds[$0.id] ?? 0, sessions: counts[$0.id] ?? 0) },
            untaggedSeconds: untagged,
            totalSeconds: total
        )
    }

    // MARK: - Outcomes (real work vs busywork)

    struct OutcomeMix: Hashable, Sendable {
        var counts: [SessionOutcome: Int] = [:]
        var seconds: [SessionOutcome: TimeInterval] = [:]
        var unratedCount = 0

        var ratedCount: Int { counts.values.reduce(0, +) }
        func count(_ outcome: SessionOutcome) -> Int { counts[outcome] ?? 0 }
        func share(_ outcome: SessionOutcome) -> Double {
            ratedCount > 0 ? Double(count(outcome)) / Double(ratedCount) : 0
        }
        /// Shipped + moved forward, as a share of rated blocks.
        var realWorkShare: Double { share(.shipped) + share(.movedForward) }
    }

    struct ProjectOutcomeMix: Hashable, Sendable, Identifiable {
        let project: AnalyticsProjectKey
        let mix: OutcomeMix
        var id: String { project.id }
    }

    /// Outcome ratings for focus blocks that started inside `interval` (all time when `nil`).
    func outcomeMix(_ sessions: [FocusSample], in interval: DateInterval? = nil) -> OutcomeMix {
        var mix = OutcomeMix()
        for session in sessions where session.isFocus && (interval?.contains(session.start) ?? true) {
            if let outcome = session.outcome {
                mix.counts[outcome, default: 0] += 1
                mix.seconds[outcome, default: 0] += session.activeSeconds
            } else {
                mix.unratedCount += 1
            }
        }
        return mix
    }

    /// Per-project outcome mix (by the block's primary project), projects with ratings only.
    func outcomeMixByProject(_ sessions: [FocusSample], in interval: DateInterval? = nil) -> [ProjectOutcomeMix] {
        let grouped = Dictionary(grouping: sessions.filter { $0.isFocus && (interval?.contains($0.start) ?? true) }, by: \.project)
        return grouped
            .map { ProjectOutcomeMix(project: $0.key, mix: outcomeMix($0.value)) }
            .filter { $0.mix.ratedCount > 0 }
            .sorted { (lhs: ProjectOutcomeMix, rhs: ProjectOutcomeMix) -> Bool in
                lhs.mix.ratedCount == rhs.mix.ratedCount ? lhs.project < rhs.project : lhs.mix.ratedCount > rhs.mix.ratedCount
            }
    }
}
