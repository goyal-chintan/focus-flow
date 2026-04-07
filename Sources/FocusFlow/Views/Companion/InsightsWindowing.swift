import Foundation

enum InsightsWindowing {
    static func trailing7DayInterval(relativeTo now: Date, calendar: Calendar) -> DateInterval? {
        CompanionAnalyticsWindow.trailing7Days.dateInterval(relativeTo: now, calendar: calendar)
    }

    static func previousInterval(before interval: DateInterval, calendar: Calendar) -> DateInterval? {
        guard let previousStart = calendar.date(byAdding: .day, value: -7, to: interval.start) else {
            return nil
        }
        return DateInterval(start: previousStart, end: interval.start)
    }

    static func overlappingFocusSessions(_ sessions: [FocusSession], in interval: DateInterval) -> [FocusSession] {
        sessions.filter { $0.type == .focus && overlaps($0, with: interval) }
    }

    static func completionRate(for sessions: [FocusSession], in interval: DateInterval) -> Double {
        let overlappingSessions = overlappingFocusSessions(sessions, in: interval)
        guard !overlappingSessions.isEmpty else { return 0 }
        let completedSessions = overlappingSessions.filter(\.completed).count
        return Double(completedSessions) / Double(overlappingSessions.count)
    }

    static func overlaps(_ session: FocusSession, with interval: DateInterval) -> Bool {
        let sessionEnd = endDate(for: session)
        return sessionEnd > interval.start && session.startedAt < interval.end
    }

    static func endDate(for session: FocusSession) -> Date {
        let fallbackEnd = session.startedAt.addingTimeInterval(max(session.actualDuration, 0))
        let resolvedEnd = session.endedAt ?? fallbackEnd
        return max(resolvedEnd, session.startedAt)
    }
}
