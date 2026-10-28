import Foundation

// MARK: - Inputs

/// What the primary action starts: N minutes on a priority or project.
struct CoachStartTarget: Sendable, Equatable {
    var minutes: Int
    /// Priority title or project name shown in "Start {N}m on {name}".
    var name: String?
    var projectID: UUID?
    var priorityID: UUID?
    /// Coach v4 §3.4: "I don't know the next step" → the block's job is to find it.
    var findNextStep: Bool = false
}

/// A confirmed derailer that is frontmost now, with its real time this week.
struct CoachDerailerFact: Sendable, Equatable {
    let name: String
    let minutesThisWeek: Int
}

/// Every number a message may state. Values are read from the user's data; nil means unknown,
/// and a template that needs an unknown value is skipped (never invent numbers).
struct CoachFacts: Sendable, Equatable {
    /// Consecutive days before today with at least one focus block.
    var streakDays: Int = 0
    /// True once the user has any focus block on record.
    var hasHistory: Bool = false
    var sessionsToday: Int = 0
    var doneMinutesToday: Int = 0
    var goalMinutes: Int = 0
    var pacing: CoachGoalPacing?
    /// Yesterday had no block, but the previous week had at least one.
    var missedYesterday: Bool = false
    /// Minutes since the real end of the last focus session (not the tracker idle streak).
    var minutesSinceLastSession: Int?
    var derailer: CoachDerailerFact?
    /// The user's own words from their last intent on this project.
    var lastIntent: String?
    /// Learned best start hour for today's weekday, when it is the current hour.
    var usualStartHourNow: Int?
    /// Pseudo-productivity guard: minutes in the current work/neutral context, and its name.
    var contextMinutes: Int?
    var contextAppName: String?
    /// Consecutive days before today without any focus block (comeback framing). Nil = unknown.
    var daysWithoutBlock: Int?
}

/// Everything a rescue message needs (rescue loop design §2–§4).
struct CoachRescueContext: Sendable, Equatable {
    var level: DriftLevel
    var signal: DriftSignal?
    /// Where the counts start: "in your 22:00 window", "since your last block", "today".
    var spanLabel: String
    var ask: CoachRescueAsk
    var priorityName: String?
    var lateNight: Bool = false
    var starterMinutes: Int = CoachStarterBlock.defaultMinutes

    /// The one honest fact behind the level, e.g. "47m on YouTube in your 22:00 window."
    var fact: String? {
        switch signal {
        case .derailer(let name, let minutes):
            return "\(CoachMessageComposer.duration(minutes)) on \(CoachMessageComposer.shortName(name)) \(spanLabel)."
        case .pseudo(let name, let minutes):
            return "\(CoachMessageComposer.duration(minutes)) in \(CoachMessageComposer.shortName(name)), no block running."
        case .hopping:
            return "Switching apps 6+ times a minute."
        case nil:
            return nil
        }
    }

    /// Long form for the pause screen: "47 minutes on YouTube in your 22:00 window".
    var longFact: String? {
        switch signal {
        case .derailer(let name, let minutes):
            return "\(Self.minutesPhrase(minutes)) on \(CoachMessageComposer.shortName(name)) \(spanLabel)"
        case .pseudo(let name, let minutes):
            return "\(Self.minutesPhrase(minutes)) in \(CoachMessageComposer.shortName(name)) with no block running"
        case .hopping:
            return "Switching apps more than six times a minute"
        case nil:
            return nil
        }
    }

    static func minutesPhrase(_ minutes: Int) -> String {
        if minutes >= 60 { return CoachMessageComposer.duration(minutes) }
        return minutes == 1 ? "1 minute" : "\(minutes) minutes"
    }
}

