import Foundation

/// When a message is shown (rescue loop design §4). Quotes are tagged with the situations they fit.
enum CoachSituation: String, CaseIterable, Sendable, Codable {
    /// A learned window opens.
    case start
    /// Drifting or lost (L1–L2).
    case drift
    /// Spiral (L3, pause screen).
    case spiral
    /// After a missed day.
    case comeback
    /// On a run of days.
    case streak
    /// After 23:00: "one small thing, then sleep".
    case lateNight
    /// After a starter block.
    case keepGoing

    /// 23:00 or later (and before 05:00) is late night.
    static func isLateNight(_ date: Date, calendar: Calendar = .current) -> Bool {
        let hour = calendar.component(.hour, from: date)
        return hour >= 23 || hour < 5
    }
}

/// A quote the coach may show, with where it comes from.
struct CoachQuote: Sendable, Equatable, Hashable, Identifiable {
    /// Stable id for learning and the no-repeat rule.
    let id: String
    let text: String
    let author: String
    /// Book, chapter or the honest origin ("Widely attributed").
    let source: String
    /// Extra honesty about the attribution, e.g. "widely attributed; original source unverified".
    let attributionNote: String?
    let situations: Set<CoachSituation>
    /// A FocusFlow Challenger house line: no author, no quotation marks, no attribution line.
    /// Shown only for `.challenger`. Its `text` may hold `{N}`, replaced by the starter length.
    var isHouseLine: Bool = false

    /// A question to answer, not a line to read (Dan Koe's interrupts).
    var isQuestion: Bool = false

    /// "“Discipline equals freedom.” — Jocko Willink". A house line is its text alone.
    var formatted: String { isHouseLine ? text : "“\(text)” — \(author)" }

    /// The text to show. House lines replace `{N}` with the starter block length (clamped, like
    /// `CoachOnePercent.todayShare(give:)`); quotes are returned unchanged.
    func resolvedText(starterMinutes: Int) -> String {
        guard isHouseLine else { return text }
        return text.replacingOccurrences(of: "{N}", with: String(CoachStarterBlock.clampedMinutes(starterMinutes)))
    }

    /// "Seneca, On the Shortness of Life" plus the note when there is one.
    var attribution: String {
        let base = "\(author), \(source)"
        guard let attributionNote, !attributionNote.isEmpty else { return base }
        return "\(base) (\(attributionNote))"
    }

    var isWidelyAttributed: Bool {
        attributionNote?.localizedCaseInsensitiveContains("widely attributed") == true
            || source.localizedCaseInsensitiveContains("widely attributed")
    }
}

