import Foundation

// Coach v3 §3.6: what the coach learned, shown to the user, plus advice that is computed from
// the user's own data and tied to a published finding. Pure; the companion views feed it.

/// One piece of advice: a title, one sentence from the user's data, and its source.
struct CoachAdvice: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable {
        case neverMissTwice
        case decideWhen
        case anchorWindow
        case shrinkStart
        case nameTheOutput
        case freshStart
        case goalGradient
        case plansWork
    }

    let kind: Kind
    let symbol: String
    let title: String
    let body: String
    /// "Gollwitzer & Sheeran, 2006"
    let citation: String
    /// Full reference for the tooltip.
    let reference: String

    var id: String { kind.rawValue }
}

/// A learned start window for today, with how much likelier a start is than in the average hour.
struct CoachWindowInsight: Equatable, Sendable, Identifiable {
    let start: Date
    let lift: Double
    var id: Date { start }
}

/// One day in the "never miss twice" chain.
struct CoachChainDay: Equatable, Sendable, Identifiable {
    enum Mark: String, Sendable {
        case goal
        case partial
        case missed
        /// Today, nothing yet.
        case open
    }

    let day: Date
    let minutes: Int
    let mark: Mark
    var id: Date { day }
}

enum CoachInsights {
    struct SessionInput: Sendable {
        let start: Date
        let seconds: TimeInterval
        /// `SessionOutcome` rating, if the user rated it.
        let outcome: SessionOutcome?
    }

    struct PlanInput: Sendable {
        let day: Date
        let startAt: Date
        let status: PlannedBlockStatus
        let pushes: Int
    }

    struct PromptInput: Sendable {
        let deliveredAt: Date
        let outcome: FocusCoachOutcome?
        let reward: Double?
        let isPlanned: Bool
    }

    struct Summary: Sendable {
        let chain: [CoachChainDay]
        let windowsToday: [CoachWindowInsight]
        let bestHourThisWeekday: CoachWindowInsight?
        /// Plans in the lookback (excluding today's still-open ones), and how many were kept.
        let plansMade: Int
        let plansKept: Int
        /// Share of days with a start: days with a plan vs days without (nil below 3 days each).
        let startRatePlannedDays: Double?
        let startRateUnplannedDays: Double?
        /// Coach prompts the user actually saw (no planned cues), and how many led to a start.
        let promptsSeen: Int
        let promptsLedToStart: Int
        let learnedFromStarts: Int
        let isLearned: Bool
        let advice: [CoachAdvice]
    }

    static let lookbackDays = 14
    static let maxAdvice = 3

    static func summary(
        now: Date,
        goalMinutes: Int,
        sessions: [SessionInput],
        plans: [PlanInput],
        prompts: [PromptInput],
        model: CoachAvailabilityModel,
        starterMinutes: Int,
        calendar: Calendar = .current
    ) -> Summary {
        let today = calendar.startOfDay(for: now)
        let chain = chainDays(now: now, goalMinutes: goalMinutes, sessions: sessions, calendar: calendar)
        let windows = windowsToday(now: now, model: model, calendar: calendar)
        let best = bestHour(on: now, model: model, calendar: calendar)

        let lookbackStart = calendar.date(byAdding: .day, value: -lookbackDays, to: today) ?? today
        let closedPlans = plans.filter { $0.day >= lookbackStart && ($0.day < today || $0.status != .planned) }
        let kept = closedPlans.filter { $0.status == .started }.count

        // Start rate on days with and without a plan (before today).
        var plannedDays = 0, plannedStarts = 0, unplannedDays = 0, unplannedStarts = 0
        let planDays = Set(plans.map { calendar.startOfDay(for: $0.day) })
        for offset in 1...lookbackDays {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let started = chain.first { calendar.isDate($0.day, inSameDayAs: day) }.map { $0.minutes > 0 }
                ?? sessions.contains { calendar.isDate($0.start, inSameDayAs: day) }
            if planDays.contains(day) {
                plannedDays += 1
                if started { plannedStarts += 1 }
            } else {
                unplannedDays += 1
                if started { unplannedStarts += 1 }
            }
        }
        let plannedRate = plannedDays >= 3 ? Double(plannedStarts) / Double(plannedDays) : nil
        let unplannedRate = unplannedDays >= 3 ? Double(unplannedStarts) / Double(unplannedDays) : nil

        let seen = prompts.filter { !$0.isPlanned && $0.deliveredAt >= lookbackStart && $0.outcome != .unseen }
        let ledToStart = seen.filter { ($0.reward ?? 0) >= 1 || $0.outcome == .improved }.count

        let advice = adviceList(
            now: now,
            goalMinutes: goalMinutes,
            chain: chain,
            plans: plans,
            sessions: sessions,
            best: best,
            plannedRate: plannedRate,
            unplannedRate: unplannedRate,
            starterMinutes: starterMinutes,
            calendar: calendar
        )

        let isLearned: Bool = { if case .learned = model.mode { return true }; return false }()
        return Summary(
            chain: chain,
            windowsToday: windows,
            bestHourThisWeekday: best,
            plansMade: closedPlans.count,
            plansKept: kept,
            startRatePlannedDays: plannedRate,
            startRateUnplannedDays: unplannedRate,
            promptsSeen: seen.count,
            promptsLedToStart: ledToStart,
            learnedFromStarts: model.totalStarts,
            isLearned: isLearned,
            advice: advice
        )
    }

