import Foundation

// MARK: - Resolved signal (single source of truth)

/// The one "most relevant situation" distilled from a `FocusCoachContext`.
/// Both the banner pill AND the headline/body/quote must derive from this — never re-resolve independently.
enum ResolvedCoachSignal: Sendable {
    case releaseWindowActive
    case blockRecommendation(target: String)
    case lowPriorityPattern(count: Int)
    case distractingAppActive(appName: String, formattedIdle: String, workMode: WorkMode?, projectName: String?)
    case longIdle(formattedDuration: String)
    case noSessionsLateDay(formattedHour: String, projectName: String?)
    case lowGoalProgress(percent: Int, goalMinutes: Int, projectName: String?)
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
        case .releaseWindowActive:      return "pause.circle.fill"
        case .blockRecommendation:      return "shield.lefthalf.filled"
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
        case .releaseWindowActive:
            return "Guardian paused after your explicit opt-out"
        case .blockRecommendation(let target):
            let displayTarget = AppUsageEntry.recommendationDisplayLabel(for: target)
            return "Recommend blocking \(displayTarget) for this project"
        case .lowPriorityPattern(let count):
            return "Low-priority pattern ×\(count) this week"
        case .distractingAppActive(let app, _, let workMode, let projectName):
            return FocusCoachMessageBuilder.exactMismatchLabel(appName: app, domain: nil, workMode: workMode, projectName: projectName)
        case .longIdle(let dur):
            return "\(dur) since last work"
        case .noSessionsLateDay(let t, _):
            return "No sessions yet · \(t)"
        case .lowGoalProgress(let pct, _, _):
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
        if context.inReleaseWindow {
            return .releaseWindowActive
        }
        if let target = context.suggestedBlockTarget {
            return .blockRecommendation(target: target)
        }
        if context.recentLowPriorityWorkCount >= 2 {
            return .lowPriorityPattern(count: context.recentLowPriorityWorkCount)
        }
        if context.isInDistractingApp, let app = context.frontmostAppName, context.idleSeconds > 600 {
            return .distractingAppActive(appName: app, formattedIdle: context.formattedIdle, workMode: context.selectedWorkMode, projectName: context.selectedProjectName)
        }
        if context.idleSeconds > 1800 {
            return .longIdle(formattedDuration: context.formattedIdle)
        }
        if context.todaySessionCount == 0, context.hourOfDay >= 14 {
            return .noSessionsLateDay(
                formattedHour: formattedHour(context.hourOfDay),
                projectName: context.selectedProjectName
            )
        }
        if context.goalProgress < 0.4, context.hourOfDay >= 17 {
            return .lowGoalProgress(
                percent: Int(context.goalProgress * 100),
                goalMinutes: Int(context.dailyGoalSeconds / 60),
                projectName: context.selectedProjectName
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
        case .releaseWindowActive:
            return "You marked yourself off-duty, so guardrails are paused for now"
        case .blockRecommendation(let target):
            let displayTarget = AppUsageEntry.recommendationDisplayLabel(for: target)
            return "\(displayTarget) is repeatedly pulling attention away from your planned work"
        case .lowPriorityPattern(let count):
            return "Low-priority work replaced planned focus \(count) times this week"
        case .distractingAppActive(let app, let idle, _, _):
            return "You've been on \(app) for \(idle)"
        case .longIdle(let dur):
            return "\(dur) since your last focused block"
        case .noSessionsLateDay(let t, let projectName):
            if let projectName, !projectName.isEmpty {
                return "It's \(t) and \(projectName) still has no started block"
            }
            return "It's \(t) and no focus block has started yet"
        case .lowGoalProgress(let pct, let goalMin, let projectName):
            if let projectName, !projectName.isEmpty {
                return "\(projectName) is at \(pct)% of the \(goalMin)m daily target"
            }
            return "You are at \(pct)% of your \(goalMin)m daily target"
        case .distractingAppPresent(let app):
            return "\(app) is active while focus protection is on"
        case .default:
            return "Your next focused block is available now"
        }
    }

    // MARK: - Body + quote category

