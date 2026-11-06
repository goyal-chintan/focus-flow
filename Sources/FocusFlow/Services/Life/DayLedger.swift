import Foundation

// Coach v8 §3.1 (docs/plans/2026-11-06-coach-v8-life-coach.md): what kind of day it was, whether
// own time was planned, and how it went. Pure; `TimerViewModel` feeds it from the store.

enum DayType: String, Codable, CaseIterable, Sendable {
    case workday, leave, weekend, holiday, sick

    var title: String {
        switch self {
        case .workday: "Workday"
        case .leave: "Leave"
        case .weekend: "Weekend"
        case .holiday: "Holiday"
        case .sick: "Sick day"
        }
    }

    /// "3 leave days", "1 weekend day".
    func count(_ n: Int) -> String {
        switch self {
        case .workday: "\(n) workday\(n == 1 ? "" : "s")"
        case .leave: "\(n) leave day\(n == 1 ? "" : "s")"
        case .weekend: "\(n) weekend day\(n == 1 ? "" : "s")"
        case .holiday: "\(n) holiday\(n == 1 ? "" : "s")"
        case .sick: "\(n) sick day\(n == 1 ? "" : "s")"
        }
    }

    /// Saturday and Sunday. One rule for the whole app: the en_IN locale counts only Sunday as
    /// the weekend, which made the coach's "weekend" disagree with Mon–Fri project targets.
    static func isWeekend(_ date: Date, calendar: Calendar = .current) -> Bool {
        let weekday = calendar.component(.weekday, from: date)
        return weekday == 1 || weekday == 7
    }

    /// Own-work minutes the day is judged against (v8 §6 defaults; phase 4 makes them editable).
    var defaultTargetMinutes: Int {
        switch self {
        case .workday: 90
        case .leave: 180
        case .weekend, .holiday: 120
        case .sick: 0
        }
    }
}

enum DayTypeSource: String, Codable, Sendable {
    case user, calendar, inferred
}

/// A calendar's say about a day: an out-of-office or leave event, or a public holiday.
enum CalendarDayMark: String, Codable, Sendable {
    case leave, holiday

    /// Words that mark an all-day event as time off.
    static let leaveWords = ["leave", "ooo", "out of office", "vacation", "pto", "time off", "day off", "holiday"]

    /// One event's mark, if any. `outOfOffice`: EventKit availability `.unavailable`.
    /// `coversHours`: how much of the working day it covers. `holidayCalendar`: the calendar's
    /// title says holidays (a subscribed public-holiday calendar).
    static func mark(title: String?, isAllDay: Bool, outOfOffice: Bool, coversHours: Double, holidayCalendar: Bool) -> CalendarDayMark? {
        if outOfOffice && (isAllDay || coversHours >= 4) { return .leave }
        let text = (title ?? "").lowercased()
        if holidayCalendar && isAllDay { return .holiday }
        if isAllDay && leaveWords.contains(where: { text.contains($0) }) {
            return text.contains("holiday") ? .holiday : .leave
        }
        return nil
    }
}

struct DayClassification: Equatable, Sendable {
    let type: DayType
    let source: DayTypeSource
    /// 0–1. Below `askBelow` on a weekday, the coach asks.
    let confidence: Double
    let reason: String

    static let askBelow = 0.75
}

/// The signals one day leaves behind.
struct DaySignals: Equatable, Sendable {
    var day: Date
    var userLabel: DayType?
    var calendarMark: CalendarDayMark?
    /// Office apps and calls plus blocks on work projects.
    var officeMinutes: Double
    /// Any recorded laptop activity (apps and blocks).
    var activeMinutes: Double
}

enum DayClassifier {
    /// Office-quiet weekdays are leave unless the office shows up.
    static let leaveBelowOfficeMinutes = 30.0
    static let workdayFromOfficeMinutes = 60.0
    /// Before this hour a quiet morning says nothing yet.
    static let decideAfterHour = 13