/// The only quotes the coach shows: exactly the verified seed list in the rescue loop design §4.
/// Do not add quotes without a checked source. The Coach v1 bank (`FocusCoachMotivationalQuotes`)
/// had no verified sources and was removed.
enum CoachQuoteLibrary {
    static let all: [CoachQuote] = [
        CoachQuote(
            id: "clear-systems",
            text: "You do not rise to the level of your goals. You fall to the level of your systems.",
            author: "James Clear",
            source: "Atomic Habits (2018)",
            attributionNote: nil,
            situations: [.start, .drift, .comeback]
        ),
        CoachQuote(
            id: "clear-vote",
            text: "Every action you take is a vote for the type of person you wish to become.",
            author: "James Clear",
            source: "Atomic Habits (2018)",
            attributionNote: nil,
            situations: [.start, .streak, .keepGoing, .lateNight]
        ),
        CoachQuote(
            id: "clear-never-miss-twice",
            text: "Never miss twice.",
            author: "James Clear",
            source: "Atomic Habits (2018)",
            attributionNote: nil,
            situations: [.comeback, .streak]
        ),
        CoachQuote(
            id: "willink-discipline-freedom",
            text: "Discipline equals freedom.",
            author: "Jocko Willink",
            source: "Discipline Equals Freedom (2017)",
            attributionNote: "the book's title",
            situations: [.drift, .spiral, .start]
        ),
        CoachQuote(
            id: "durant-excellence-habit",
            text: "We are what we repeatedly do. Excellence, then, is not an act, but a habit.",
            author: "Will Durant",
            source: "The Story of Philosophy (1926)",
            attributionNote: "summarising Aristotle; often misattributed to Aristotle himself",
            situations: [.streak, .start, .keepGoing]
        ),
        CoachQuote(
            id: "king-amateurs",
            text: "Amateurs sit and wait for inspiration, the rest of us just get up and go to work.",
            author: "Stephen King",
            source: "On Writing (2000)",
            attributionNote: nil,
            situations: [.start, .drift, .spiral]
        ),
        CoachQuote(
            id: "dillard-days",
            text: "How we spend our days is, of course, how we spend our lives.",
            author: "Annie Dillard",
            source: "The Writing Life (1989)",
            attributionNote: nil,
            situations: [.drift, .spiral, .lateNight]
        ),
        CoachQuote(
            id: "seneca-short-life",
            text: "It is not that we have a short time to live, but that we waste a lot of it.",
            author: "Seneca",
            source: "On the Shortness of Life",
            attributionNote: nil,
            situations: [.spiral, .drift]
        ),
        CoachQuote(
            id: "aurelius-obstacle",
            text: "The impediment to action advances action. What stands in the way becomes the way.",
            author: "Marcus Aurelius",
            source: "Meditations 5.20",
            attributionNote: nil,
            situations: [.spiral, .comeback]
        ),
        CoachQuote(
            id: "rubin-every-day",
            text: "What you do every day matters more than what you do once in a while.",
            author: "Gretchen Rubin",
            source: "her writing on habits",
            attributionNote: "her own maxim",
            situations: [.streak, .start, .lateNight, .comeback]
        ),
        CoachQuote(
            id: "gregorek-hard-choices",
            text: "Hard choices, easy life. Easy choices, hard life.",
            author: "Jerzy Gregorek",
            source: "his own maxim",
            attributionNote: nil,
            situations: [.drift, .spiral]
        ),
        CoachQuote(
            id: "rohn-motivation-habit",
            text: "Motivation is what gets you started. Habit is what keeps you going.",
            author: "Jim Rohn",
            source: "Widely attributed",
            attributionNote: "widely attributed; original source unverified",
            situations: [.keepGoing, .start, .streak]
        ),
        CoachQuote(
            id: "rohn-discipline-bridge",
            text: "Discipline is the bridge between goals and accomplishment.",
            author: "Jim Rohn",
            source: "Widely attributed",
            attributionNote: "widely attributed; original source unverified",
            situations: [.start, .drift]
        ),
        CoachQuote(
            id: "levenson-clock",
            text: "Don't watch the clock; do what it does. Keep going.",
            author: "Sam Levenson",
            source: "Widely attributed",
            attributionNote: "widely attributed; original source unverified",
            situations: [.keepGoing, .lateNight]
        ),
        CoachQuote(
            id: "picasso-inspiration",
            text: "Inspiration exists, but it has to find you working.",
            author: "Pablo Picasso",
            source: "Widely attributed",
            attributionNote: "widely attributed; original source unverified",
            situations: [.start, .keepGoing, .spiral]
        ),
        CoachQuote(
            id: "karen-lamb-year-from-now",
            text: "A year from now you may wish you had started today.",
            author: "Karen Lamb",
            // No book or speech to cite: the honest origin is "widely attributed", as for the other unsourced lines.
            source: "Widely attributed",
            attributionNote: "widely attributed (earliest: 1994)",
            situations: [.start, .comeback]
        ),
        CoachQuote(
            id: "emmett-dread",
            text: "The dread of doing a task uses up more time and energy than doing the task itself.",
            author: "Rita Emmett",
            source: "The Procrastinator's Handbook",
            attributionNote: "attributed",
            situations: [.start, .spiral]
        ),
        CoachQuote(
            id: "seneca-nothing-ours",
            text: "Nothing, Lucilius, is ours, except time.",
            author: "Seneca",
            source: "Moral Letters to Lucilius, Letter 1",
            attributionNote: nil,
            situations: [.drift, .spiral, .lateNight]
        ),
        CoachQuote(
            id: "seneca-each-day-a-life",
            text: "Begin at once to live, and count each separate day as a separate life.",
            author: "Seneca",
            source: "Moral Letters to Lucilius, Letter 101",
            attributionNote: "attributed",
            situations: [.start, .comeback]
        ),
        CoachQuote(
            id: "aurelius-ten-thousand-years",
            text: "Do not act as if thou wert going to live ten thousand years.",
            author: "Marcus Aurelius",
            source: "Meditations 4.17 (tr. George Long)",
            attributionNote: nil,
            situations: [.drift, .spiral]
        ),
        CoachQuote(
            id: "franklin-lost-time",
            text: "Lost time is never found again.",
            author: "Benjamin Franklin",
            source: "The Way to Wealth (1758)",
            attributionNote: nil,
            situations: [.drift, .spiral, .lateNight]
        ),
        CoachQuote(
            id: "clear-trajectory",
            text: "You should be far more concerned with your current trajectory than with your current results.",
            author: "James Clear",
            source: "Atomic Habits",
            attributionNote: "attributed",
            situations: [.comeback, .keepGoing]
        ),
        CoachQuote(
            id: "clear-compound-interest",
            text: "Habits are the compound interest of self-improvement.",
            author: "James Clear",
            source: "Atomic Habits",
            attributionNote: "attributed",
            situations: [.streak, .keepGoing]
        ),
        CoachQuote(
            id: "newport-clarity",
            text: "Clarity about what matters provides clarity about what does not.",
            author: "Cal Newport",
            source: "Deep Work",
            attributionNote: "attributed",
            situations: [.start]
        ),
        // Challenger house lines. Not quotes: no author, no quotation marks, no attribution line.
        CoachQuote(
            id: "house-intelligence-discipline",
            text: "Intelligence without discipline is wasted potential. Discipline without genius still wins.",
            author: "",
            source: "",
            attributionNote: nil,
            situations: [.drift, .spiral],
            isHouseLine: true
        ),
        CoachQuote(
            id: "house-cost-of-procrastination",
            text: "The cost of procrastination isn't lost time. It's the version of you that never happened.",
            author: "",
            source: "",
            attributionNote: nil,
            situations: [.drift, .spiral, .lateNight],
            isHouseLine: true
        ),
        CoachQuote(
            id: "house-give-it-minutes",
            text: "Give it {N} minutes. If you still want to quit after that, you can.",
            author: "",
            source: "",
            attributionNote: nil,
            situations: [.start, .spiral],
            isHouseLine: true
        ),
        // Misattributed to Mark Twain; the origin is anonymous (Quote Investigator, 2018). It is
        // a house line for that reason: FocusFlow does not claim an author for it.
        CoachQuote(
            id: "house-secret-getting-started",
            text: "The secret of getting ahead is getting started.",
            author: "",
            source: "",
            attributionNote: nil,
            situations: [.start],
            isHouseLine: true
        ),
        // Dan Koe, "How to fix your entire life in 1 day" (newsletter, 23 Dec 2025), checked against
        // the original post on 2026-10-28. Statements, then his "interrupt" questions: they are meant
        // to be asked throughout the day, so they ground the daily reminder line and the rescue loop.
        CoachQuote(
            id: "koe-not-the-person",
            text: "You aren't where you want to be because you aren't the person who would be there.",
            author: "Dan Koe",
            source: "How to fix your entire life in 1 day (letters.thedankoe.com, 23 Dec 2025)",
            attributionNote: nil,
            situations: [.start, .drift, .comeback]
        ),
        CoachQuote(
            id: "koe-afraid",
            text: "You aren't where you want to be because you're afraid to be there.",
            author: "Dan Koe",
            source: "How to fix your entire life in 1 day (letters.thedankoe.com, 23 Dec 2025)",
            attributionNote: nil,
            situations: [.start, .comeback]
        ),
        CoachQuote(
            id: "koe-learn-from-mistakes",
            text: "The mark of low intelligence is the inability to learn from your mistakes.",
            author: "Dan Koe",
            source: "How to fix your entire life in 1 day (letters.thedankoe.com, 23 Dec 2025)",
            attributionNote: nil,
            situations: [.comeback]
        ),
        CoachQuote(
            id: "koe-progress",
            text: "Enjoyment is found in progress.",
            author: "Dan Koe",
            source: "How to fix your entire life in 1 day (letters.thedankoe.com, 23 Dec 2025)",
            attributionNote: nil,
            situations: [.start, .keepGoing, .streak]
        ),
        CoachQuote(
            id: "koe-anti-vision-stakes",
            text: "Your anti-vision is what's at stake.",
            author: "Dan Koe",
            source: "How to fix your entire life in 1 day (letters.thedankoe.com, 23 Dec 2025)",
            attributionNote: nil,
            situations: [.start, .drift]
        ),
        CoachQuote(
            id: "koe-levers-quests",
            text: "Your daily levers are the quests.",
            author: "Dan Koe",
            source: "How to fix your entire life in 1 day (letters.thedankoe.com, 23 Dec 2025)",
            attributionNote: nil,
            situations: [.start]
        ),
        CoachQuote(
            id: "koe-q-avoiding",
            text: "What am I avoiding right now by doing what I'm doing?",
            author: "Dan Koe",
            source: "How to fix your entire life in 1 day (letters.thedankoe.com, 23 Dec 2025)",
            attributionNote: nil,
            situations: [.drift, .spiral, .comeback],
            isQuestion: true
        ),
        CoachQuote(
            id: "koe-q-filmed",
            text: "If someone filmed the last two hours, what would they conclude I want from my life?",
            author: "Dan Koe",
            source: "How to fix your entire life in 1 day (letters.thedankoe.com, 23 Dec 2025)",
            attributionNote: nil,
            situations: [.drift, .spiral, .comeback],
            isQuestion: true
        ),
        CoachQuote(
            id: "koe-q-toward",
            text: "Am I moving toward the life I hate or the life I want?",
            author: "Dan Koe",
            source: "How to fix your entire life in 1 day (letters.thedankoe.com, 23 Dec 2025)",
            attributionNote: nil,
            situations: [.drift, .spiral, .comeback],
            isQuestion: true
        ),
        CoachQuote(
            id: "koe-q-pretending",
            text: "What's the most important thing I'm pretending isn't important?",
            author: "Dan Koe",
            source: "How to fix your entire life in 1 day (letters.thedankoe.com, 23 Dec 2025)",
            attributionNote: nil,
            situations: [.drift, .spiral, .comeback],
            isQuestion: true
        ),
        CoachQuote(
            id: "koe-q-identity-protection",
            text: "What did I do today out of identity protection rather than genuine desire?",
            author: "Dan Koe",
            source: "How to fix your entire life in 1 day (letters.thedankoe.com, 23 Dec 2025)",
            attributionNote: nil,
            situations: [.drift, .spiral, .comeback],
            isQuestion: true
        ),
        CoachQuote(
            id: "koe-q-alive",
            text: "When did I feel most alive today? When did I feel most dead?",
            author: "Dan Koe",
            source: "How to fix your entire life in 1 day (letters.thedankoe.com, 23 Dec 2025)",
            attributionNote: nil,
            situations: [.drift, .spiral, .comeback],
            isQuestion: true
        ),
        CoachQuote(
            id: "koe-q-safety",
            text: "Where in my life am I trading aliveness for safety?",
            author: "Dan Koe",
            source: "How to fix your entire life in 1 day (letters.thedankoe.com, 23 Dec 2025)",
            attributionNote: nil,
            situations: [.drift, .spiral, .comeback],
            isQuestion: true
        ),
        CoachQuote(
            id: "koe-q-smallest-version",
            text: "What's the smallest version of the person I want to become that I could be tomorrow?",
            author: "Dan Koe",
            source: "How to fix your entire life in 1 day (letters.thedankoe.com, 23 Dec 2025)",
            attributionNote: nil,
            situations: [.drift, .spiral, .comeback],
            isQuestion: true
        ),
        CoachQuote(
            id: "koe-q-complain",
            text: "What do you complain about repeatedly but never actually change?",
            author: "Dan Koe",
            source: "How to fix your entire life in 1 day (letters.thedankoe.com, 23 Dec 2025)",
            attributionNote: nil,
            situations: [.drift, .spiral, .comeback],
            isQuestion: true
        ),
        CoachQuote(
            id: "koe-q-embarrassing",
            text: "What is the most embarrassing reason you haven't changed?",
            author: "Dan Koe",
            source: "How to fix your entire life in 1 day (letters.thedankoe.com, 23 Dec 2025)",
            attributionNote: nil,
            situations: [.drift, .spiral, .comeback],
            isQuestion: true
        ),
        CoachQuote(
            id: "koe-q-tuesday",
            text: "If absolutely nothing changes for the next five years, describe an average Tuesday.",
            author: "Dan Koe",
            source: "How to fix your entire life in 1 day (letters.thedankoe.com, 23 Dec 2025)",
            attributionNote: nil,
            situations: [.drift, .spiral, .comeback],
            isQuestion: true
        ),
        CoachQuote(
            id: "koe-q-this-week",
            text: "What is one thing you would do this week if you were already that person?",
            author: "Dan Koe",
            source: "How to fix your entire life in 1 day (letters.thedankoe.com, 23 Dec 2025)",
            attributionNote: nil,
            situations: [.drift, .spiral, .comeback],
            isQuestion: true
        ),
    ]