    // MARK: Chain

    /// The last 14 days, oldest first, ending today.
    static func chainDays(now: Date, goalMinutes: Int, sessions: [SessionInput], calendar: Calendar = .current) -> [CoachChainDay] {
        let today = calendar.startOfDay(for: now)
        var minutesByDay: [Date: Double] = [:]
        for session in sessions where session.seconds > 0 {
            minutesByDay[calendar.startOfDay(for: session.start), default: 0] += session.seconds / 60
        }
        return (0..<lookbackDays).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let minutes = Int(minutesByDay[day] ?? 0)
            let mark: CoachChainDay.Mark
            if goalMinutes > 0 && minutes >= goalMinutes {
                mark = .goal
            } else if minutes > 0 {
                mark = .partial
            } else {
                mark = offset == 0 ? .open : .missed
            }
            return CoachChainDay(day: day, minutes: minutes, mark: mark)
        }
    }

    // MARK: Windows

    /// Learned good windows still ahead today (hour starts), strongest lift first, at most 3.
    static func windowsToday(now: Date, model: CoachAvailabilityModel, calendar: Calendar = .current) -> [CoachWindowInsight] {
        guard case .learned = model.mode, model.meanRate > 0,
              let hourStart = calendar.dateInterval(of: .hour, for: now)?.start,
              let dayEnd = calendar.dateInterval(of: .day, for: now)?.end else { return [] }
        var result: [CoachWindowInsight] = []
        var cursor = hourStart
        while cursor < dayEnd {
            if model.isGoodWindow(cursor) {
                result.append(CoachWindowInsight(start: cursor, lift: model.p(cursor) / model.meanRate))
            }
            guard let next = calendar.date(byAdding: .hour, value: 1, to: cursor) else { break }
            cursor = next
        }
        return Array(result.sorted { $0.lift > $1.lift }.prefix(3)).sorted { $0.start < $1.start }
    }

    /// The strongest hour on `date`'s weekday (learned mode only).
    static func bestHour(on date: Date, model: CoachAvailabilityModel, calendar: Calendar = .current) -> CoachWindowInsight? {
        guard case .learned = model.mode, model.meanRate > 0, let hour = model.usualStartHour(on: date),
              let start = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: date) else { return nil }
        return CoachWindowInsight(start: start, lift: model.p(start) / model.meanRate)
    }

    // MARK: Advice

    static func adviceList(
        now: Date,
        goalMinutes: Int,
        chain: [CoachChainDay],
        plans: [PlanInput],
        sessions: [SessionInput],
        best: CoachWindowInsight?,
        plannedRate: Double?,
        unplannedRate: Double?,
        starterMinutes: Int,
        calendar: Calendar = .current
    ) -> [CoachAdvice] {
        var list: [CoachAdvice] = []
        let today = chain.last
        let yesterday = chain.dropLast().last
        let todayMinutes = today?.minutes ?? 0

        if yesterday?.mark == .missed && todayMinutes == 0 {
            list.append(CoachAdvice(
                kind: .neverMissTwice, symbol: "link",
                title: "Never miss twice",
                body: "Yesterday had no block. One miss barely dents a habit; two in a row start a new one. \(starterMinutes) minutes today keeps the chain.",
                citation: "Lally et al., 2010",
                reference: "Lally, van Jaarsveld, Potts & Wardle (2010). How are habits formed. European Journal of Social Psychology 40(6), 998–1009."
            ))
        }

        let goalMet = goalMinutes > 0 && todayMinutes >= goalMinutes
        let hasPlanToday = plans.contains { calendar.isDate($0.day, inSameDayAs: now) }
        if !hasPlanToday && !goalMet {
            list.append(CoachAdvice(
                kind: .decideWhen, symbol: "calendar.badge.clock",
                title: "Decide when, today",
                body: "Pick a start time now. Deciding when and where in advance has a medium-to-large effect on actually starting.",
                citation: "Gollwitzer & Sheeran, 2006",
                reference: "Gollwitzer & Sheeran (2006). Implementation intentions and goal achievement: a meta-analysis. Advances in Experimental Social Psychology 38, 69–119."
            ))
        }

        if let plannedRate, let unplannedRate, plannedRate > unplannedRate + 0.1 {
            list.append(CoachAdvice(
                kind: .plansWork, symbol: "checkmark.seal",
                title: "Planning works for you",
                body: "On days you plan a time you start \(percent(plannedRate)) of the time, versus \(percent(unplannedRate)) when you don't.",
                citation: "Your last \(lookbackDays) days",
                reference: "Computed from your own focus blocks and plans."
            ))
        }

        if let best, best.lift >= 1.5 {
            let hour = TimerViewModel.clockLabel(best.start, calendar: calendar)
            list.append(CoachAdvice(
                kind: .anchorWindow, symbol: "clock.badge.checkmark",
                title: "Anchor it at \(hour)",
                body: String(format: "You're %.1f× likelier to start at %@ on this weekday than in an average hour. The same time daily turns the clock into the cue.", best.lift, hour),
                citation: "Wood & Neal, 2007",
                reference: "Wood & Neal (2007). A new look at habits and the habit–goal interface. Psychological Review 114(4), 843–863."
            ))
        }

        let recentPlans = plans.filter { $0.status != .planned }.suffix(7)
        if recentPlans.count >= 3 {
            let pushes = Double(recentPlans.map(\.pushes).reduce(0, +)) / Double(recentPlans.count)
            let missed = recentPlans.filter { $0.status == .missed || $0.status == .skipped }.count
            if pushes >= 1 || Double(missed) / Double(recentPlans.count) >= 0.5 {
                list.append(CoachAdvice(
                    kind: .shrinkStart, symbol: "arrow.down.right.and.arrow.up.left",
                    title: "Make the start smaller",
                    body: "Your plans get pushed or missed. Start with \(starterMinutes) minutes: the aversive part is starting, and it shrinks once you begin.",
                    citation: "Steel, 2007",
                    reference: "Steel (2007). The nature of procrastination: a meta-analytic and theoretical review. Psychological Bulletin 133(1), 65–94."
                ))
            }
        }

        let rated = sessions.suffix(30).compactMap(\.outcome)
        if rated.count >= 4 {
            let busy = rated.filter { $0 == .busywork }.count
            if Double(busy) / Double(rated.count) >= 0.4 {
                list.append(CoachAdvice(
                    kind: .nameTheOutput, symbol: "target",
                    title: "Name the output first",
                    body: "\(busy) of your last \(rated.count) rated blocks were busywork. Before you start, write what will exist at the end. Specific goals beat \"do your best\".",
                    citation: "Locke & Latham, 2002",
                    reference: "Locke & Latham (2002). Building a practically useful theory of goal setting and task motivation. American Psychologist 57(9), 705–717."
                ))
            }
        }

        let weekday = calendar.component(.weekday, from: now)
        let dayOfMonth = calendar.component(.day, from: now)
        if weekday == 2 || dayOfMonth == 1 {
            list.append(CoachAdvice(
                kind: .freshStart, symbol: "sunrise",
                title: weekday == 2 ? "Monday is a fresh start" : "A new month is a fresh start",
                body: "Temporal landmarks make people likelier to start on goals. Use today to set this week's time.",
                citation: "Dai, Milkman & Riis, 2014",
                reference: "Dai, Milkman & Riis (2014). The fresh start effect. Management Science 60(10), 2563–2582."
            ))
        }

        if goalMinutes > 0, todayMinutes > 0, !goalMet, Double(todayMinutes) / Double(goalMinutes) >= 0.5 {
            list.append(CoachAdvice(
                kind: .goalGradient, symbol: "chart.line.uptrend.xyaxis",
                title: "You're past halfway",
                body: "\(todayMinutes) of \(goalMinutes) minutes. Effort rises as a goal gets close; one more block finishes today.",
                citation: "Kivetz, Urminsky & Zheng, 2006",
                reference: "Kivetz, Urminsky & Zheng (2006). The goal-gradient hypothesis resurrected. Journal of Marketing Research 43(1), 39–58."
            ))
        }

        return Array(list.prefix(maxAdvice))
    }

    static func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }
}
