import Foundation

// MARK: - Resolved signal (single source of truth)

/// The one "most relevant situation" distilled from a `FocusCoachContext`.
/// Both the banner pill AND the headline/body/quote must derive from this — never re-resolve independently.
enum ResolvedCoachSignal: Sendable {
    case lowPriorityPattern(count: Int)
    case distractingAppActive(appName: String, formattedIdle: String)
    case longIdle(formattedDuration: String)
    case noSessionsLateDay(formattedHour: String)
    case lowGoalProgress(percent: Int, goalMinutes: Int)
    case distractingAppPresent(appName: String)
    case `default`
}

// MARK: - Output model

/// The personalised message bundle produced by `FocusCoachMessageBuilder`.
/// `signal` is exposed so the UI can derive its context pill from the same resolved situation.
struct CoachMessage: Sendable {
    let signal: ResolvedCoachSignal
    let headline: String
    let body: String
    let quote: FocusCoachQuote

    /// SF Symbol for the context pill. Non-nil means a pill should be shown.
    var bannerIcon: String? {
        switch signal {
        case .lowPriorityPattern:       return "arrow.triangle.2.circlepath"
        case .distractingAppActive:     return "exclamationmark.app.fill"
        case .longIdle:                 return "timer"
        case .noSessionsLateDay:        return "clock.badge.exclamationmark"
        case .lowGoalProgress:          return "chart.bar.fill"
        case .distractingAppPresent:    return "exclamationmark.app.fill"
        case .default:                  return nil
        }
    }

    /// Short label for the context pill. Nil for `.default` (no pill shown).
    var bannerLabel: String? {
        switch signal {
        case .lowPriorityPattern(let count):
            return "Low-priority pattern ×\(count) this week"
        case .distractingAppActive(let app, let idle):
            return "\(app) · \(idle) idle"
        case .longIdle(let dur):
            return "\(dur) since last work"
        case .noSessionsLateDay(let t):
            return "No sessions yet · \(t)"
        case .lowGoalProgress(let pct, _):
            return "\(pct)% of daily goal"
        case .distractingAppPresent(let app):
            return "\(app) in foreground"
        case .default:
            return nil
        }
    }
}

// MARK: - Builder

enum FocusCoachMessageBuilder {

    static func build(context: FocusCoachContext, sessionSeed: Int = 0) -> CoachMessage {
        let signal = resolveSignal(context: context)
        let headline = buildHeadline(signal: signal)
        let (body, quoteCategory) = buildBodyAndCategory(signal: signal, context: context)
        let quote = FocusCoachMotivationalQuotes.pick(category: quoteCategory, seed: sessionSeed)
        return CoachMessage(signal: signal, headline: headline, body: body, quote: quote)
    }

    // MARK: - Signal resolution (single pass — used by all downstream functions)

    static func resolveSignal(context: FocusCoachContext) -> ResolvedCoachSignal {
        if context.recentLowPriorityWorkCount >= 2 {
            return .lowPriorityPattern(count: context.recentLowPriorityWorkCount)
        }
        if context.isInDistractingApp, let app = context.frontmostAppName, context.idleSeconds > 600 {
            return .distractingAppActive(appName: app, formattedIdle: context.formattedIdle)
        }
        if context.idleSeconds > 1800 {
            return .longIdle(formattedDuration: context.formattedIdle)
        }
        if context.todaySessionCount == 0, context.hourOfDay >= 14 {
            return .noSessionsLateDay(formattedHour: formattedHour(context.hourOfDay))
        }
        if context.goalProgress < 0.4, context.hourOfDay >= 17 {
            return .lowGoalProgress(
                percent: Int(context.goalProgress * 100),
                goalMinutes: Int(context.dailyGoalSeconds / 60)
            )
        }
        if let app = context.frontmostAppName, context.frontmostAppCategory == .distracting {
            return .distractingAppPresent(appName: app)
        }
        return .default
    }

    // MARK: - Headline

    private static func buildHeadline(signal: ResolvedCoachSignal) -> String {
        switch signal {
        case .lowPriorityPattern(let count):
            return "You've shifted to low-priority work \(count)× this week instead of focusing"
        case .distractingAppActive(let app, let idle):
            return "You've been on \(app) for \(idle)"
        case .longIdle(let dur):
            return "\(dur) since your last focused work — that's a long drift"
        case .noSessionsLateDay(let t):
            return "It's \(t) and you haven't started a single session today"
        case .lowGoalProgress(let pct, let goalMin):
            return "Only \(pct)% of your \(goalMin)m goal done — window is closing"
        case .distractingAppPresent(let app):
            return "Close \(app) and lock in"
        case .default:
            return "Your deep work window is open — close it strong"
        }
    }

    // MARK: - Body + quote category

    private static func buildBodyAndCategory(
        signal: ResolvedCoachSignal,
        context: FocusCoachContext
    ) -> (body: String, quoteCategory: FocusCoachQuote.Category) {
        switch signal {
        case .lowPriorityPattern:
            return (
                "Over-planning and shallow tasks feel productive — but they don't move your most important work. What's the one thing that actually matters right now?",
                .priority
            )
        case .distractingAppActive(let app, _):
            return (
                "One distraction triggers another. Close \(app) and lock in — even 20 focused minutes changes the arc of your day.",
                .distraction
            )
        case .longIdle:
            return (
                "The longer the drift, the harder the restart. A single focused session right now reverses the momentum.",
                .timeUrgency
            )
        case .noSessionsLateDay:
            return (
                "Afternoon slips are normal — but one started session reverses the trajectory. The bar is just to begin.",
                .timeUrgency
            )
        case .lowGoalProgress:
            return (
                "There's still time. A focused push now is worth more than the whole scattered day behind you.",
                .timeUrgency
            )
        case .distractingAppPresent(let app):
            return (
                "One distraction triggers another. Close \(app) and lock in.",
                .distraction
            )
        case .default:
            if context.todaySessionCount >= 2 {
                return (
                    "You've already proved you can focus today. One more session locks in the day.",
                    .momentum
                )
            }
            return (
                "Deep work done now compounds. Shallow tasks done now disappear.",
                .procrastination
            )
        }
    }

    // MARK: - Helpers

    private static func formattedHour(_ hour: Int) -> String {
        let h = hour % 12 == 0 ? 12 : hour % 12
        let period = hour < 12 ? "AM" : "PM"
        return "\(h)\(period)"
    }
}