enum CoachTrigger: Sendable, Equatable {
    /// Learned window is open and the user is idle: nudge to start.
    case startNudge
    /// Evening guard: busy in a work context, but is it the priority?
    case pseudoProductivity(priority: String)
    /// In-session drift check.
    case inSessionDrift(projectName: String?, appName: String?, minutesInApp: Int?)
    /// No weekly priorities yet: invite the user to set 1–3.
    case weeklyPriorities
    /// Rescue loop: the ladder ask for the current drift level.
    case rescue(CoachRescueContext)
    /// End of a starter block: "Keep going: 20m on {step}?"
    case keepGoing(step: String?)
    /// Five minutes into a rescue-started block: "You're in. Make it 25?"
    case momentum
    /// Feedback after the global shortcut started a starter block.
    case starterStarted(minutes: Int)
    /// v3 §3.2: the user's own planned start time has come.
    case plannedStart(CoachPlannedCueContext)
    /// v4 §3.3: the start card. Start the next block now (5 · 15 · 25), or pick a time later.
    /// (v3's plan card asked "When is today's 2h?"; `goalMinutes` is no longer shown.)
    case dailyPlan(goalMinutes: Int, firstSuggestion: String?)
    /// v4 §3.4: the "then" of an if-then plan, right after a reasoned "Not now".
    case counterOffer(reason: FocusCoachSkipReason)
}

/// What a planned-start cue says (v3 §3.2).
struct CoachPlannedCueContext: Sendable, Equatable {
    /// "22:00"
    var timeLabel: String
    var minutes: Int
    var priorityName: String?
    /// Times the user already pushed this block today.
    var pushes: Int = 0
    var missedYesterday: Bool = false
    var starterMinutes: Int = CoachStarterBlock.defaultMinutes
}

struct CoachComposerInput: Sendable {
    var style: CoachStyle
    var trigger: CoachTrigger
    var facts: CoachFacts
    var target: CoachStartTarget
    var whyLines: [String] = []
    var quotes: [CoachQuote] = CoachQuoteLibrary.rotation
    /// Rotation seed for quotes, "my why" lines and alternating hooks.
    var seed: Int = 0
    /// Quote or why line chosen by `CoachQuotePicker` (learned, no repeats). When set it
    /// replaces the seed rotation; when nil the seed rotation is the fallback.
    var pickedDetail: CoachDetail?
    /// True when the picker ran and found nothing it may show (all shown in the last 3 days).
    var pickerExhausted: Bool = false
    /// The starter block length from settings; fills `{N}` in house lines.
    var starterMinutes: Int = CoachStarterBlock.defaultMinutes
}

// MARK: - Output

enum CoachDetail: Sendable, Equatable {
    /// One true statement from the user's data.
    case fact(String)
    /// A "My why" line the user wrote.
    case why(String)
    case quote(CoachQuote)
    /// A Challenger house line: plain statement, no author, no quotation marks.
    case houseLine(String)
    /// Fixed supporting copy with no user numbers.
    case line(String)

    var text: String {
        switch self {
        case .fact(let text), .why(let text), .houseLine(let text), .line(let text): text
        case .quote(let quote): quote.formatted
        }
    }
}

/// A coach message: hook + at most one fact + one primary action.
struct CoachComposedMessage: Sendable, Equatable {
    let style: CoachStyle
    let trigger: CoachTrigger
    let hook: String
    let detail: CoachDetail?
    let primaryTitle: String
    /// True when the hook itself states a fact from the user's data.
    let hookIsFact: Bool
    /// A quote, house line or "my why" line shown under the fact (v3 §3.4, R6). Before v3 a
    /// quote had to win the single detail slot against facts and almost never did.
    var motivation: CoachDetail? = nil

    var accessibilityText: String {
        [hook, detail?.text, motivation?.text].compactMap { $0 }.joined(separator: ". ")
    }

    /// The picked quote, house line or why line is actually on screen (log it as shown).
    var showsMotivation: Bool {
        if motivation != nil { return true }
        switch detail {
        case .quote, .why, .houseLine: return true
        case .fact, .line, nil: return false
        }
    }

    /// Number of statements drawn from user data (hook + detail). Always ≤ 1.
    var factCount: Int {
        (hookIsFact ? 1 : 0) + (detail.map { if case .fact = $0 { 1 } else { 0 } } ?? 0)
    }
}

// MARK: - Composer

