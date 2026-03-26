import Foundation

/// Pure heuristics for deciding when to intervene and how easy it is to start a focus session now.
/// Keeps logic explainable and testable.
struct FocusCoachOpportunityModel: Sendable {

    struct IdleStarterContext: Sendable {
        let driftConfidence: Double
        let focusOpportunity: Double
        let recommendedDurationMinutes: Int
        let summary: String
    }

    /// Estimates how likely the user is currently drifting while idle.
    /// Value is clamped to 0...1.
    func idleDriftConfidence(
        idleSeconds: Int,
        escalationLevel: Int,
        frontmostCategory: AppUsageEntry.AppCategory
    ) -> Double {
        let idleNorm = clamp(Double(idleSeconds) / 900.0) // saturates at 15 min
        let escalationNorm = clamp(Double(escalationLevel) / 3.0)

        let categoryFactor: Double
        switch frontmostCategory {
        case .distracting:
            categoryFactor = 1.0
        case .neutral:
            categoryFactor = 0.6
        case .productive:
            // Being in a coding/productive app *without* a session is itself a work-intent
            // signal (vibe coding, terminal, Cursor, etc.) — it should prompt the user to
            // start tracking sooner, not later. 0.7 matches neutral-leaning urgency.
            categoryFactor = 0.7
        }

        return clamp((idleNorm * 0.5) + (escalationNorm * 0.2) + (categoryFactor * 0.3))
    }

    /// Estimates whether *now* is a practical moment to start focus.
    /// Considers time-of-day and calendar window fit.
    func focusOpportunityScore(
        hourOfDay: Int,
        minutesUntilNextCalendarEvent: Int?,
        isInActiveSession: Bool
    ) -> Double {
        if isInActiveSession {
            return 0.95
        }

        let hourScore: Double
        switch hourOfDay {
        case 7..<12:
            hourScore = 0.9
        case 12..<18:
            hourScore = 0.75
        case 18..<22:
            hourScore = 0.6
        default:
            hourScore = 0.35
        }

        let calendarScore: Double
        if let minutesUntilNextCalendarEvent {
            switch minutesUntilNextCalendarEvent {
            case ..<10:
                calendarScore = 0.25
            case 10..<20:
                calendarScore = 0.55
            case 20..<30:
                calendarScore = 0.75
            default:
                calendarScore = 0.9
            }
        } else {
            calendarScore = 0.7
        }

        return clamp((hourScore * 0.6) + (calendarScore * 0.4))
    }

    /// Picks a recommended focus duration aligned to the next calendar commitment.
    /// Uses 5-minute increments and keeps a 5-minute transition buffer.
    func recommendedDuration(
        defaultMinutes: Int,
        minutesUntilNextCalendarEvent: Int?
    ) -> Int {
        guard let gapMinutes = minutesUntilNextCalendarEvent else {
            return max(5, defaultMinutes)
        }

        let usable = max(5, gapMinutes - 5)
        let presets = [5, 10, 15, 20, 25, 30, 45, 60, 90]
        let bestFit = presets.last(where: { $0 <= usable }) ?? 5
        return min(max(5, defaultMinutes), bestFit)
    }

    func idleStarterContext(
        idleSeconds: Int,
        escalationLevel: Int,
        frontmostCategory: AppUsageEntry.AppCategory,
        hourOfDay: Int,
        minutesUntilNextCalendarEvent: Int?,
        defaultMinutes: Int
    ) -> IdleStarterContext {
        let drift = idleDriftConfidence(
            idleSeconds: idleSeconds,
            escalationLevel: escalationLevel,
            frontmostCategory: frontmostCategory
        )
        let opportunity = focusOpportunityScore(
            hourOfDay: hourOfDay,
            minutesUntilNextCalendarEvent: minutesUntilNextCalendarEvent,
            isInActiveSession: false
        )
        let duration = recommendedDuration(
            defaultMinutes: defaultMinutes,
            minutesUntilNextCalendarEvent: minutesUntilNextCalendarEvent
        )

        let summary: String
        if let minutesUntilNextCalendarEvent {
            summary = "You have about \(minutesUntilNextCalendarEvent)m before the next commitment. A \(duration)m rescue block fits now."
        } else {
            summary = "This is a strong window for a \(duration)m focused block."
        }

        return IdleStarterContext(
            driftConfidence: drift,
            focusOpportunity: opportunity,
            recommendedDurationMinutes: duration,
            summary: summary
        )
    }

    private func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}