    /// Every quote the coach may rotate through. Kept as a name for older callers.
    static var rotation: [CoachQuote] { all }

    /// Quotes and house lines for a situation. House lines are Challenger-only.
    static func quotes(for situation: CoachSituation, style: CoachStyle) -> [CoachQuote] {
        all.filter { $0.situations.contains(situation) && (!$0.isHouseLine || style == .challenger) }
    }

    static func quote(id: String) -> CoachQuote? {
        all.first { $0.id == id }
    }

    /// Every line a style may show (house lines are Challenger-only), in a stable order.
    static func lines(for style: CoachStyle) -> [CoachQuote] {
        all.filter { !$0.isHouseLine || style == .challenger }.sorted { $0.id < $1.id }
    }

    /// "Today's line" in the popover (v3 §3.4): one line per calendar day, the same all day.
    /// `offset` steps to the next line when the user asks for another.
    static func dailyLine(style: CoachStyle, on date: Date, offset: Int = 0, calendar: Calendar = .current) -> CoachQuote? {
        let pool = lines(for: style)
        guard !pool.isEmpty else { return nil }
        let day = calendar.ordinality(of: .day, in: .era, for: date) ?? 0
        // A stride co-prime with the pool size walks every line before repeating.
        let stride = pool.count > 7 && pool.count % 7 != 0 ? 7 : 1
        let index = ((day &* stride) &+ offset) % pool.count
        return pool[(index + pool.count) % pool.count]
    }
}