/// The one builder for coach copy (Coach v2 design §3 [4], §4). Every surface (panel,
/// popover card, notification, in-session check) gets its words from here.
///
/// Rules: no shaming, no fake urgency, every number comes from `CoachFacts` or the target,
/// and a message carries at most one fact.
enum CoachMessageComposer {
    static let maxNameLength = 24

    static func compose(_ input: CoachComposerInput) -> CoachComposedMessage {
        let hook: (text: String, isFact: Bool)
        switch input.trigger {
        case .startNudge:
            hook = startHook(input)
        case .pseudoProductivity(let priority):
            hook = pseudoHook(input, priority: shortName(priority))
        case .inSessionDrift(let project, let app, let minutes):
            hook = driftHook(input.style, project: project.map(shortName), app: app.map(shortName), minutes: minutes)
        case .weeklyPriorities:
            hook = ("New week. Pick 1–3 priorities.", false)
        case .rescue(let rescue):
            hook = rescueHook(input, rescue)
        case .keepGoing(let step):
            hook = (CoachStarterBlock.keepGoingHook(step: step), false)
        case .momentum:
            hook = (CoachMomentumRamp.hook, false)
        case .starterStarted(let minutes):
            hook = (CoachStarterBlock.startedNotice(minutes: minutes), false)
        case .plannedStart(let cue):
            hook = plannedHook(input, cue)
        case .dailyPlan:
            hook = startCardHook(input)
        case .counterOffer(let reason):
            hook = counterOfferHook(input, reason: reason)
        }

        let detail = detail(input, hookIsFact: hook.isFact)
        return CoachComposedMessage(
            style: input.style,
            trigger: input.trigger,
            hook: hook.text,
            detail: detail,
            primaryTitle: primaryTitle(input),
            hookIsFact: hook.isFact,
            motivation: motivationLine(input, detail: detail)
        )
    }

    /// Challenger and Gentle prompts that ask for a start always carry a quote, house line or
    /// "my why" line, unless the detail already is one. Data style stays numbers-only.
    private static func motivationLine(_ input: CoachComposerInput, detail: CoachDetail?) -> CoachDetail? {
        guard input.style != .data else { return nil }
        switch detail {
        case .quote, .why, .houseLine: return nil
        case .fact, .line, nil: break
        }
        switch input.trigger {
        case .startNudge, .rescue, .pseudoProductivity, .plannedStart, .dailyPlan:
            return rotation(input)
        case .inSessionDrift, .weeklyPriorities, .keepGoing, .momentum, .starterStarted, .counterOffer:
            return nil
        }
    }

    private static func plannedHook(_ input: CoachComposerInput, _ cue: CoachPlannedCueContext) -> (String, Bool) {
        switch input.style {
        case .challenger:
            if cue.missedYesterday && cue.pushes == 0 { return ("\(cue.timeLabel). Missed yesterday. Never miss twice.", true) }
            if cue.pushes >= 2 { return ("Pushed \(cue.pushes) times. Start small. Start now.", true) }
            if cue.pushes == 1 { return ("\(cue.timeLabel). No more pushing. Begin.", false) }
            return ("\(cue.timeLabel). You said you'd start now.", false)
        case .data:
            return ("Planned: \(cue.timeLabel) · \(cue.minutes)m.", true)
        case .gentle:
            return ("It's \(cue.timeLabel), your planned block.", false)
        }
    }

    /// The start card never names the day's goal: a near, small goal gets started; a distal one
    /// gets postponed (Bandura & Schunk, 1981). It asks for the next block only.
    private static func startCardHook(_ input: CoachComposerInput) -> (String, Bool) {
        let first = input.facts.sessionsToday == 0
        switch input.style {
        case .challenger:
            if first && input.facts.missedYesterday { return ("Never miss twice. Start small.", false) }
            return (first ? "First block. Start small." : "Next block. Small is fine.", false)
        case .data:
            if first { return ("No block yet today. Next: \(input.target.minutes)m.", true) }
            return ("\(input.facts.sessionsToday) block\(input.facts.sessionsToday == 1 ? "" : "s") today. Next: \(input.target.minutes)m.", true)
        case .gentle:
            return (first ? "Ready for a small start?" : "Ready for one more small block?", false)
        }
    }

