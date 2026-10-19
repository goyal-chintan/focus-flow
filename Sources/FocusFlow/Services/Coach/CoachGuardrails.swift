import Foundation

/// Hard limits on coach prompts (Coach v2 design §3 [3]). These are not learnable: the bandit
/// only chooses among the surfaces that pass them. `silent` always passes.
struct CoachGuardrails: Sendable {
    struct Delivery: Sendable, Equatable {
        let surface: CoachSurface
        let deliveredAt: Date
        /// False for prompts the user asked for (planned-start cues, the daily plan card) and
        /// for panels nobody saw. Those never use up the daily cap (v3 §3.3, R1).
        var countsTowardCap: Bool = true
    }

    struct Input: Sendable {
        var now: Date
        var calendar: Calendar = .current
        /// Prompts already shown (any surface except silent), most recent 24h is enough.
        var deliveries: [Delivery] = []
        var maxPromptsPerDay: Int = 3
        /// Minutes after midnight. Equal start and end disables quiet hours.
        var quietStartMinute: Int = 30
        var quietEndMinute: Int = 420
        var calendarBusy: Bool = false
        var screenShareActive: Bool = false
        /// "Done for today" or another explicit release.
        var releaseActive: Bool = false
        /// "Not now" / "Planned, leave me" snooze.
        var snoozedUntil: Date?
        /// A focus block (or break) is running. Idle prompts never show then.
        var sessionActive: Bool = false
        /// True for idle/start prompts; false for the in-session drift check.
        var isIdlePrompt: Bool = true
        /// The rescue loop has its own cadence (level rises, 20-minute repeats), so the 2-hour
        /// panel spacing does not apply to it. Every other hard limit does.
        var ignorePanelSpacing: Bool = false
    }

    enum Verdict: String, Sendable, Equatable {
        case allowed
        case sessionActive
        case released
        case screenShare
        case calendarBusy
        case quietHours
        case snoozed
        case dailyCapReached
        case panelTooSoon
    }

    static let panelSpacing: TimeInterval = 2 * 60 * 60

    /// Verdict for showing a prompt on `surface`.
    func verdict(for surface: CoachSurface, input: Input) -> Verdict {
        if surface == .silent { return .allowed }
        if input.isIdlePrompt && input.sessionActive { return .sessionActive }
        if input.releaseActive { return .released }
        if input.screenShareActive { return .screenShare }
        if input.calendarBusy { return .calendarBusy }
        if Self.isQuietHours(input.now, start: input.quietStartMinute, end: input.quietEndMinute, calendar: input.calendar) {
            return .quietHours
        }
        if let snoozedUntil = input.snoozedUntil, input.now < snoozedUntil { return .snoozed }

        let startOfDay = input.calendar.startOfDay(for: input.now)
        // Only prompts that interrupted: a menu-bar badge is ambient (v3 R1).
        let shownToday = input.deliveries.filter {
            $0.countsTowardCap && $0.surface != .silent && $0.surface != .badge
                && $0.deliveredAt >= startOfDay && $0.deliveredAt <= input.now
        }
        if shownToday.count >= max(0, input.maxPromptsPerDay) { return .dailyCapReached }

        if (surface == .panel || surface == .strongWindow) && !input.ignorePanelSpacing {
            let spacingStart = input.now.addingTimeInterval(-Self.panelSpacing)
            let recentPanel = input.deliveries.contains {
                ($0.surface == .panel || $0.surface == .strongWindow)
                    && $0.deliveredAt > spacingStart && $0.deliveredAt <= input.now
            }
            if recentPanel { return .panelTooSoon }
        }
        return .allowed
    }

    /// Surfaces from `candidates` that pass, plus the first blocking verdict for reporting.
    func allowedSurfaces(
        from candidates: [CoachSurface],
        input: Input
    ) -> (surfaces: [CoachSurface], firstBlock: Verdict?) {
        var allowed: [CoachSurface] = []
        var firstBlock: Verdict?
        for surface in candidates {
            let verdict = verdict(for: surface, input: input)
            if verdict == .allowed {
                allowed.append(surface)
            } else if firstBlock == nil {
                firstBlock = verdict
            }
        }
        return (allowed, firstBlock)
    }

    static func isQuietHours(_ date: Date, start: Int, end: Int, calendar: Calendar = .current) -> Bool {
        guard start != end else { return false }
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let minute = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        if start < end {
            return minute >= start && minute < end
        }
        // Wraps past midnight, e.g. 23:00 → 07:00.
        return minute >= start || minute < end
    }
}

extension CoachGuardrails.Delivery {
    /// Maps a stored attempt. Rows from before Coach v2.1 have no surface: a strong prompt was
    /// a window (counts as a panel for spacing), everything else counts toward the cap only.
    init(attempt: InterventionAttempt) {
        let surface = attempt.surfaceRawValue.flatMap(CoachSurface.init(rawValue:))
            ?? (attempt.kind == .strongPrompt ? .strongWindow : .badge)
        let requested = attempt.contextKey.map(CoachPlannedCue.isPlannedContextKey) ?? false
        self.init(
            surface: surface,
            deliveredAt: attempt.deliveredAt,
            countsTowardCap: !requested && attempt.outcome != .unseen
        )
    }
}
