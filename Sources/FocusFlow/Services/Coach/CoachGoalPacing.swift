import Foundation

/// Daily goal pacing (Coach v2 design §8).
///
/// `remaining = goal − today's personal work`. Pressure is `remaining / windowMinutesLeft`,
/// where `windowMinutesLeft` is the good-window time still ahead today from the availability
/// model. Tiers: < 0.5 on track (stay quiet), 0.5–1.0 nudge at the next window, > 1.0 at risk.
///
/// "Personal work" is every focus session today. FocusFlow is only used for personal deep
/// work by this user, so no session is excluded (documented decision; priority tagging is
/// recorded on the session but not required for it to count).
struct CoachGoalPacing: Sendable, Equatable {
    enum Tier: String, Sendable, Equatable {
        case goalMet
        case onTrack
        case nudge
        case atRisk
        /// No window data yet, so pressure can't be computed. Prompts are allowed.
        case unknown
    }

    static let minimumBlockMinutes = 25
    static let maximumBlockMinutes = 50

    let goalMinutes: Int
    let doneMinutes: Int
    let remainingMinutes: Int
    let windowMinutesLeft: Int?
    /// `remaining / windowMinutesLeft`. Nil when unknown; `.infinity` when no window is left.
    let pressure: Double?
    let tier: Tier
    /// `max(25, min(remaining, 50))`.
    let suggestedBlockMinutes: Int

    init(goalMinutes: Int, doneMinutes: Int, windowMinutesLeft: Int?) {
        self.goalMinutes = max(0, goalMinutes)
        self.doneMinutes = max(0, doneMinutes)
        let remaining = max(0, goalMinutes - doneMinutes)
        self.remainingMinutes = remaining
        self.windowMinutesLeft = windowMinutesLeft
        self.suggestedBlockMinutes = max(Self.minimumBlockMinutes, min(remaining, Self.maximumBlockMinutes))

        if remaining == 0 {
            pressure = 0
            tier = .goalMet
        } else if let windowMinutesLeft {
            let value = windowMinutesLeft > 0 ? Double(remaining) / Double(windowMinutesLeft) : .infinity
            pressure = value
            tier = value > 1.0 ? .atRisk : (value >= 0.5 ? .nudge : .onTrack)
        } else {
            pressure = nil
            tier = .unknown
        }
    }

    /// Share of today's goal done, 0...100.
    var percentOfGoal: Int {
        guard goalMinutes > 0 else { return 100 }
        return min(100, Int((Double(doneMinutes) / Double(goalMinutes) * 100).rounded(.down)))
    }

    /// Pressure ≥ 0.5, or unknown with work remaining. Start nudges and the
    /// pseudo-productivity guard only run when this is true; on track means stay quiet.
    var isBehindPace: Bool {
        switch tier {
        case .nudge, .atRisk, .unknown: true
        case .goalMet, .onTrack: false
        }
    }
}