    private static func counterOfferHook(_ input: CoachComposerInput, reason: FocusCoachSkipReason) -> (String, Bool) {
        let minutes = input.target.minutes
        switch (reason, input.style) {
        case (.unclearNextStep, .gentle): return ("Let's spend \(minutes) minutes finding the next step?", false)
        case (.unclearNextStep, _): return ("No next step? Spend \(minutes) minutes finding it.", false)
        case (_, .gentle): return ("Then just \(minutes) minutes?", false)
        default: return ("Too big? Then \(minutes) minutes. Just open it.", false)
        }
    }

    /// Copy for a decision that arrived without composed copy (should not happen in v2).
    static func neutralFallback(isInSession: Bool) -> CoachComposedMessage {
        CoachComposedMessage(
            style: .gentle,
            trigger: isInSession ? .inSessionDrift(projectName: nil, appName: nil, minutesInApp: nil) : .startNudge,
            hook: isInSession ? "Still on your block?" : "Ready for a focus block?",
            detail: nil,
            primaryTitle: isInSession ? "Back to it" : "Start focus",
            hookIsFact: false
        )
    }

    // MARK: Hooks

    private static func startHook(_ input: CoachComposerInput) -> (String, Bool) {
        let facts = input.facts
        let minutes = input.target.minutes
        switch input.style {
        case .challenger:
            if let derailer = facts.derailer {
                return ("\(shortName(derailer.name)) has had \(duration(derailer.minutesThisWeek)) of you this week.", true)
            }
            if let pacing = facts.pacing, pacing.tier == .atRisk, let windowLeft = pacing.windowMinutesLeft, windowLeft > 0 {
                return ("\(pacing.percentOfGoal)% of today's goal. \(windowLeft)m of good window left today.", true)
            }
            if facts.missedYesterday && facts.sessionsToday == 0 {
                return ("Never miss twice.", false)
            }
            if facts.sessionsToday == 0 && facts.hasHistory {
                return ("Day \(facts.streakDays + 1). Show up.", true)
            }
            if let intent = facts.lastIntent.map(trimmedIntent), !intent.isEmpty {
                return ("You said: “\(intent)”.", false)
            }
            return input.seed % 2 == 0
                ? ("1% better daily = 37× in a year.", false)
                : ("Show up. \(minutes) minutes.", false)
        case .data:
            if let derailer = facts.derailer {
                return ("\(shortName(derailer.name)): \(duration(derailer.minutesThisWeek)) this week.", true)
            }
            if facts.goalMinutes > 0 {
                return ("\(facts.doneMinutesToday)m of \(facts.goalMinutes)m today.", true)
            }
            if let hour = facts.usualStartHourNow {
                return ("You usually start around \(String(format: "%02d", hour)):00.", true)
            }
            return ("Next block: \(minutes) minutes.", false)
        case .gentle:
            if let name = input.target.name {
                return ("Ready for \(shortName(name))?", false)
            }
            return ("Ready for a focus block?", false)
        }
    }

    private static func rescueHook(_ input: CoachComposerInput, _ rescue: CoachRescueContext) -> (String, Bool) {
        let fact = rescue.fact
        let priority = rescue.priorityName.map(shortName)
        switch input.style {
        case .challenger:
            if rescue.lateNight { return ("One small thing, then sleep.", false) }
            if rescue.level == .drifting, let worse = CoachOnePercent.worseStreak(days: input.facts.daysWithoutBlock) {
                return (worse, true)
            }
            if rescue.level == .drifting, case .pseudo = rescue.signal, let priority {
                return ("Is this \(priority), or does it just feel productive?", false)
            }
            if case .hopping = rescue.signal { return ("You're scanning, not doing.", false) }
            if let fact { return (fact, true) }
            return (rescue.level == .spiral ? "Pause. Shrink the next step." : "Come back to \(priority ?? "the work").", false)
        case .data:
            if let fact { return (fact, true) }
            return ("Drift level \(rescue.level.rawValue) of 3.", true)
        case .gentle:
            if rescue.lateNight { return ("One small thing, then sleep?", false) }
            switch rescue.level {
            case .ok, .drifting:
                return (priority.map { "Ready to come back to \($0)?" } ?? "Ready to come back?", false)
            case .lost:
                return ("Smaller step: just 10 minutes?", false)
            case .spiral:
                return ("Just \(rescue.starterMinutes) minutes to plan the next step?", false)
            }
        }
    }