// MARK: - 1% framings (from the user's own data)

enum CoachOnePercent {
    /// 1.01^365 ≈ 37.8.
    static let compounding = "1% better daily = 37× in a year."
    /// 1% of 24 h is 14.4 minutes.
    static let minutesInOnePercentOfDay = 14

    /// "1% of today is 14 minutes. Give 5 now." `give` is the real ask (the starter length);
    /// nil when the ask is longer than 1% of the day, so the line stays true.
    static func todayShare(give minutes: Int) -> String? {
        guard minutes > 0, minutes <= minutesInOnePercentOfDay else { return nil }
        return "1% of today is \(minutesInOnePercentOfDay) minutes. Give \(minutes) now."
    }

    /// "You've been 1% worse for {N} days. Today you turn it." Only with a real count of
    /// consecutive days without a focus block (at least 2).
    static func worseStreak(days: Int?) -> String? {
        guard let days, days >= 2 else { return nil }
        return "You've been 1% worse for \(days) days. Today you turn it."
    }
}

// MARK: - Per-quote learning

/// One "My why" line or quote that can be shown. Both are arms with the same prior, so the
/// user's own lines are weighted equal to quotes.
enum CoachMotivationItem: Equatable, Sendable {
    case quote(CoachQuote)
    case why(String)

