import Foundation

/// "Is this {priority}, or does it just feel productive?" (Coach v2 design §9 step 4).
///
/// Inside a learned window, with no session running and pacing pressure ≥ 0.5, after at least
/// 20 minutes in a work or neutral context, the coach asks once. A derailer frontmost is a
/// different problem (the start nudge covers it), so it resets the run.
enum CoachPseudoProductivityGuard {
    static let minimumContextMinutes = 20
    /// "Ask once": at most one question per 3 hours, so one per evening window.
    static let askCooldown: TimeInterval = 3 * 60 * 60
    /// "Planned, leave me" keeps the coach quiet this long.
    static let plannedQuietMinutes = 60

    struct Input: Sendable {
        var now: Date
        var inGoodWindow: Bool
        var sessionActive: Bool
        var pacing: CoachGoalPacing
        /// When the current uninterrupted work/neutral context run began.
        var contextRunStart: Date?
        var lastAskedAt: Date?
        var hasPriority: Bool
    }

    static func shouldAsk(_ input: Input) -> Bool {
        guard input.hasPriority, input.inGoodWindow, !input.sessionActive, input.pacing.isBehindPace,
              let runStart = input.contextRunStart else { return false }
        guard input.now.timeIntervalSince(runStart) >= TimeInterval(minimumContextMinutes * 60) else { return false }
        if let lastAskedAt = input.lastAskedAt, input.now.timeIntervalSince(lastAskedAt) < askCooldown {
            return false
        }
        return true
    }

    /// Tracks the uninterrupted run of work/neutral context. A derailer or a session ends it.
    static func updatedRunStart(
        previous: Date?,
        category: AppUsageEntry.AppCategory,
        sessionActive: Bool,
        now: Date
    ) -> Date? {
        guard !sessionActive else { return nil }
        switch category {
        case .productive, .neutral:
            return previous ?? now
        case .distracting:
            return nil
        }
    }
}

/// The user's answer to the pseudo-productivity question.
enum CoachPseudoAnswer: String, Codable, Sendable, CaseIterable {
    /// "It's {priority}: start a block"
    case isPriority
    /// "Side quest: start {priority} instead"
    case sideQuest
    /// "Planned, leave me"
    case planned
}

/// One logged answer, kept so the coach can learn which contexts are pseudo-work (§9 step 5).
struct CoachPseudoWorkEntry: Codable, Sendable, Equatable {
    let answeredAt: Date
    let answer: CoachPseudoAnswer
    let contextName: String?
    let hourOfDay: Int
    let priorityTitle: String
}

/// Answer log in UserDefaults (newest last, capped).
struct CoachPseudoWorkLog {
    static let storageKey = "focusflow.coachPseudoWorkLog.v1"
    static let maxEntries = 500
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var entries: [CoachPseudoWorkEntry] {
        guard let data = defaults.data(forKey: Self.storageKey) else { return [] }
        return (try? JSONDecoder().decode([CoachPseudoWorkEntry].self, from: data)) ?? []
    }

    func append(_ entry: CoachPseudoWorkEntry) {
        var all = entries
        all.append(entry)
        if all.count > Self.maxEntries { all.removeFirst(all.count - Self.maxEntries) }
        if let data = try? JSONEncoder().encode(all) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }

    /// Side-quest rate for a context, e.g. "Claude" at 22:00 (§9 step 5 input).
    func sideQuestRate(contextName: String) -> Double? {
        let matching = entries.filter { $0.contextName == contextName }
        guard !matching.isEmpty else { return nil }
        return Double(matching.filter { $0.answer == .sideQuest }.count) / Double(matching.count)
    }
}
