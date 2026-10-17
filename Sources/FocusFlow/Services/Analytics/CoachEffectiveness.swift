import Foundation

// Is the coach helping? The primary metric from Coach v2 §6: a prompt counts as a success
// when a focus block starts within 10 minutes of it.

extension FocusAnalytics {
    struct PromptArm: Hashable, Sendable, Identifiable {
        let key: String
        let label: String
        let prompts: Int
        let starts: Int
        var id: String { key }
        var rate: Double { prompts > 0 ? Double(starts) / Double(prompts) : 0 }
    }

    struct CoachEffectiveness: Hashable, Sendable {
        /// Prompts actually shown (silent "do nothing" decisions excluded).
        let prompts: Int
        let startsWithinWindow: Int
        let promptsPerDay: Double
        /// Days the per-day rate is taken over (from the first prompt in range).
        let days: Int
        /// Only styles recorded on attempts (`styleRawValue`); empty for legacy data.
        let byStyle: [PromptArm]
        let bySurface: [PromptArm]
        /// The bandit's "silent" arm, a natural baseline when present.
        let silentBaseline: PromptArm?

        var rate: Double? { prompts > 0 ? Double(startsWithinWindow) / Double(prompts) : nil }
        var hasData: Bool { prompts > 0 }
    }

    /// - Parameters:
    ///   - window: how soon after a prompt a start still counts (default 10 min).
    ///   Prompts delivered while a focus block was already running are ignored: a start can't follow them.
    func coachEffectiveness(
        prompts: [PromptSample],
        sessions: [FocusSample],
        in interval: DateInterval,
        window: TimeInterval = 600
    ) -> CoachEffectiveness {
        let focus = sessions.filter(\.isFocus).sorted { $0.start < $1.start }
        let starts = focus.map(\.start)

        func isDuringFocus(_ date: Date) -> Bool {
            focus.contains { $0.start < date && date < $0.end }
        }

        func startedSoon(after date: Date) -> Bool {
            // First start ≥ date via binary search.
            var low = 0
            var high = starts.count
            while low < high {
                let mid = (low + high) / 2
                if starts[mid] < date { low = mid + 1 } else { high = mid }
            }
            return low < starts.count && starts[low].timeIntervalSince(date) <= window
        }

        let relevant = prompts.filter { interval.contains($0.deliveredAt) && !isDuringFocus($0.deliveredAt) }
        let shown = relevant.filter { $0.surface != .silent }
        let silent = relevant.filter { $0.surface == .silent }
        let outcomes = shown.map { ($0, startedSoon(after: $0.deliveredAt)) }

        func arm(key: String, label: String, _ items: [(PromptSample, Bool)]) -> PromptArm {
            PromptArm(key: key, label: label, prompts: items.count, starts: items.filter(\.1).count)
        }

        let byStyle = CoachStyle.allCases.compactMap { style -> PromptArm? in
            let items = outcomes.filter { $0.0.style == style }
            return items.isEmpty ? nil : arm(key: style.rawValue, label: style.displayName, items)
        }

        let bySurface = CoachSurface.allCases.filter { $0 != .silent }.compactMap { surface -> PromptArm? in
            let items = outcomes.filter { $0.0.surface == surface }
            return items.isEmpty ? nil : arm(key: surface.rawValue, label: Self.surfaceLabel(surface), items)
        }

        let silentArm = silent.isEmpty ? nil : arm(
            key: CoachSurface.silent.rawValue,
            label: Self.surfaceLabel(.silent),
            silent.map { ($0, startedSoon(after: $0.deliveredAt)) }
        )

        let firstPrompt = shown.map(\.deliveredAt).min() ?? interval.start
        let spanStart = calendar.startOfDay(for: max(firstPrompt, interval.start))
        let spanEnd = calendar.startOfDay(for: interval.end)
        let days = max(1, (calendar.dateComponents([.day], from: spanStart, to: spanEnd).day ?? 0) + 1)

        return CoachEffectiveness(
            prompts: shown.count,
            startsWithinWindow: outcomes.filter(\.1).count,
            promptsPerDay: shown.isEmpty ? 0 : Double(shown.count) / Double(days),
            days: days,
            byStyle: byStyle,
            bySurface: bySurface,
            silentBaseline: silentArm
        )
    }

    static func surfaceLabel(_ surface: CoachSurface) -> String {
        switch surface {
        case .silent: "No prompt"
        case .badge: "Badge"
        case .panel: "Panel"
        case .notification: "Notification"
        case .strongWindow: "Pause screen"
        }
    }
}

