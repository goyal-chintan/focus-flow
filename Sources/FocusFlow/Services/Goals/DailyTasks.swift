import Foundation

/// Counts for one day's tasks (daily tasks design: docs/plans/2026-10-28-daily-tasks-design.md).
struct DailyTaskStats: Equatable, Sendable {
    let planned: Int
    let done: Int

    var remaining: Int { max(0, planned - done) }
    var fraction: Double { planned > 0 ? Double(done) / Double(planned) : 0 }
    var isComplete: Bool { planned > 0 && done >= planned }
    /// "3 of 5 done", "All 5 done", "1 of 1 done", "No tasks yet". Never a bare "Done": it reads
    /// as "your day is done" next to a time goal that is not.
    var label: String {
        if planned == 0 { return "No tasks yet" }
        if isComplete, planned > 1 { return "All \(planned) done" }
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
        // A synced task the Reminders sync already brought into today is not carried twice.
        let remindersToday = Set(all.filter { calendar.isDate($0.day, inSameDayAs: start) }.compactMap(\.reminderID))
        return tasks(earlier, on: lastDay, calendar: calendar)
            .filter { !$0.isDone && !carried.contains($0.id) && !titlesToday.contains($0.title.lowercased()) }
            .filter { $0.reminderID.map { !remindersToday.contains($0) } ?? true }
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

    /// One truth per key result (clarity fixes §4): a task for it today *is* today's commitment.
    /// A done task drops the lever (the commitment is met, even if the pace has since risen); an
    /// open task replaces the lever's text, a counted one with its counter ("Problems solved: 1 of 3 today").
    static func reconcile(_ levers: [DailyLever], with tasks: [DailyTask], on day: Date, calendar: Calendar = .current) -> [DailyLever] {
        let todays = self.tasks(tasks, on: day, calendar: calendar).filter { $0.keyResultID != nil }
        return levers.compactMap { lever in
            let linked = todays.filter { $0.keyResultID == lever.id }
            guard !linked.isEmpty else { return lever }
            guard let open = linked.first(where: { !$0.isDone }) else { return nil }
            var adjusted = lever
            if open.isCounted {
                adjusted.action = "\(open.title): \(DailyTaskReceipt.number(open.loggedCount)) of \(DailyTaskReceipt.number(open.progressAmount)) today"
                adjusted.amount = max(1, open.progressAmount - open.loggedCount)
            } else {
                adjusted.action = open.title
            }
            return adjusted
        }
    }

    /// Today's levers not yet on today's list (matched by key result), as one-tap suggestions.
    static func leverSuggestions(_ levers: [DailyLever], existing: [DailyTask], on day: Date, calendar: Calendar = .current) -> [DailyLever] {
        let todays = tasks(existing, on: day, calendar: calendar)
        let linked = Set(todays.compactMap(\.keyResultID))
        let titles = Set(todays.map { $0.title.lowercased() })
        return levers.filter { !linked.contains($0.id) && !titles.contains($0.action.lowercased()) }
    }
}

/// What a tick or a +1 just logged, shown for a few seconds with Undo, so a tap is never silent
/// (clarity design: docs/plans/2026-10-28-clarity-fixes.md).
struct DailyTaskReceipt: Equatable, Identifiable, Sendable {
    enum Undo: Equatable, Sendable { case reopen, markDone, stepDown, stepUp }
    enum Change: Sendable { case done, reopened, added, removed }

    static let visibleSeconds: Double = 6

    let id = UUID()
    let taskID: UUID
    let text: String
    let undo: Undo
    let at: Date

    /// "+1 Problems solved · today 2 of 3 · goal 12 of 40". Unlinked: "Done: Review notes".
    static func text(change: Change, taskTitle: String, resultTitle: String?, amount: Double,
                     logged: Double, of target: Double, goalDone: Double?, goalTarget: Double?) -> String {
        let goal = goalDone.flatMap { done in goalTarget.map { "goal \(number(done)) of \(number($0))" } }
        guard let resultTitle else {
            return change == .reopened ? "Not done: \(taskTitle)" : "Done: \(taskTitle)"
        }
        switch change {
        case .added:
            let today = logged >= target ? "today's \(number(target)) done" : "today \(number(logged)) of \(number(target))"
            return ["+\(number(amount)) \(resultTitle)", today, goal].compactMap { $0 }.joined(separator: " · ")
        case .removed:
            return ["−\(number(amount)) \(resultTitle)", "today \(number(logged)) of \(number(target))", goal].compactMap { $0 }.joined(separator: " · ")
        case .done:
            guard amount > 0 else { return "Done: \(taskTitle)" }
            return ["Done · +\(number(amount)) \(resultTitle)", goal].compactMap { $0 }.joined(separator: " · ")
        case .reopened:
            guard amount > 0 else { return "Not done: \(taskTitle)" }
            return ["Not done · −\(number(amount)) \(resultTitle)", goal].compactMap { $0 }.joined(separator: " · ")
        }
    }

    /// "3", "2.5".
    static func number(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }
}
