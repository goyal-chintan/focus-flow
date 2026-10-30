import Foundation

// Coach audit 2026-10-30: the learned availability model learned office hours, because that is
// when the user worked. Own-work time is a decision the user makes, so the user declares it
// (Settings → Coach → Own-work windows). Inside a declared window the coach decides; outside it
// creates no decision points. With no windows declared, the learned model stays in charge.

/// A daily own-work window, e.g. 07:00–09:00. Minutes after midnight; `end` is exclusive and
/// never wraps past midnight.
struct CoachOwnWorkWindow: Equatable, Hashable, Sendable, Identifiable {
    var startMinute: Int
    var endMinute: Int
    var id: Int { startMinute * 10_000 + endMinute }

    init(startMinute: Int, endMinute: Int) {
        self.startMinute = max(0, min(startMinute, 24 * 60 - 1))
        self.endMinute = max(self.startMinute + 1, min(endMinute, 24 * 60))
    }

    var durationMinutes: Int { endMinute - startMinute }

    /// The window on `date`'s day.
    func interval(on date: Date, calendar: Calendar = .current) -> DateInterval {
        let day = calendar.startOfDay(for: date)
        let start = calendar.date(byAdding: .minute, value: startMinute, to: day) ?? day
        let end = calendar.date(byAdding: .minute, value: endMinute, to: day) ?? start
        return DateInterval(start: start, end: max(start, end))
    }

    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        let interval = interval(on: date, calendar: calendar)
        return date >= interval.start && date < interval.end
    }

    /// "07:00–09:00".
    var label: String {
        "\(Self.clock(startMinute))–\(Self.clock(endMinute))"
    }

    static func clock(_ minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60, minute % 60)
    }
}

enum CoachOwnWorkWindows {
    static let maxWindows = 4
    /// The guaranteed prompt waits for the window's last half hour (half the window if shorter),
    /// so the randomised decisions before it keep their quiet control group.
    static let lastCallMinutes = 30
    /// Interrupting prompts per day, whatever the setting says (coach audit 2026-10-30).
    static let dailyCap = 3

    /// "420-540,1200-1320" → windows, sorted, overlaps dropped.
    static func parse(_ raw: String?) -> [CoachOwnWorkWindow] {
        guard let raw, !raw.isEmpty else { return [] }
        let windows = raw.split(separator: ",").compactMap { part -> CoachOwnWorkWindow? in
            let bounds = part.split(separator: "-").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            guard bounds.count == 2, bounds[1] > bounds[0] else { return nil }
            return CoachOwnWorkWindow(startMinute: bounds[0], endMinute: bounds[1])
        }
        return normalized(windows)
    }

    static func encode(_ windows: [CoachOwnWorkWindow]) -> String? {
        let kept = normalized(windows)
        guard !kept.isEmpty else { return nil }
        return kept.map { "\($0.startMinute)-\($0.endMinute)" }.joined(separator: ",")
    }

    /// Sorted by start; a window that overlaps an earlier one is dropped; at most `maxWindows`.
    static func normalized(_ windows: [CoachOwnWorkWindow]) -> [CoachOwnWorkWindow] {
        var result: [CoachOwnWorkWindow] = []
        for window in windows.sorted(by: { $0.startMinute < $1.startMinute })
        where result.last.map({ window.startMinute >= $0.endMinute }) ?? true {
            result.append(window)
        }
        return Array(result.prefix(maxWindows))
    }

    /// Today's window that contains `now`.
    static func current(_ windows: [CoachOwnWorkWindow], now: Date, calendar: Calendar = .current) -> DateInterval? {
        windows.first { $0.contains(now, calendar: calendar) }?.interval(on: now, calendar: calendar)
    }

    /// Windows later today that have not begun: each may still need its guaranteed prompt.
    static func laterToday(_ windows: [CoachOwnWorkWindow], now: Date, calendar: Calendar = .current) -> Int {
        windows.filter { $0.interval(on: now, calendar: calendar).start > now }.count
    }

    /// In the window's last call: its final 30 minutes (or final half, if shorter).
    static func isLastCall(_ window: DateInterval, now: Date) -> Bool {
        let lead = min(TimeInterval(lastCallMinutes * 60), window.duration / 2)
        return now >= window.end.addingTimeInterval(-lead) && now < window.end
    }

    /// The window owes its one interrupting prompt: last call, no block started in it yet,
    /// nothing has interrupted in it yet, and today's goal isn't met.
    static func owesPrompt(window: DateInterval?, now: Date, startedInWindow: Bool, promptsInWindow: Int, goalMet: Bool) -> Bool {
        guard let window, isLastCall(window, now: now) else { return false }
        return !startedInWindow && promptsInWindow == 0 && !goalMet
    }

    /// Daily cap for a prompt the coach chose (not a window's guaranteed one): the setting,
    /// never above 3, minus one slot held for each declared window still to come today.
    static func cap(setting: Int, windows: [CoachOwnWorkWindow], now: Date, guaranteed: Bool, calendar: Calendar = .current) -> Int {
        let cap = min(max(setting, 1), dailyCap)
        guard !guaranteed else { return cap }
        return max(0, cap - laterToday(windows, now: now, calendar: calendar))
    }
}