    private static func buildBodyAndCategory(
        signal: ResolvedCoachSignal,
        context: FocusCoachContext
    ) -> (body: String, quoteCategory: FocusCoachQuote.Category) {
        switch signal {
        case .releaseWindowActive:
            return (
                "You made an explicit stop choice. FocusFlow will stay passive until your release window ends.",
                .momentum
            )
        case .blockRecommendation:
            return (
                context.blockRecommendationReason ?? "This context has repeatedly correlated with avoidant drift. Add a project-specific block to reduce future slips.",
                .priority
            )
        case .lowPriorityPattern:
            return (
                "Pattern detected from your own skips: low-priority activity is replacing the intended task. Start a 5-minute rescue block or mark off-duty honestly.",
                .priority
            )
        case .distractingAppActive(let app, _, let workMode, let projectName):
            let modeFragment = workMode.map { " during \($0.displayName)" } ?? ""
            let projectFragment = projectName.map { !$0.isEmpty ? " for \($0)" : "" } ?? ""
            return (
                "\(app) has held foreground long enough to derail restart momentum\(modeFragment)\(projectFragment). Decide now: rescue block, break, or off-duty.",
                .distraction
            )
        case .longIdle:
            if let top = context.topDistractingAppName, context.topDistractingAppMinutes > 0 {
                return (
                    "Restart friction increases with idle drift. \(top) already took \(context.topDistractingAppMinutes)m today — a short rescue block can recover trajectory.",
                    .timeUrgency
                )
            }
            return (
                "Restart friction increases with idle drift. A short rescue block is enough to recover trajectory.",
                .timeUrgency
            )
        case .noSessionsLateDay:
            return (
                "You're still in the recovery window. Ready when you are.",
                .timeUrgency
            )
        case .lowGoalProgress:
            return (
                "Use one deliberate block now instead of more reactive context-switching.",
                .timeUrgency
            )
        case .distractingAppPresent(let app):
            return (
                "\(app) looks off-plan for the current focus context. Classify it as planned research or drift.",
                .distraction
            )
        case .default:
            if context.todaySessionCount >= 2 {
                return (
                    "You already have momentum today. One more deliberate block compounds it.",
                    .momentum
                )
            }
            return (
                "Starting your first block is the highest-value move right now. One 25-minute block changes the whole day.",
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

    // MARK: - Exact mismatch label (FIX 3 / fix-p4)

    /// Produces a rich, context-aware drift label for the risk strip.
    /// Falls back gracefully when optional parameters are nil.
    static func exactMismatchLabel(
        appName: String,
        domain: String?,
        workMode: WorkMode?,
        projectName: String?
    ) -> String {
        let workModeLabel = workMode?.displayName ?? "your focus block"

        // AI/chat tool loop pattern
        let aiApps = ["ChatGPT", "Claude", "Gemini", "Copilot", "Perplexity"]
        if aiApps.contains(where: { appName.localizedCaseInsensitiveContains($0) }) {
            return "ChatGPT loop during \(workModeLabel) — looks like over-planning"
        }

        // Editor with wrong repo
        let editorApps = ["Xcode", "Cursor", "VS Code", "Visual Studio Code", "Nova", "Zed"]
        if editorApps.contains(where: { appName.localizedCaseInsensitiveContains($0) }),
           let projectName, !projectName.isEmpty {
            return "\(appName) repo does not match \(projectName)"
        }

        // Browser with distracting domain
        if let domain {
            let domainLabel = AppUsageEntry.recommendationDisplayLabel(for: domain)
            return "\(appName) on \(domainLabel) during \(workModeLabel)"
        }

        // Generic fallback with workMode context
        if let workMode {
            return "\(appName) during \(workMode.displayName)"
        }

        return "\(appName) — off-plan for this context"
    }

    // MARK: - Break recovery copy (fix-c7 part B)

    /// Message shown when a break has overrun. `overrunMinutes` is the excess beyond planned break duration.
    static func breakOverrunMessage(overrunMinutes: Int) -> String {
        "Break ran \(overrunMinutes) minutes over. Your last earned block is still saved. Ready to return or done for now?"
    }

    /// Confirmation copy shown after the user opts out of further coaching pressure.
    static let optOutConfirmation = "Saved. I'll stop pushing for now."
}
