import Foundation

/// The line you see every time you open FocusFlow (clarity design: docs/plans/2026-10-28-clarity-fixes.md).
/// It grounds rather than decorates: Dan Koe's questions and lines, and the challenging quotes the
/// user chose, never generic advice. Your own words (My why, anti-vision, vision) take every other
/// day. The line holds all day and changes tomorrow.
struct DailyReminderLine: Equatable, Sendable {
    let text: String
    /// "Dan Koe, How to fix your entire life in 1 day (2025)"; "Your why", "Your anti-vision" for your own words.
    let attribution: String
    /// Written by you (My why, vision, anti-vision), not from the library.
    let isOwn: Bool
    /// A question to sit with (Dan Koe's interrupts), shown with a question mark, not quotes.
    var isQuestion: Bool = false
}

enum DailyReminder {
    /// Your own lines, in order: why lines, then anti-vision, then vision (one sentence each).
    static func ownLines(why: [String], antiVision: String?, vision: String?) -> [DailyReminderLine] {
        var lines = why.map { DailyReminderLine(text: $0, attribution: "Your why", isOwn: true) }
        if let anti = firstSentence(antiVision) {
            lines.append(DailyReminderLine(text: anti, attribution: "Your anti-vision", isOwn: true))
        }
        if let vision = firstSentence(vision) {
            lines.append(DailyReminderLine(text: vision, attribution: "Your vision", isOwn: true))
        }
        return lines
    }

    /// Dan Koe's interrupt questions ("What am I avoiding right now by doing what I'm doing?").
    static var koeQuestions: [CoachQuote] { CoachQuoteLibrary.all.filter(\.isQuestion) }

    /// The challenging lines: Dan Koe's statements first, then the quotes the user picked on
    /// 2026-10-17 and the hardest discipline lines. Generic advice ("Clarity about what matters…")
    /// is left out on purpose.
    static let groundingQuoteIDs = [
        "koe-not-the-person", "house-intelligence-discipline", "koe-afraid", "house-cost-of-procrastination",
        "koe-anti-vision-stakes", "seneca-short-life", "koe-learn-from-mistakes", "karen-lamb-year-from-now",
        "koe-progress", "gregorek-hard-choices", "koe-levers-quests", "willink-discipline-freedom",
        "emmett-dread", "clear-trajectory", "house-give-it-minutes", "clear-never-miss-twice",
        "aurelius-ten-thousand-years", "house-secret-getting-started",
    ]

    /// Questions and challenging lines, alternating, so every other day asks you something.
    /// House lines are Challenger's; "1% better" is everyone's.
    static func libraryLines(style: CoachStyle, starterMinutes: Int = CoachStarterBlock.defaultMinutes) -> [DailyReminderLine] {
        let questions = koeQuestions.map { line(from: $0, starterMinutes: starterMinutes) }
        var statements = groundingQuoteIDs
            .compactMap(CoachQuoteLibrary.quote(id:))
            .filter { !$0.isHouseLine || style == .challenger }
            .map { line(from: $0, starterMinutes: starterMinutes) }
        statements.insert(DailyReminderLine(text: CoachOnePercent.compounding, attribution: "1.01³⁶⁵ ≈ 37.8", isOwn: false), at: min(5, statements.count))
        var mixed: [DailyReminderLine] = []
        for index in 0..<max(questions.count, statements.count) {
            if index < questions.count { mixed.append(questions[index]) }
            if index < statements.count { mixed.append(statements[index]) }
        }
        return mixed
    }

    private static func line(from quote: CoachQuote, starterMinutes: Int) -> DailyReminderLine {
        DailyReminderLine(
            text: quote.resolvedText(starterMinutes: starterMinutes),
            attribution: quote.isHouseLine ? "FocusFlow" : (quote.author == "Dan Koe" ? "Dan Koe, How to fix your entire life in 1 day (2025)" : quote.attribution),
            isOwn: false,
            isQuestion: quote.isQuestion
        )
    }

    /// Today's line, shifted by `offset` when you tap for another. With lines of your own, they
    /// take every other day and the grounding lines the rest.
    static func line(own: [DailyReminderLine], style: CoachStyle, on day: Date, offset: Int = 0,
                     calendar: Calendar = .current) -> DailyReminderLine? {
        let library = libraryLines(style: style)
        let step = dayNumber(day, calendar: calendar) + offset
        let n = max(0, step)
        if own.isEmpty {
            guard !library.isEmpty else { return nil }
            return library[n % library.count]
        }
        if library.isEmpty || n % 2 == 0 { return own[(n / 2) % own.count] }
        return library[(n / 2) % library.count]
    }

    /// Whole days since 2001-01-01 in the user's calendar: the same all day, +1 tomorrow.
    static func dayNumber(_ day: Date, calendar: Calendar = .current) -> Int {
        let start = calendar.startOfDay(for: day)
        let reference = calendar.startOfDay(for: Date(timeIntervalSinceReferenceDate: 0))
        return max(0, calendar.dateComponents([.day], from: reference, to: start).day ?? 0)
    }

    /// The first sentence or line of a longer note, trimmed; nil when empty.
    static func firstSentence(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        if let end = line.firstIndex(where: { ".!?".contains($0) }), line.index(after: end) < line.endIndex {
            return String(line[...end]).trimmingCharacters(in: .whitespaces)
        }
        return line.trimmingCharacters(in: .whitespaces)
    }
}
