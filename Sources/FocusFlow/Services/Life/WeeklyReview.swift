import Foundation

// Coach v8 §3.5 (docs/plans/2026-11-06-coach-v8-life-coach.md): a 5-minute weekly review on Sunday
// evening. Look back (the verdict and the days), pick one change, put next week's own-work blocks on
// the calendar, and name what's in the way. Monitoring with a written plan (Harkin et al., 2016),
// reflection (Di Stefano et al., 2016) and implementation intentions (Gollwitzer & Sheeran, 2006).
// Pure; the view model and `WeeklyReviewView` use it.

struct WeeklyReviewRecord: Codable, Equatable, Sendable {
    /// Monday of the week reviewed.
    var weekStart: Date
    var completedAt: Date
    var pickID: String?
    var pickTitle: String?
    var plannedBlocks: Int
    var obstacle: String
}

enum WeeklyReviewPolicy {
    /// Sunday 19:00 opens the review; it stays offered until Monday 12:00.
    static let openHour = 19
    static let closeHourMonday = 12
    /// A "Later" waits this long before the next offer.
    static let reofferAfter: TimeInterval = 3 * 3600

    /// The window the review is due in, if `now` is inside one: Sunday 19:00 – Monday 12:00.
    static func window(containing now: Date, calendar: Calendar = .current) -> DateInterval? {
        let weekday = calendar.component(.weekday, from: now)
        let hour = calendar.component(.hour, from: now)
        let today = calendar.startOfDay(for: now)
        let sunday: Date
        if weekday == 1 && hour >= openHour {
            sunday = today
        } else if weekday == 2 && hour < closeHourMonday {
            sunday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        } else {
            return nil
        }
        guard let start = calendar.date(bySettingHour: openHour, minute: 0, second: 0, of: sunday),
              let monday = calendar.date(byAdding: .day, value: 1, to: sunday),
              let end = calendar.date(bySettingHour: closeHourMonday, minute: 0, second: 0, of: monday) else { return nil }
        return DateInterval(start: start, end: end)
    }

    /// Monday of the week a review at `now` looks back on (the week ending on the latest Sunday).
    static func reviewedWeekStart(_ now: Date, calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: now)
        let weekday = calendar.component(.weekday, from: today)
        // Days back to the latest Sunday (today when Sunday), then 6 more to its Monday.
        let backToSunday = (weekday + 6) % 7
        return calendar.date(byAdding: .day, value: -(backToSunday + 6), to: today) ?? today
    }

    /// The 7 days a review plans: from tomorrow on Sunday, else from today.
    static func planDays(_ now: Date, calendar: Calendar = .current) -> [Date] {
        let today = calendar.startOfDay(for: now)
        let first = calendar.component(.weekday, from: now) == 1 ? (calendar.date(byAdding: .day, value: 1, to: today) ?? today) : today
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: first) }
    }

    static func isDue(now: Date, lastDone: Date?, lastOffered: Date?, calendar: Calendar = .current) -> Bool {
        guard let window = window(containing: now, calendar: calendar) else { return false }
        if let lastDone, lastDone >= window.start.addingTimeInterval(-12 * 3600) { return false }
        if let lastOffered, now.timeIntervalSince(lastOffered) < reofferAfter { return false }
        return true
    }

    /// Two anchors on workdays: Tuesday and Thursday, else the first two workdays offered.
    static func anchorDays(_ workdays: [Date], calendar: Calendar = .current) -> Set<Date> {
        let preferred = workdays.filter { [3, 5].contains(calendar.component(.weekday, from: $0)) }
        return Set((preferred.count == 2 ? preferred : Array(workdays.prefix(2))))
    }
}

/// Reviews in defaults (one a week; the last 52 are kept). The store is not touched.
struct WeeklyReviewStore {
    static let recordsKey = "focusflow.weeklyReview.records"
    static let offeredKey = "focusflow.weeklyReview.lastOffered"
    static let keep = 52

    let defaults: UserDefaults

    func records() -> [WeeklyReviewRecord] {
        guard let data = defaults.data(forKey: Self.recordsKey),
              let list = try? JSONDecoder().decode([WeeklyReviewRecord].self, from: data) else { return [] }
        return list.sorted { $0.completedAt < $1.completedAt }
    }

    var last: WeeklyReviewRecord? { records().last }

    func append(_ record: WeeklyReviewRecord) {
        let list = Array((records().filter { $0.weekStart != record.weekStart } + [record]).suffix(Self.keep))
        if let data = try? JSONEncoder().encode(list) { defaults.set(data, forKey: Self.recordsKey) }
    }

    var lastOffered: Date? { defaults.object(forKey: Self.offeredKey) as? Date }

    func markOffered(_ now: Date) { defaults.set(now, forKey: Self.offeredKey) }
}

/// "Plan today?" (§3.5): a day off with no plan yet, in the morning, after a week without plans.
enum PlanTodayPolicy {
    static let fromHour = 8
    static let untilHour = 13

    /// Start times to offer: your usual hour on days off, 14:00 and 18:00, each at least 20 min ahead.
    static func times(now: Date, usualHour: Int, calendar: Calendar = .current) -> [Date] {
        let hours = Array(Set([usualHour, 14, 18])).sorted()
        return hours.compactMap { calendar.date(bySettingHour: $0, minute: 0, second: 0, of: now) }
            .filter { $0.timeIntervalSince(now) >= 20 * 60 }
            .prefix(3)
            .map { $0 }
    }

    static func shouldAsk(type: DayType, now: Date, hasPlanToday: Bool, ownMinutesToday: Double, plannedDaysLastWeek: Int,
                          calendar: Calendar = .current) -> Bool {
        let hour = calendar.component(.hour, from: now)
        return [.weekend, .holiday, .leave].contains(type) && (fromHour..<untilHour).contains(hour)
            && !hasPlanToday && ownMinutesToday < 1 && plannedDaysLastWeek == 0
    }
}
