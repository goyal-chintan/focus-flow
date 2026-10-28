import Foundation

/// Counts for one day's tasks (daily tasks design: docs/plans/2026-10-28-daily-tasks-design.md).
struct DailyTaskStats: Equatable, Sendable {
    let planned: Int
    let done: Int

    var remaining: Int { max(0, planned - done) }
    var fraction: Double { planned > 0 ? Double(done) / Double(planned) : 0 }
    var isComplete: Bool { planned > 0 && done >= planned }
    /// "3 of 5 done", "All 5 done", "No tasks yet".
    var label: String {
        if planned == 0 { return "No tasks yet" }
        if isComplete { return planned == 1 ? "Done" : "All \(planned) done" }
        return "\(done) of \(planned) done"
    }
}

/// One day of planned against done, for the week strip and the drift report.
struct DailyTaskDay: Equatable, Sendable, Identifiable {
    let day: Date
    let planned: Int
    let done: Int
    var id: Date { day }
}

/// Pure task logic; the view model and views feed it `DailyTask`s.
enum DailyTaskPlanner {
    /// How far back carry-over looks for the last planned day.
    static let carryOverLookbackDays = 7

    /// The day's tasks: open ones first in their order, then done ones in the order they were done.
    static func tasks(_ all: [DailyTask], on day: Date, calendar: Calendar = .current) -> [DailyTask] {
        let start = calendar.startOfDay(for: day)
        let todays = all.filter { calendar.isDate($0.day, inSameDayAs: start) }
        let open = todays.filter { !$0.isDone }.sorted { ($0.order, $0.createdAt) < ($1.order, $1.createdAt) }
        let done = todays.filter(\.isDone).sorted { ($0.doneAt ?? .distantPast) < ($1.doneAt ?? .distantPast) }
        return open + done
    }

    static func stats(_ all: [DailyTask], on day: Date, calendar: Calendar = .current) -> DailyTaskStats {
        let todays = tasks(all, on: day, calendar: calendar)
        return DailyTaskStats(planned: todays.count, done: todays.filter(\.isDone).count)
    }

    /// The next open task, preferring one for `projectID` when given.
    static func nextTask(_ all: [DailyTask], on day: Date, preferring projectID: UUID? = nil, calendar: Calendar = .current) -> DailyTask? {
        let open = tasks(all, on: day, calendar: calendar).filter { !$0.isDone }
        if let projectID, let match = open.first(where: { $0.projectID == projectID }) { return match }
        return open.first
    }

    /// Unfinished tasks from the most recent earlier day that had any tasks (within the lookback),
    /// minus those already carried to `today`.
    static func carryOverCandidates(_ all: [DailyTask], today: Date, calendar: Calendar = .current) -> [DailyTask] {
        let start = calendar.startOfDay(for: today)
        guard let earliest = calendar.date(byAdding: .day, value: -carryOverLookbackDays, to: start) else { return [] }
        let earlier = all.filter { $0.day < start && $0.day >= earliest }
        guard let lastDay = earlier.map({ calendar.startOfDay(for: $0.day) }).max() else { return [] }
        let carried = Set(all.filter { calendar.isDate($0.day, inSameDayAs: start) }.compactMap(\.carriedFromID))
        let titlesToday = Set(all.filter { calendar.isDate($0.day, inSameDayAs: start) }.map { $0.title.lowercased() })
        return tasks(earlier, on: lastDay, calendar: calendar)
            .filter { !$0.isDone && !carried.contains($0.id) && !titlesToday.contains($0.title.lowercased()) }
    }

    /// Planned against done for each of the `days` days ending today (oldest first).
    static func history(_ all: [DailyTask], endingOn today: Date, days: Int = 7, calendar: Calendar = .current) -> [DailyTaskDay] {
        let end = calendar.startOfDay(for: today)
        return (0..<days).reversed().compactMap { back in
            guard let day = calendar.date(byAdding: .day, value: -back, to: end) else { return nil }
            let s = stats(all, on: day, calendar: calendar)
            return DailyTaskDay(day: day, planned: s.planned, done: s.done)
        }
    }

    /// Done ÷ planned over days that had a plan (nil without any).
    static func completionRate(_ history: [DailyTaskDay]) -> Double? {
        let planned = history.reduce(0) { $0 + $1.planned }
        guard planned > 0 else { return nil }
        return Double(history.reduce(0) { $0 + $1.done }) / Double(planned)
    }

    /// "12 planned · 7 done · 58%" for the drift report (nil without a plan).
    static func weekSummary(_ history: [DailyTaskDay]) -> String? {
        guard let rate = completionRate(history) else { return nil }
        let planned = history.reduce(0) { $0 + $1.planned }
        let done = history.reduce(0) { $0 + $1.done }
        return "\(planned) planned · \(done) done · \(Int((rate * 100).rounded()))%"
    }

    /// Today's levers not yet on today's list (matched by key result), as one-tap suggestions.
    static func leverSuggestions(_ levers: [DailyLever], existing: [DailyTask], on day: Date, calendar: Calendar = .current) -> [DailyLever] {
        let todays = tasks(existing, on: day, calendar: calendar)
        let linked = Set(todays.compactMap(\.keyResultID))
        let titles = Set(todays.map { $0.title.lowercased() })
        return levers.filter { !linked.contains($0.id) && !titles.contains($0.action.lowercased()) }
    }
}
