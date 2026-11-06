import Foundation

// Coach v8 §3.5 (docs/plans/2026-11-06-coach-v8-life-coach.md): an own-work target per day type.
// A type you have not set follows the daily goal (Goals tab), so nothing changes until you set one
// ("Set a leave target of 3h?" in Your week, or Settings → Focus). A sick day is rest unless you set it.

/// Your targets, in defaults. Small and per Mac, like the coach's other answers; the store is not touched.
struct DayTargetStore {
    static func key(_ type: DayType) -> String { "focusflow.dayTarget.\(type.rawValue)" }
    static let range = 0...600

    let defaults: UserDefaults

    /// Your number for `type`, or nil when it follows the daily goal.
    func minutes(for type: DayType) -> Int? {
        guard type != .workday, defaults.object(forKey: Self.key(type)) != nil else { return nil }
        return defaults.integer(forKey: Self.key(type))
    }

    /// nil goes back to following the daily goal. A workday always follows the Goals tab.
    func set(_ minutes: Int?, for type: DayType) {
        guard type != .workday else { return }
        if let minutes {
            defaults.set(min(Self.range.upperBound, max(Self.range.lowerBound, minutes)), forKey: Self.key(type))
        } else {
            defaults.removeObject(forKey: Self.key(type))
        }
    }

    var all: [DayType: Int] {
        Dictionary(uniqueKeysWithValues: DayType.allCases.compactMap { type in minutes(for: type).map { (type, $0) } })
    }
}

enum DayTargets {
    /// The day's own-work target in minutes: your number for the type, else the daily goal; a sick day rests.
    static func minutes(type: DayType, yours: Int?, goalMinutes: Int) -> Int {
        if let yours { return yours }
        return type == .sick ? 0 : goalMinutes
    }

    /// Whether the day type is sure enough to change today's goal. An inferred leave (0.6) waits
    /// for your answer to "On leave?"; a weekend, the calendar and your answer count.
    static func isSettled(_ classification: DayClassification) -> Bool {
        classification.source != .inferred || classification.confidence >= DayClassification.askBelow
    }

    /// "Leave 3h · Weekend follows your goal (2h 30m)".
    static func label(_ minutes: Int) -> String {
        guard minutes > 0 else { return "rest" }
        let h = minutes / 60, m = minutes % 60
        return h == 0 ? "\(m)m" : (m == 0 ? "\(h)h" : "\(h)h \(m)m")
    }
}

extension DailyGoal {
    /// The same goal sized for a day type's target (stretch keeps its distance above it).
    func sized(minutes: Int, for type: DayType) -> DailyGoal {
        let seconds = max(60, TimeInterval(minutes * 60))
        return DailyGoal(
            scope: scope,
            seconds: seconds,
            stretchSeconds: seconds + max(0, stretchSeconds - self.seconds),
            source: .dayType(type),
            targetSeconds: targetSeconds,
            fixedSeconds: fixedSeconds,
            followsTargets: followsTargets
        )
    }
}
