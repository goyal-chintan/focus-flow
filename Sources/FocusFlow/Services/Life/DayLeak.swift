import Foundation

// Where the day went, and why (6 Nov 2026, after "I'm at the laptop from 10 to 7 and get 2 hours").
// From the first activity to the last, each minute is own work, work, a break, office, side work,
// a pull, away, or other. Gaps of 30+ min between own-work sittings carry what filled them and,
// once you say, why: family and rest are fine; tired, putting it off and side projects are what
// the coach learns from. Experience sampling at the moment beats recall (Csikszentmihalyi &
// Larson, 1987), so the coach asks about one big gap a day and Today lets you label in place. Pure.

enum LeakCategory: String, CaseIterable, Codable, Sendable {
    case own, work, rest, office, side, unblockedOwn, pull, away, other

    var title: String {
        switch self {
        case .own: "Own work"
        case .work: "Work blocks"
        case .rest: "Breaks"
        case .office: "Office & calls"
        case .side: "Side work"
        case .unblockedOwn: "Own work, no block"
        case .pull: "Pulls"
        case .away: "Away"
        case .other: "Other"
        }
    }

    /// What it means for the coach, in one phrase.
    var caption: String {
        switch self {
        case .side: "Dev and AI tools outside a block"
        case .unblockedOwn: "Your learning sites outside a block"
        case .away: "No input for 5+ min, or the laptop asleep"
        default: ""
        }
    }
}

/// Why a gap happened, from you.
enum GapReason: String, CaseIterable, Codable, Sendable {
    case family, rest, meal, office, tired, procrastinating, sideProject, other

    var title: String {
        switch self {
        case .family: "Family / friends"
        case .rest: "Rest / outside"
        case .meal: "Meal / chores"
        case .office: "Office work"
        case .tired: "Tired"
        case .procrastinating: "Putting it off"
        case .sideProject: "Side project"
        case .other: "Something else"
        }
    }

    /// Time well spent elsewhere: the coach does not count it against you.
    var isFine: Bool { [.family, .rest, .meal, .office].contains(self) }
}

/// Which apps are side work outside a block: tools for building, not the goal itself
/// (FocusFlow itself is built with these). Inside an own-work block they are that block's work.
enum SideWorkTools {
    static let needles = ["claude", "cursor", "todesktop.230313mzl4w4u92", "githubapp", "copilot", "antigravity", "ghostty",
                          "com.apple.terminal", "iterm", "xcode", "github.com", "gemini", "chatgpt", "openai", "grok",
                          "anysphere", "vscode", "com.microsoft.vscode", "herokuapp", "localhost", "focusflow"]

    static func isSide(key: String, label: String) -> Bool {
        let text = (key + " " + label).lowercased()
        return needles.contains { text.contains($0) }
    }
}

struct DayAccount: Equatable, Sendable {
    struct Gap: Equatable, Sendable, Identifiable {
        let start: Date
        let end: Date
        /// What filled it (minutes); "away" includes time with nothing recorded.
        let filled: [LeakCategory: Double]
        var reason: GapReason?

        var id: Date { start }
        var minutes: Double { end.timeIntervalSince(start) / 60 }
        var dominant: LeakCategory { filled.max { $0.value < $1.value }?.key ?? .away }

        /// "1h 20m away · 25m side work".
        var summary: String {
            filled.filter { $0.value >= 5 }.sorted { $0.value > $1.value }.prefix(3)
                .map { "\(FFFormatLite.duration($0.value)) \($0.key.title.lowercased())" }
                .joined(separator: " · ")
        }
    }

    let day: Date
    /// First activity to last (or now, today); nil with nothing recorded.
    let span: DateInterval?
    let minutes: [LeakCategory: Double]
    let gaps: [Gap]
    /// Hourly rows covered the day (calls, away and app time are known).
    let hasRollup: Bool

    static let minGapMinutes = 30.0

    var spanMinutes: Double { span.map { $0.duration / 60 } ?? 0 }

    /// Minutes not accounted for by own work or time you called fine.
    var leakMinutes: Double {
        let fine = gaps.filter { $0.reason?.isFine == true }.map(\.minutes).reduce(0, +)
        return max(0, spanMinutes - (minutes[.own] ?? 0) - (minutes[.work] ?? 0) - (minutes[.rest] ?? 0) - (minutes[.office] ?? 0) - fine)
    }

    struct Row: Equatable, Sendable {
        var hourStart: Date
        var key: String
        var label: String
        var inBlock: Bool
        var seconds: Int
    }

    struct Block: Equatable, Sendable {
        var start: Date
        var end: Date
        var own: Bool
        /// Paused inside the block: a break, not focus.
        var pausedSeconds: TimeInterval = 0
    }

