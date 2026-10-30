import Foundation
import SwiftData

/// Reads the coach's inputs from SwiftData: past sessions, active days, weekly priorities,
/// streaks and confirmed derailers. Every fetch tolerates a container without the Coach v2
/// models (older test fixtures), returning empty results instead of failing.
@MainActor
struct CoachHistoryReader {
    static let lookbackDays = 120
    static let minimumSessionSeconds: TimeInterval = 5 * 60
    static let minimumDerailerMinutes = 20

    let modelContext: ModelContext
    var calendar: Calendar = .current

    func hasEntity(named name: String) -> Bool {
        modelContext.container.schema.entities.contains { $0.name == name }
    }

    // MARK: Priorities and goals (priorities-goals design §3.5)

    /// Ranked, active projects: #1 first.
    func rankedProjects() -> [Project] {
        let descriptor = FetchDescriptor<Project>(predicate: #Predicate { !$0.archived })
        return ((try? modelContext.fetch(descriptor)) ?? [])
            .filter { $0.priorityRank != nil }
            .sorted { ($0.priorityRank ?? .max) < ($1.priorityRank ?? .max) }
    }

    /// Own-work seconds today (personal and learning projects), or nil when no project is marked
    /// Work, in which case all focus counts.
    /// Today's seconds inside the goal's scope (★ #1 project, else own work); nil when every block counts.
    func goalScopeSecondsToday(now: Date) -> TimeInterval? {
        let projects = (try? modelContext.fetch(FetchDescriptor<Project>())) ?? []
        guard let keys = GoalDataBuilder.goalScope(projects).keys else { return nil }
        let start = calendar.startOfDay(for: now)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
        let samples = focusSessions(since: start.addingTimeInterval(-12 * 3600)).map(FocusSample.init)
        let seconds = GoalDataBuilder.seconds(samples: samples, in: DateInterval(start: start, end: end))
        return seconds.filter { keys.contains($0.key) }.values.reduce(0, +)
    }

    /// Active goals (empty on stores without the goal entities).
    func activeGoals() -> [ProjectGoal] {
        guard hasEntity(named: "ProjectGoal") else { return [] }
        let active = GoalStatus.active.rawValue
        let descriptor = FetchDescriptor<ProjectGoal>(predicate: #Predicate { $0.statusRaw == active })
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    // MARK: Sessions

    /// Finished or running focus sessions that started on or after `date`.
    func focusSessions(since date: Date) -> [FocusSession] {
        let descriptor = FetchDescriptor<FocusSession>(
            predicate: #Predicate { $0.startedAt >= date },
            sortBy: [SortDescriptor(\.startedAt)]
        )
        let sessions = (try? modelContext.fetch(descriptor)) ?? []
        return sessions.filter { session in
            guard session.type == .focus else { return false }
            if session.endedAt == nil || session.actualDuration >= Self.minimumSessionSeconds { return true }
            // A completed starter block (2–10 min) counts: declining "keep going" is still a win.
            return session.completed && CoachStarterBlock.isStarter(customLabel: session.customLabel, hasProject: session.project != nil)
        }
    }

    /// Inputs for `CoachAvailabilityModel`.
    func availabilityInputs(now: Date) -> (sessions: [CoachAvailabilityModel.Session], activeDays: [Date]) {
        let since = calendar.date(byAdding: .day, value: -Self.lookbackDays, to: calendar.startOfDay(for: now)) ?? now
        let sessions = focusSessions(since: since)
            .filter { $0.endedAt != nil }
            .map { CoachAvailabilityModel.Session(start: $0.startedAt, end: $0.effectiveEnd) }
        let entryDescriptor = FetchDescriptor<AppUsageEntry>(predicate: #Predicate { $0.date >= since })
        let activeDays = Set(((try? modelContext.fetch(entryDescriptor)) ?? []).map { calendar.startOfDay(for: $0.date) })
        return (sessions, Array(activeDays))
    }

    func lastFocusSessionEnd(before now: Date) -> Date? {
        var descriptor = FetchDescriptor<FocusSession>(
            predicate: #Predicate { $0.endedAt != nil },
            sortBy: [SortDescriptor(\.endedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 20
        let sessions = (try? modelContext.fetch(descriptor)) ?? []
        return sessions.first { $0.type == .focus && ($0.endedAt ?? .distantFuture) <= now }?.endedAt
    }

    /// The user's most recent intent for a project (prefill and "You said: …").
    func lastIntent(projectID: UUID?) -> String? {
        var descriptor = FetchDescriptor<FocusSession>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
        descriptor.fetchLimit = 200
        let sessions = (try? modelContext.fetch(descriptor)) ?? []
        return sessions.first { session in
            session.project?.id == projectID
                && !(session.intentText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        }?.intentText
    }

    // MARK: Streak

    /// Days before `now`'s day, counting back, that each had a focus block.
    func streakDays(now: Date) -> (streak: Int, missedYesterday: Bool, hasHistory: Bool) {
        let today = calendar.startOfDay(for: now)
        let since = calendar.date(byAdding: .day, value: -Self.lookbackDays, to: today) ?? today
        let days = Set(focusSessions(since: since).map { calendar.startOfDay(for: $0.startedAt) })
        return Self.streak(daysWithSessions: days, today: today, calendar: calendar)
    }

    static func streak(daysWithSessions: Set<Date>, today: Date, calendar: Calendar) -> (streak: Int, missedYesterday: Bool, hasHistory: Bool) {
        var streak = 0
        var day = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        while daysWithSessions.contains(day) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let weekBefore = (2...8).compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
        let missedYesterday = !daysWithSessions.contains(yesterday) && weekBefore.contains { daysWithSessions.contains($0) }
        return (streak, missedYesterday, !daysWithSessions.isEmpty)
    }

    /// Consecutive days before today without a focus block, counting back from yesterday.
    /// Nil when there is no history in the lookback (the count would not be real).
    func daysWithoutBlock(now: Date) -> Int? {
        let today = calendar.startOfDay(for: now)
        let since = calendar.date(byAdding: .day, value: -Self.lookbackDays, to: today) ?? today
        let days = Set(focusSessions(since: since).map { calendar.startOfDay(for: $0.startedAt) })
        return Self.daysWithoutBlock(daysWithSessions: days, today: today, calendar: calendar)
    }

    nonisolated static func daysWithoutBlock(daysWithSessions: Set<Date>, today: Date, calendar: Calendar) -> Int? {
        guard let earliest = daysWithSessions.min(), earliest < today else { return nil }
        var count = 0
        var day = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        while day >= earliest, !daysWithSessions.contains(day) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }

    // MARK: Weekly priorities

    func weeklyPriorities(now: Date) -> [WeeklyPriority] {
        guard hasEntity(named: "WeeklyPriority") else { return [] }
        let weekStart = WeeklyPriority.weekStart(for: now, calendar: calendar)
        let descriptor = FetchDescriptor<WeeklyPriority>(
            predicate: #Predicate { $0.weekStart == weekStart },
            sortBy: [SortDescriptor(\.order)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func project(id: UUID) -> Project? {
        let descriptor = FetchDescriptor<Project>(predicate: #Predicate { $0.id == id && !$0.archived })
        return try? modelContext.fetch(descriptor).first
    }

    // MARK: Derailers

    /// The frontmost target's real time this week, when it is a confirmed derailer: a user
    /// distraction rule, or a built-in entertainment site/app (never a work tool). Website
    /// detail is only used when the user allowed domain collection.
    func derailerFact(
        bundleIdentifier: String?,
        browserHost: String?,
        displayName: String?,
        allowDomains: Bool,
        catalog: IdleDistractionCatalog,
        now: Date
    ) -> CoachDerailerFact? {
        let key: String
        let name: String
        let target: IdleDistractionCatalog.Target
        if let host = browserHost, allowDomains, let normalized = AppUsageEntry.normalizedBrowserHost(from: host) {
            key = "domain:\(normalized)"
            name = displayName ?? normalized
            target = .website(normalized)
        } else if let bundleIdentifier {
            key = bundleIdentifier
            name = displayName ?? bundleIdentifier
            target = .app(bundleIdentifier)
        } else {
            return nil
        }

        let userRule = catalog.resolution(for: target).severity != nil
        let builtIn = AppUsageEntry.classify(
            bundleIdentifier: key,
            appName: name,
            browserHost: key.hasPrefix("domain:") ? String(key.dropFirst("domain:".count)) : nil
        ) == .distracting
        guard userRule || builtIn else { return nil }

        let weekStart = WeeklyPriority.weekStart(for: now, calendar: calendar)
        let descriptor = FetchDescriptor<AppUsageEntry>(predicate: #Predicate { $0.date >= weekStart })
        let entries = (try? modelContext.fetch(descriptor)) ?? []
        let seconds = entries
            .filter { $0.bundleIdentifier.lowercased() == key.lowercased() }
            .reduce(0) { $0 + $1.totalSeconds }
        let minutes = seconds / 60
        guard minutes >= Self.minimumDerailerMinutes else { return nil }
        return CoachDerailerFact(name: name, minutesThisWeek: minutes)
    }
}