    var id: String {
        switch self {
        case .quote(let quote): "quote:\(quote.id)"
        case .why(let line): "why:\(line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
        }
    }

    /// House lines become `.houseLine` with `{N}` filled in; quotes stay `.quote`.
    func detail(starterMinutes: Int) -> CoachDetail {
        switch self {
        case .quote(let quote) where quote.isHouseLine: .houseLine(quote.resolvedText(starterMinutes: starterMinutes))
        case .quote(let quote): .quote(quote)
        case .why(let line): .why(line)
        }
    }
}

/// A shown quote or why line, linked to the prompt it rode on.
struct CoachQuoteShow: Codable, Sendable, Equatable {
    let itemID: String
    let shownAt: Date
    let attemptID: UUID?
}

/// Beta learning per quote/why line from the prompt's reward, with no repeats within 3 days.
///
/// The show log is the source of truth: each entry links an item to the `InterventionAttempt`
/// it rode on, and the posterior is rebuilt from those attempts' rewards (`u = reward / 2`,
/// the bandit's scale), so quotes that precede starts rise and dead ones fade.
enum CoachQuotePicker {
    static let noRepeatInterval: TimeInterval = 3 * 24 * 3600
    static let fallbackNoRepeatInterval: TimeInterval = 24 * 3600
    static let prior = (alpha: 1.0, beta: 1.0)

