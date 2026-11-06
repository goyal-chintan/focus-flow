import Foundation

// Coach v8 phase 5 (docs/plans/2026-11-06-coach-v8-life-coach.md §3.6): one job per surface.
// The popover starts and controls a block, the notch shows the timer and one next action, Today
// says where the day stands in one sentence, and the daily target lives in Settings → Focus.
// Pure rules the views share, so they are unit-tested.

enum CalmSurfaces {
    // MARK: Today's one sentence

    /// "1h 43m of 2h 30m · on pace · leave day". The pace is said once; a workday is not named.
    static func todaySentence(
        doneSeconds: TimeInterval,
        goal: DailyGoal,
        pace: CoachGoalPacing.Tier?,
        dayType: DayType?,
        format: (TimeInterval) -> String
    ) -> String {
        if dayType == .sick || goal.source == .dayType(.sick) {
            return doneSeconds >= 60 ? "Sick day · rest · \(format(doneSeconds)) logged" : "Sick day · rest"
        }
        var parts: [String] = []
        let met = goal.seconds > 0 && doneSeconds >= goal.seconds
        if met {
            parts.append("\(format(doneSeconds)) · goal of \(format(goal.seconds)) met")
        } else {
            parts.append("\(format(doneSeconds)) of \(format(goal.seconds))")
            if let phrase = pace.flatMap(paceWord) { parts.append(phrase) }
        }
        if let day = dayType.flatMap(dayWord) { parts.append(day) }
        return parts.joined(separator: " · ")
    }

    static func paceWord(_ tier: CoachGoalPacing.Tier) -> String? {
        switch tier {
        case .goalMet: nil
        case .onTrack: "on pace"
        case .nudge: "on pace if you start soon"
        case .atRisk: "behind pace"
        case .unknown: nil
        }
    }

    static func dayWord(_ type: DayType) -> String? {
        switch type {
        case .workday: nil
        case .leave: "leave day"
        case .weekend: "weekend"
        case .holiday: "holiday"
        case .sick: "sick day"
        }
    }

    // MARK: Notch: one next action

    enum NotchNext: Equatable {
        /// The task line: the task to tick (or today's task count).
        case task
        /// Today's lever ("3 LeetCode questions").
        case lever
        /// The running block's key result +1.
        case result
        case none
    }

    /// The lever or the task, never both. A task you planned wins over the lever (it is more
    /// concrete); in a block, the block's own task wins over the key result's +1.
    static func notchNext(inBlock: Bool, hasTask: Bool, tasksPlanned: Int, hasLever: Bool, hasResult: Bool) -> NotchNext {
        if hasTask { return .task }
        if inBlock {
            if hasResult { return .result }
            return tasksPlanned > 0 ? .task : .none
        }
        if hasLever { return .lever }
        return tasksPlanned > 0 ? .task : .none
    }

    /// The block's intent beside the timer, unless it only repeats the task shown under it.
    static func notchIntent(_ intent: String?, taskTitle: String?) -> String? {
        guard let intent = intent?.trimmingCharacters(in: .whitespacesAndNewlines), !intent.isEmpty else { return nil }
        if let taskTitle, taskTitle.caseInsensitiveCompare(intent) == .orderedSame { return nil }
        return intent
    }

    // MARK: Settings → Focus: own-work target by day type

    struct TargetRow: Equatable, Identifiable {
        let type: DayType
        /// Your number; nil follows the daily goal (a sick day: rest).
        let yours: Int?
        /// What the day is judged by now.
        let effective: Int
        /// "Follows your goal (2h 30m)", "Rest", "3h".
        let caption: String

        var id: DayType { type }
        var followsGoal: Bool { yours == nil }
    }

    /// The day types you can set (a workday follows the Goals rules above it).
    static let settableTypes: [DayType] = [.leave, .weekend, .holiday, .sick]

    static func targetRows(yours: [DayType: Int], goalMinutes: Int) -> [TargetRow] {
        settableTypes.map { type in
            let own = yours[type]
            let effective = DayTargets.minutes(type: type, yours: own, goalMinutes: goalMinutes)
            let caption: String
            if own != nil {
                caption = DayTargets.label(effective)
            } else if type == .sick {
                caption = "Rest"
            } else {
                caption = "Follows your goal (\(DayTargets.label(goalMinutes)))"
            }
            return TargetRow(type: type, yours: own, effective: effective, caption: caption)
        }
    }

    /// The value to store when "Own number" is switched on or off: on starts from what the day is
    /// judged by now (a sick day from 30 min, so rest is never stored by accident).
    static func toggledTarget(_ row: TargetRow, ownNumber: Bool) -> Int? {
        guard ownNumber else { return nil }
        if let yours = row.yours { return yours }
        return row.type == .sick ? 30 : row.effective
    }

}
