import Foundation

// When the user actually focuses: a 7×24 hour-of-week matrix and the best windows derived from it.
// This is the same signal the coach's availability model learns from (Coach v2 §3, §8).

extension FocusAnalytics {
    struct HourOfWeekMatrix: Hashable, Sendable {
        /// Focus minutes per [weekday][hour], Monday-first (0 = Mon … 6 = Sun), summed over the range.
        let minutes: [[Double]]
        /// Number of distinct weeks with at least one block starting in [weekday][hour].
        let startWeeks: [[Int]]
        /// Weeks the averages are taken over (≥ 1; starts at the first week with data).
        let weeksObserved: Int

        static let empty = HourOfWeekMatrix(
            minutes: Array(repeating: Array(repeating: 0, count: 24), count: 7),
            startWeeks: Array(repeating: Array(repeating: 0, count: 24), count: 7),
            weeksObserved: 1
        )

        /// Average focus minutes per week in this bucket.
        func averageMinutes(weekday: Int, hour: Int) -> Double {
            minutes[weekday][hour] / Double(max(1, weeksObserved))
        }

        /// Share of observed weeks with a block starting in this bucket (0…1).
        func startRate(weekday: Int, hour: Int) -> Double {
            Double(startWeeks[weekday][hour]) / Double(max(1, weeksObserved))
        }

        var maxAverageMinutes: Double {
            (0..<7).flatMap { day in (0..<24).map { averageMinutes(weekday: day, hour: $0) } }.max() ?? 0
        }

        var totalMinutes: Double { minutes.joined().reduce(0, +) }
        var isEmpty: Bool { totalMinutes <= 0 }
    }

    /// Builds the hour-of-week matrix over the `weeks` calendar weeks ending with the week containing `now`.
    func hourOfWeek(_ sessions: [FocusSample], weeks: Int = 8, now: Date) -> HourOfWeekMatrix {
        let currentWeek = weekInterval(containing: now)
        let rangeStart = calendar.date(byAdding: .weekOfYear, value: -(max(1, weeks) - 1), to: currentWeek.start) ?? currentWeek.start
        let range = DateInterval(start: rangeStart, end: max(rangeStart, now))
        let focus = sessions.filter { $0.isFocus && $0.activeSeconds > 0 && $0.overlap(with: range) > 0 }
        guard let firstStart = focus.map({ max($0.start, range.start) }).min() else { return .empty }

        var minutes = Array(repeating: Array(repeating: 0.0, count: 24), count: 7)
        var startWeekSets = Array(repeating: Array(repeating: Set<Date>(), count: 24), count: 7)

        for session in focus {
            var cursor = max(session.start, range.start)
            let end = min(session.end, range.end)
            while cursor < end {
                let hourEnd = calendar.dateInterval(of: .hour, for: cursor)?.end ?? cursor.addingTimeInterval(3600)
                let segmentEnd = min(end, hourEnd)
                let day = mondayFirstWeekdayIndex(of: cursor)
                let hour = calendar.component(.hour, from: cursor)
                minutes[day][hour] += segmentEnd.timeIntervalSince(cursor) / 60
                cursor = segmentEnd
            }
            if range.contains(session.start) {
                let day = mondayFirstWeekdayIndex(of: session.start)
                let hour = calendar.component(.hour, from: session.start)
                startWeekSets[day][hour].insert(weekInterval(containing: session.start).start)
            }
        }

        let firstWeek = weekInterval(containing: firstStart).start
        let weeksObserved = (calendar.dateComponents([.weekOfYear], from: firstWeek, to: currentWeek.start).weekOfYear ?? 0) + 1

        return HourOfWeekMatrix(
            minutes: minutes,
            startWeeks: startWeekSets.map { $0.map(\.count) },
            weeksObserved: max(1, weeksObserved)
        )
    }

    // MARK: - Best windows

    enum DayScope: String, Hashable, Sendable {
        case weekdays
        case weekends
        case everyDay

        var label: String {
            switch self {
            case .weekdays: "weekdays"
            case .weekends: "weekends"
            case .everyDay: "daily"
            }
        }

        func includes(weekdayIndex: Int) -> Bool {
            switch self {
            case .weekdays: weekdayIndex < 5
            case .weekends: weekdayIndex >= 5
            case .everyDay: true
            }
        }
    }

    struct FocusWindow: Hashable, Sendable, Identifiable {
        /// First hour of the window (0…23).
        let startHour: Int
        /// Number of whole hours; the window may wrap past midnight.
        let hourCount: Int
        /// Average focus minutes per week inside the window.
        let averageMinutesPerWeek: Double
        let dayScope: DayScope