    static func classify(_ s: DaySignals, now: Date, calendar: Calendar = .current) -> DayClassification {
        if let label = s.userLabel {
            return DayClassification(type: label, source: .user, confidence: 1, reason: "You said so.")
        }
        if s.calendarMark == .leave {
            return DayClassification(type: .leave, source: .calendar, confidence: 0.9, reason: "Your calendar has you out of office.")
        }
        if DayType.isWeekend(s.day, calendar: calendar) {
            return DayClassification(type: .weekend, source: .inferred, confidence: 0.95, reason: "Saturday or Sunday.")
        }
        if s.calendarMark == .holiday, s.officeMinutes < workdayFromOfficeMinutes {
            return DayClassification(type: .holiday, source: .calendar, confidence: 0.8, reason: "A public holiday on your calendar.")
        }
        let isToday = calendar.isDate(s.day, inSameDayAs: now)
        if s.officeMinutes >= workdayFromOfficeMinutes {
            return DayClassification(type: .workday, source: .inferred, confidence: 0.9, reason: "\(Int(s.officeMinutes)) min of office apps and calls.")
        }
        if isToday, calendar.component(.hour, from: now) < decideAfterHour {
            return DayClassification(type: .workday, source: .inferred, confidence: 0.4, reason: "Too early to tell.")
        }
        if s.activeMinutes < 30 {
            return DayClassification(type: .workday, source: .inferred, confidence: 0.3, reason: "Hardly any laptop activity recorded.")
        }
        if s.officeMinutes < leaveBelowOfficeMinutes {
            return DayClassification(type: .leave, source: .inferred, confidence: 0.6,
                                     reason: "No Slack, calls or office tools (\(Int(s.officeMinutes)) min) on a weekday.")
        }
        return DayClassification(type: .workday, source: .inferred, confidence: 0.5, reason: "Light office activity (\(Int(s.officeMinutes)) min).")
    }
}

/// Which activity is office work. Phase 1 uses names; phase 2 learns per-project app roles.
enum OfficeActivity {
    static let needles = [
        "slack", "zoom", "teams", "webex", "meet.google", "atlassian", "jira", "confluence",
        "outlook", "com.microsoft.outlook", "gotomeeting",
    ]

    static func isOffice(key: String) -> Bool {
        let text = key.lowercased()
        return text == "call" || needles.contains { text.contains($0) }
    }
}

enum DayVerdict: String, Equatable, Sendable {
    case plannedDone, plannedMissed, unplannedDid, unplannedLost, rest, open

    var title: String {
        switch self {
        case .plannedDone: "Planned & done"
        case .plannedMissed: "Planned, missed"
        case .unplannedDid: "Unplanned but did"
        case .unplannedLost: "Unplanned & lost"
        case .rest: "Rest"
        case .open: "In progress"
        }
    }

    /// "Did" means at least half the day type's own-work target, and at least 25 min.
    /// Own-work minutes that make a day count as "did".
    static func didMinutes(targetMinutes: Int) -> Double { max(25, Double(targetMinutes) / 2) }

    static func of(planned: Bool, ownMinutes: Double, targetMinutes: Int, isPast: Bool) -> DayVerdict {
        guard targetMinutes > 0 else { return .rest }
        let did = ownMinutes >= didMinutes(targetMinutes: targetMinutes)
        if !isPast && !did { return .open }
        switch (planned, did) {
        case (true, true): return .plannedDone
        case (true, false): return .plannedMissed
        case (false, true): return .unplannedDid
        case (false, false): return .unplannedLost
        }
    }
}

/// One day of the ledger.
struct DayEntry: Equatable, Sendable, Identifiable {
    let day: Date
    let classification: DayClassification
    let planned: Bool
    let ownMinutes: Double
    let officeMinutes: Double
    let callMinutes: Double?
    let awayMinutes: Double?
    let derailMinutes: Double
    let targetMinutes: Int
    let verdict: DayVerdict

    var id: Date { day }
    var type: DayType { classification.type }
}

/// The days' story in one sentence (Insights, until phase 3's Your week page).
enum DayLedgerSummary {
    static func sentence(_ days: [DayEntry]) -> String? {
        let past = days.filter { $0.verdict != .open }
        guard past.count >= 5 else { return nil }
        let counts = Dictionary(grouping: past, by: \.type).mapValues(\.count)
        let mix = DayType.allCases.compactMap { type in counts[type].map { type.count($0) } }.joined(separator: ", ")
        let free = past.filter { $0.type != .workday && $0.type != .sick }
        let lost = free.filter { $0.verdict == .unplannedLost }.count
        let planned = free.filter(\.planned).count
        var text = "Last \(past.count) days: \(mix)."
        if !free.isEmpty {
            text += " Of \(free.count) days off, \(planned) had a plan and \(lost) went unplanned with little own work."
        }
        return text
    }
}