    private static func rescueDetail(_ input: CoachComposerInput, _ rescue: CoachRescueContext, hookIsFact: Bool) -> CoachDetail? {
        if !hookIsFact, input.style != .gentle, let fact = rescue.fact {
            return .fact(fact)
        }
        if rescue.level >= .lost, input.style != .gentle,
           let share = CoachOnePercent.todayShare(give: rescue.ask.minutes) {
            return .line(share)
        }
        if input.style == .data { return nil }
        return rotation(input)
    }

    private static func pseudoHook(_ input: CoachComposerInput, priority: String) -> (String, Bool) {
        switch input.style {
        case .challenger:
            return ("Is this \(priority), or does it just feel productive?", false)
        case .data:
            if let minutes = input.facts.contextMinutes, let app = input.facts.contextAppName {
                return ("\(minutes)m in \(shortName(app)). Is this \(priority)?", true)
            }
            return ("Is this \(priority), or does it just feel productive?", false)
        case .gentle:
            return ("Quick check: is this \(priority)?", false)
        }
    }

    private static func driftHook(_ style: CoachStyle, project: String?, app: String?, minutes: Int?) -> (String, Bool) {
        switch style {
        case .challenger:
            return ("Back to \(project ?? "your block").", false)
        case .data:
            if let app, let minutes, minutes > 0 {
                return ("\(minutes)m in \(app) this block.", true)
            }
            return ("Off-plan for \(project ?? "this block")?", false)
        case .gentle:
            return ("Still on \(project ?? "your block")?", false)
        }
    }

    // MARK: Detail (at most one fact)

    private static func detail(_ input: CoachComposerInput, hookIsFact: Bool) -> CoachDetail? {
        let facts = input.facts
        switch input.trigger {
        case .rescue(let rescue):
            return rescueDetail(input, rescue, hookIsFact: hookIsFact)
        case .keepGoing:
            return rotation(input) ?? .line(CoachOnePercent.compounding)
        case .momentum:
            return .line("Starting was the hard part. That part is done.")
        case .starterStarted:
            return .line("What's the very next step? Type it in the menu bar.")
        case .plannedStart(let cue):
            if !hookIsFact, input.style != .gentle || facts.doneMinutesToday > 0,
               facts.goalMinutes > 0 {
                return .fact("\(facts.doneMinutesToday)m of \(facts.goalMinutes)m today.")
            }
            if input.style == .data { return nil }
            return .line("Too much? \(cue.starterMinutes) minutes still counts.")
        case .dailyPlan:
            switch input.style {
            case .challenger: return .line("Starting is the hard part. Make it small enough to start now.")
            case .data: return .line("Short, near goals raise starts and persistence (Bandura & Schunk, 1981).")
            case .gentle: return .line("Five minutes still counts.")
            }
        case .counterOffer(let reason):
            if reason == .unclearNextStep {
                return .line("Write the next step down. Then the work has a door.")
            }
            return input.style == .data
                ? .line("Name the obstacle, then plan around it: if-then plans help (g = 0.34).")
                : .line("You don't have to want to. Just start the small version.")
        case .weeklyPriorities:
            switch input.style {
            case .challenger: return .line("What will you finish by Sunday?")
            case .data: return .line("The coach checks your blocks against them.")
            case .gentle: return .line("It takes 30 seconds.")
            }

        case .inSessionDrift(_, let app, let minutes):
            if !hookIsFact, let app, let minutes, minutes > 0 {
                return .fact("\(minutes)m in \(shortName(app)) this block.")
            }
            return input.style == .data ? nil : .line("Your time so far is saved.")

        case .pseudoProductivity:
            if !hookIsFact, input.style != .gentle,
               let minutes = facts.contextMinutes, let app = facts.contextAppName {
                return .fact("\(minutes)m in \(shortName(app)) so far.")
            }
            switch input.style {
            case .challenger: return .line("Feeling busy isn't progress.")
            case .data: return nil
            case .gentle: return .line("If it's planned, I'll leave you be.")
            }

        case .startNudge:
            if !hookIsFact, input.style != .gentle || facts.sessionsToday > 0,
               let fact = startFact(facts) {
                return .fact(fact)
            }
            if input.style == .data { return nil }
            return rotation(input)
        }
    }