    /// `category(key, label, hour)` names an outside-block row: office, pull, side, unblockedOwn
    /// or other (calls and away are known from the key). `reasons` by gap start (minute).
    static func build(day: Date, now: Date, rows: [Row], blocks: [Block], breaks: [DateInterval],
                      category: (String, String, Int) -> LeakCategory, reasons: [Date: GapReason],
                      calendar: Calendar = .current) -> DayAccount {
        let dayStart = calendar.startOfDay(for: day)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        let dayRows = rows.filter { $0.hourStart >= dayStart && $0.hourStart < dayEnd }
        let dayBlocks = blocks.compactMap { b -> Block? in
            let s = max(b.start, dayStart), e = min(b.end, dayEnd)
            let whole = max(1, b.end.timeIntervalSince(b.start))
            return e > s ? Block(start: s, end: e, own: b.own, pausedSeconds: b.pausedSeconds * e.timeIntervalSince(s) / whole) : nil
        }.sorted { $0.start < $1.start }

        var minutes: [LeakCategory: Double] = [:]
        for b in dayBlocks {
            let wall = b.end.timeIntervalSince(b.start)
            let paused = min(wall, max(0, b.pausedSeconds))
            minutes[b.own ? .own : .work, default: 0] += (wall - paused) / 60
            if paused > 0 { minutes[.rest, default: 0] += paused / 60 }
        }
        let dayBreaks = breaks.compactMap { i -> DateInterval? in
            let s = max(i.start, dayStart), e = min(i.end, dayEnd)
            return e > s ? DateInterval(start: s, end: e) : nil
        }
        for b in dayBreaks { minutes[.rest, default: 0] += b.duration / 60 }

        // Outside-block rows, by hour and category.
        var byHour: [Date: [LeakCategory: Double]] = [:]
        for row in dayRows where !row.inBlock {
            let hour = calendar.component(.hour, from: row.hourStart)
            let cat: LeakCategory
            switch row.key {
            case "away": cat = .away
            case "call": cat = .office
            default: cat = category(row.key, row.label, hour)
            }
            byHour[row.hourStart, default: [:]][cat, default: 0] += Double(row.seconds) / 60
        }

        // Span: the first and last activity (hour rows give the hour; blocks give the minute).
        let active = dayRows.filter { $0.key != "away" && $0.seconds >= 60 }
        let firstRow = active.map(\.hourStart).min()
        let lastRow = active.map { $0.hourStart.addingTimeInterval(3600) }.max()
        let starts = [firstRow, dayBlocks.first?.start].compactMap { $0 }
        let ends = [lastRow, dayBlocks.map(\.end).max()].compactMap { $0 }
        var span: DateInterval?
        if let s = starts.min(), let e = ends.max() {
            let end = calendar.isDate(now, inSameDayAs: dayStart) ? max(min(now, dayEnd), s) : max(e, s)
            span = DateInterval(start: s, end: max(end, s))
        }
        if let span {
            // Outside-block time inside the span, prorated by hour.
            for (hour, cats) in byHour {
                let overlap = max(0, min(span.end, hour.addingTimeInterval(3600)).timeIntervalSince(max(span.start, hour)))
                guard overlap > 0 else { continue }
                for (cat, m) in cats { minutes[cat, default: 0] += m * overlap / 3600 }
            }
        }

        // Gaps: between own-work sittings (and before the first), 30+ min, breaks taken out.
        var gaps: [Gap] = []
        if let span {
            let own = dayBlocks.filter(\.own)
            var cursor = span.start
            var edges: [(Date, Date)] = []
            for b in own {
                if b.start.timeIntervalSince(cursor) / 60 >= minGapMinutes { edges.append((cursor, b.start)) }
                cursor = max(cursor, b.end)
            }
            // After the last sitting (today: until now, still open).
            if span.end.timeIntervalSince(cursor) / 60 >= minGapMinutes { edges.append((cursor, span.end)) }
            for (s, e) in edges {
                var filled: [LeakCategory: Double] = [:]
                for b in dayBlocks where !b.own {
                    let o = min(e, b.end).timeIntervalSince(max(s, b.start))
                    if o > 0 { filled[.work, default: 0] += o / 60 }
                }
                for b in dayBreaks {
                    let o = min(e, b.end).timeIntervalSince(max(s, b.start))
                    if o > 0 { filled[.rest, default: 0] += o / 60 }
                }
                for (hour, cats) in byHour {
                    let o = min(e, hour.addingTimeInterval(3600)).timeIntervalSince(max(s, hour))
                    guard o > 0 else { continue }
                    let share = o / 3600
                    for (cat, m) in cats { filled[cat, default: 0] += m * share }
                }
                let total = (e.timeIntervalSince(s)) / 60
                let known = filled.values.reduce(0, +)
                if known < total {
                    // Nothing recorded: the laptop was asleep or you were off it.
                    filled[.away, default: 0] += total - known
                } else if known > total {
                    let scale = total / known
                    for k in filled.keys { filled[k]! *= scale }
                }
                gaps.append(Gap(start: s, end: e, filled: filled, reason: reasons[reasonKey(s, calendar: calendar)]))
            }
        }
        return DayAccount(day: dayStart, span: span, minutes: minutes, gaps: gaps, hasRollup: !dayRows.isEmpty)
    }

    /// The key a gap's reason is stored under: its start, to the minute.
    static func reasonKey(_ start: Date, calendar: Calendar = .current) -> Date {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: start)
        return calendar.date(from: parts) ?? start
    }
}

/// Your answers, in defaults (small, per Mac; kept 120 days).
struct GapReasonStore {
    static let key = "focusflow.gapReasons"
    let defaults: UserDefaults

    func all() -> [Date: GapReason] {
        guard let raw = defaults.dictionary(forKey: Self.key) as? [String: String] else { return [:] }
        var out: [Date: GapReason] = [:]
        for (k, v) in raw {
            if let t = TimeInterval(k), let r = GapReason(rawValue: v) { out[Date(timeIntervalSince1970: t)] = r }
        }
        return out
    }

    func set(_ reason: GapReason?, for start: Date, now: Date = Date()) {
        var raw = (defaults.dictionary(forKey: Self.key) as? [String: String]) ?? [:]
        let key = String(Int(DayAccount.reasonKey(start).timeIntervalSince1970))
        raw[key] = reason?.rawValue
        let cutoff = now.addingTimeInterval(-120 * 86_400).timeIntervalSince1970
        raw = raw.filter { (TimeInterval($0.key) ?? 0) >= cutoff }
        defaults.set(raw, forKey: Self.key)
    }
}