    static func candidates(situation: CoachSituation, whyLines: [String], style: CoachStyle) -> [CoachMotivationItem] {
        let whys = whyLines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map(CoachMotivationItem.why)
        return CoachQuoteLibrary.quotes(for: situation, style: style).map(CoachMotivationItem.quote) + whys
    }

    static func posteriors(log: [CoachQuoteShow], rewards: [UUID: Double]) -> [String: (alpha: Double, beta: Double)] {
        var result: [String: (alpha: Double, beta: Double)] = [:]
        for show in log {
            guard let attemptID = show.attemptID, let reward = rewards[attemptID] else { continue }
            let u = CoachBanditModel.successFraction(for: reward)
            let current = result[show.itemID] ?? prior
            result[show.itemID] = (current.alpha + u, current.beta + 1 - u)
        }
        return result
    }

    /// Thompson-samples one item, skipping anything shown in the last 3 days. Nil when every
    /// candidate was shown recently (no quote is better than a repeat).
    static func pick<G: RandomNumberGenerator>(
        situation: CoachSituation,
        style: CoachStyle,
        whyLines: [String],
        log: [CoachQuoteShow],
        rewards: [UUID: Double],
        now: Date,
        using rng: inout G
    ) -> CoachMotivationItem? {
        let recent = Set(log.filter { now.timeIntervalSince($0.shownAt) < noRepeatInterval && $0.shownAt <= now }.map(\.itemID))
        var available = candidates(situation: situation, whyLines: whyLines, style: style).filter { !recent.contains($0.id) }
        if available.isEmpty {
            // v3 R6: with a quote on every prompt the situation's pool runs dry within days.
            // Fall back to any line for the style not shown in the last 24 hours.
            let lastDay = Set(log.filter { now.timeIntervalSince($0.shownAt) < fallbackNoRepeatInterval && $0.shownAt <= now }.map(\.itemID))
            available = CoachQuoteLibrary.lines(for: style).map(CoachMotivationItem.quote).filter { !lastDay.contains($0.id) }
        }
        guard !available.isEmpty else { return nil }
        let posteriors = posteriors(log: log, rewards: rewards)
        var best: CoachMotivationItem?
        var bestSample = -Double.infinity
        for item in available {
            let p = posteriors[item.id] ?? prior
            let sample = BetaSampler.sample(alpha: p.alpha, beta: p.beta, using: &rng)
            if sample > bestSample {
                bestSample = sample
                best = item
            }
        }
        return best
    }
}

/// Show log in UserDefaults (newest last, capped).
struct CoachQuoteShowLog {
    static let storageKey = "focusflow.coachQuoteShows.v1"
    static let maxEntries = 400
    let defaults: UserDefaults

    var entries: [CoachQuoteShow] {
        guard let data = defaults.data(forKey: Self.storageKey) else { return [] }
        return (try? JSONDecoder().decode([CoachQuoteShow].self, from: data)) ?? []
    }

    func append(_ show: CoachQuoteShow) {
        var all = entries
        all.append(show)
        if all.count > Self.maxEntries { all.removeFirst(all.count - Self.maxEntries) }
        if let data = try? JSONEncoder().encode(all) { defaults.set(data, forKey: Self.storageKey) }
    }
}