    private static func startFact(_ facts: CoachFacts) -> String? {
        if facts.goalMinutes > 0 && (facts.doneMinutesToday > 0 || facts.sessionsToday > 0) {
            return "\(facts.doneMinutesToday)m of \(facts.goalMinutes)m today."
        }
        if let since = facts.minutesSinceLastSession, since >= 60 {
            return "Last block ended \(duration(since)) ago."
        }
        if facts.goalMinutes > 0 {
            return "\(facts.doneMinutesToday)m of \(facts.goalMinutes)m today."
        }
        return nil
    }

    /// Alternates the user's "My why" lines with vetted quotes.
    private static func rotation(_ input: CoachComposerInput) -> CoachDetail? {
        if let picked = input.pickedDetail { return picked }
        if input.pickerExhausted { return nil }
        let whys = input.whyLines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        // House lines only for Challenger; sourced quotes otherwise.
        let quotes = input.quotes.filter { $0.isHouseLine ? input.style == .challenger : !$0.source.isEmpty }
        let seed = abs(input.seed)
        if !whys.isEmpty && (seed % 2 == 0 || quotes.isEmpty) {
            return .why(whys[(seed / 2) % whys.count])
        }
        if !quotes.isEmpty {
            let quote = quotes[seed % quotes.count]
            return quote.isHouseLine
                ? .houseLine(quote.resolvedText(starterMinutes: input.starterMinutes))
                : .quote(quote)
        }
        return nil
    }

    // MARK: Action

    private static func primaryTitle(_ input: CoachComposerInput) -> String {
        switch input.trigger {
        case .weeklyPriorities:
            return "Set priorities"
        case .inSessionDrift:
            return "Back to it"
        case .pseudoProductivity(let priority):
            return "It's \(shortName(priority)): start a block"
        case .startNudge:
            return startTitle(input.target)
        case .rescue(let rescue):
            return rescue.ask.title
        case .keepGoing:
            return "Keep going · \(CoachStarterBlock.keepGoingMinutes)m"
        case .momentum:
            return "Make it \(CoachMomentumRamp.targetMinutes)"
        case .starterStarted:
            return ""
        case .dailyPlan, .counterOffer:
            return startTitle(input.target)
        case .plannedStart(let cue):
            var target = input.target
            target.minutes = cue.minutes
            if let name = cue.priorityName { target.name = name }
            return startTitle(target)
        }
    }

    static func startTitle(_ target: CoachStartTarget) -> String {
        if target.findNextStep { return "Find the next step · \(target.minutes)m" }
        if let name = target.name, !name.isEmpty {
            return "Start \(target.minutes)m on \(shortName(name))"
        }
        return "Start \(target.minutes)m focus"
    }

    // MARK: Formatting

    static func shortName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxNameLength else { return trimmed }
        return String(trimmed.prefix(maxNameLength - 1)) + "…"
    }

    private static func trimmedIntent(_ intent: String) -> String {
        let line = intent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard line.count > 48 else { return line }
        return String(line.prefix(47)) + "…"
    }

    /// "2h 10m", "45m".
    static func duration(_ minutes: Int) -> String {
        FocusCoachContext.formatDuration(seconds: max(0, minutes) * 60)
    }
}
