import Foundation

struct EarnedBreakSuggestionInput {
    let effectiveEffortSeconds: Int
    let overtimeSeconds: Int
    let runCreditSeconds: Int
    let adaptationMinutes: Int
}

struct EarnedBreakSuggestion {
    let suggestedMinutes: Int
    let adaptationAppliedMinutes: Int
}

struct EarnedBreakSuggestionEngine {
    func suggest(_ input: EarnedBreakSuggestionInput) -> EarnedBreakSuggestion {
        let effortMinutes = max(0, input.effectiveEffortSeconds / 60)
        let baseline: Int
        switch effortMinutes {
        case ..<25: baseline = 5
        case 25..<40: baseline = 8
        case 40..<55: baseline = 12
        case 55..<75: baseline = 15
        default: baseline = 20
        }

        let overtimeBonus = input.overtimeSeconds > 0 ? 2 : 0
        let clampedAdaptation = min(3, max(-3, input.adaptationMinutes))
        let raw = baseline + overtimeBonus + clampedAdaptation
        let suggested = min(20, max(5, raw))

        return EarnedBreakSuggestion(
            suggestedMinutes: suggested,
            adaptationAppliedMinutes: clampedAdaptation
        )
    }
}

/// Coach v6 §3.4: why a break ran over. Asked in the break-over window once it is 5+ min over.
enum BreakOverrunReason: String, CaseIterable, Sendable, Identifiable {
    case neededRest = "needed_rest"
    case pulledAway = "pulled_away"
    case lostTrack = "lost_track"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .neededRest: "Needed the rest"
        case .pulledAway: "Got pulled into something"
        case .lostTrack: "Lost track"
        }
    }

    /// The window asks once the break is this far over.
    static let askAfterSeconds = 5 * 60
}

/// How recent breaks move the next suggestion, in minutes (−3…+3).
enum BreakAdaptation {
    struct Event: Equatable, Sendable {
        var returnedToFocus: Bool
        var endedEarly: Bool
        var overrunSeconds: Int
        var reason: BreakOverrunReason?
    }

    /// Ended early: shorter. Ran over because you needed the rest: longer, the suggestion was too
    /// short. Ran over because something pulled you in or you lost track: not a length problem, so
    /// no change (the break-over reminder is the lever there). Ran over with no answer: shorter, as
    /// before v6. Coming back to focus is the break working, so it nudges toward keeping it.
    static func minutes(_ events: [Event]) -> Int {
        var score = 0
        for event in events {
            if event.returnedToFocus { score += 1 }
            if event.endedEarly { score -= 1 }
            if event.overrunSeconds > 120 {
                switch event.reason {
                case .neededRest: score += 2
                case .pulledAway, .lostTrack: break
                case nil: score -= 1
                }
            }
        }
        return min(3, max(-3, score / 2))
    }
}