// MARK: - Rescue loop (rescue loop design §5)

/// One rescue, read from an attempt's context key (`lvl:` and `surf:`).
struct RescueSample: Hashable, Sendable {
    let deliveredAt: Date
    let level: DriftLevel
    let surface: CoachRescueSurface

    init(deliveredAt: Date, level: DriftLevel, surface: CoachRescueSurface) {
        self.deliveredAt = deliveredAt
        self.level = level
        self.surface = surface
    }

    /// Nil for prompts that are not rescues (no drift level in the key).
    init?(contextKey: String?, deliveredAt: Date) {
        guard let contextKey, let key = CoachContextKey(rawValue: contextKey),
              let level = key.driftLevel, level > .ok, let surface = key.rescueSurface else { return nil }
        self.init(deliveredAt: deliveredAt, level: level, surface: surface)
    }
}

extension FocusAnalytics {
    struct RescueEffectiveness: Hashable, Sendable {
        /// Rescue → start within the window, per drift level (L1–L3, only levels with rescues).
        let byLevel: [PromptArm]
        /// Same, per surface (panel, pause screen, menu bar only).
        let bySurface: [PromptArm]
        /// Starter blocks in range, and how many led straight into a block of 20 minutes or more.
        let starterBlocks: Int
        let startersKeptGoing: Int

        var hasRescues: Bool { !byLevel.isEmpty }
        var keptGoingRate: Double? { starterBlocks > 0 ? Double(startersKeptGoing) / Double(starterBlocks) : nil }
    }

    func rescueEffectiveness(
        rescues: [RescueSample],
        sessions: [FocusSample],
        in interval: DateInterval,
        window: TimeInterval = 600
    ) -> RescueEffectiveness {
        let focus = sessions.filter(\.isFocus).sorted { $0.start < $1.start }
        let starts = focus.map(\.start)

        func startedSoon(after date: Date) -> Bool {
            var low = 0
            var high = starts.count
            while low < high {
                let mid = (low + high) / 2
                if starts[mid] < date { low = mid + 1 } else { high = mid }
            }
            return low < starts.count && starts[low].timeIntervalSince(date) <= window
        }

        let relevant = rescues.filter { interval.contains($0.deliveredAt) }
        let outcomes = relevant.map { ($0, startedSoon(after: $0.deliveredAt)) }
        func arm(key: String, label: String, _ items: [(RescueSample, Bool)]) -> PromptArm {
            PromptArm(key: key, label: label, prompts: items.count, starts: items.filter(\.1).count)
        }
        let byLevel = DriftLevel.allCases.filter { $0 > .ok }.compactMap { level -> PromptArm? in
            let items = outcomes.filter { $0.0.level == level }
            return items.isEmpty ? nil : arm(key: "L\(level.rawValue)", label: "L\(level.rawValue) \(level.label)", items)
        }
        let bySurface = CoachRescueSurface.allCases.compactMap { surface -> PromptArm? in
            let items = outcomes.filter { $0.0.surface == surface }
            return items.isEmpty ? nil : arm(key: surface.rawValue, label: surface.label, items)
        }
        let conversion = starterConversion(focus, in: interval)
        return RescueEffectiveness(
            byLevel: byLevel,
            bySurface: bySurface,
            starterBlocks: conversion.starters,
            startersKeptGoing: conversion.keptGoing
        )
    }

    /// Starter blocks (`label("Starter")`, no project) and how many were followed, within
    /// 5 minutes of their end, by a focus block of at least 20 minutes ("kept going").
    func starterConversion(_ sessions: [FocusSample], in interval: DateInterval) -> (starters: Int, keptGoing: Int) {
        let focus = sessions.filter(\.isFocus).sorted { $0.start < $1.start }
        var starters = 0
        var kept = 0
        for (index, session) in focus.enumerated() where interval.contains(session.start) && Self.isStarter(session) {
            starters += 1
            let end = session.start.addingTimeInterval(session.activeSeconds)
            let next = focus[(index + 1)...].first { !Self.isStarter($0) && $0.start >= end.addingTimeInterval(-60) }
            if let next,
               next.start.timeIntervalSince(end) <= CoachStarterBlock.keepGoingGap,
               next.activeSeconds >= CoachStarterBlock.keptGoingMinimumSeconds {
                kept += 1
            }
        }
        return (starters, kept)
    }

    static func isStarter(_ session: FocusSample) -> Bool {
        session.project == .label(CoachStarterBlock.label)
    }
}