        var id: Int { startHour }
        var endHour: Int { (startHour + hourCount) % 24 }

        /// "11–12", "22–00".
        var label: String { String(format: "%02d–%02d", startHour, endHour) }
        /// "11:00–12:00".
        var longLabel: String { String(format: "%02d:00–%02d:00", startHour, endHour) }

        func contains(hour: Int) -> Bool {
            (0..<hourCount).contains { (startHour + $0) % 24 == hour }
        }
    }

    /// Top contiguous hour ranges by focus minutes. An hour qualifies when it holds at least
    /// `threshold` of the busiest hour's minutes; adjacent qualifying hours (wrapping midnight) merge.
    func bestWindows(_ matrix: HourOfWeekMatrix, limit: Int = 3, threshold: Double = 0.35, minimumMinutesPerWeek: Double = 10) -> [FocusWindow] {
        let perHour = (0..<24).map { hour in (0..<7).reduce(0.0) { $0 + matrix.averageMinutes(weekday: $1, hour: hour) } }
        guard let peak = perHour.max(), peak >= minimumMinutesPerWeek else { return [] }
        let cutoff = max(peak * threshold, minimumMinutesPerWeek)
        let qualifies = perHour.map { $0 >= cutoff }

        var runs: [[Int]] = []
        if qualifies.allSatisfy({ $0 }) {
            runs = [Array(0..<24)]
        } else {
            // Start walking just after a non-qualifying hour so a run spanning midnight stays whole.
            let anchor = qualifies.firstIndex(of: false) ?? 0
            var current: [Int] = []
            for step in 1...24 {
                let hour = (anchor + step) % 24
                if qualifies[hour] {
                    current.append(hour)
                } else if !current.isEmpty {
                    runs.append(current)
                    current = []
                }
            }
            if !current.isEmpty { runs.append(current) }
        }

        let windows = runs.map { hours -> FocusWindow in
            let total = hours.reduce(0.0) { $0 + perHour[$1] }
            let weekday = hours.reduce(0.0) { sum, hour in sum + (0..<5).reduce(0.0) { $0 + matrix.averageMinutes(weekday: $1, hour: hour) } }
            let weekdayShare = total > 0 ? weekday / total : 0
            let scope: DayScope = weekdayShare >= 0.85 ? .weekdays : (weekdayShare <= 0.15 ? .weekends : .everyDay)
            return FocusWindow(startHour: hours[0], hourCount: hours.count, averageMinutesPerWeek: total, dayScope: scope)
        }

        return Array(
            windows
                .sorted { (lhs: FocusWindow, rhs: FocusWindow) -> Bool in
                    lhs.averageMinutesPerWeek == rhs.averageMinutesPerWeek ? lhs.startHour < rhs.startHour : lhs.averageMinutesPerWeek > rhs.averageMinutesPerWeek
                }
                .prefix(max(0, limit))
        )
    }

    /// "weekdays 11–12, 22–00" style summary for a set of windows, in clock order.
    static func windowsSummary(_ windows: [FocusWindow]) -> String {
        let ordered = windows.sorted { $0.startHour < $1.startHour }
        let scopes = Set(ordered.map(\.dayScope))
        if scopes.count == 1, let scope = scopes.first, scope != .everyDay {
            return "\(scope.label) " + ordered.map(\.label).joined(separator: ", ")
        }
        return ordered.map { $0.dayScope == .everyDay ? $0.label : "\($0.label) (\($0.dayScope.label))" }.joined(separator: ", ")
    }

    struct NextWindow: Hashable, Sendable {
        let window: FocusWindow
        let start: Date
        /// `now` is already inside the window.
        let isNow: Bool
    }

    /// The next occurrence of any best window at or after `now` (honouring weekday/weekend scope).
    func nextWindow(_ windows: [FocusWindow], after now: Date) -> NextWindow? {
        let today = calendar.startOfDay(for: now)
        var best: NextWindow?
        for window in windows {
            for dayOffset in -1...7 {
                guard let day = calendar.date(byAdding: .day, value: dayOffset, to: today),
                      window.dayScope.includes(weekdayIndex: mondayFirstWeekdayIndex(of: day)),
                      let start = calendar.date(bySettingHour: window.startHour, minute: 0, second: 0, of: day),
                      let end = calendar.date(byAdding: .hour, value: window.hourCount, to: start),
                      end > now else { continue }
                let candidate = NextWindow(window: window, start: start, isNow: start <= now)
                if let current = best {
                    if candidate.isNow != current.isNow {
                        if candidate.isNow { best = candidate }
                    } else if candidate.start < current.start {
                        best = candidate
                    }
                } else {
                    best = candidate
                }
                break
            }
        }
        return best
    }
}
