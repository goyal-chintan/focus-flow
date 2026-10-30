import Foundation

/// One day of the coach log (Insights → coach log, coach audit 2026-10-30): how often the coach
/// had a moment to ask, what it showed and what it held back (and why), whether you started
/// after a prompt or on your own, and your own-work minutes against the goal.
struct CoachLogDay: Equatable, Sendable, Identifiable {
    struct HeldBack: Equatable, Sendable, Identifiable {
        let code: CoachJournal.Code
        let count: Int
        var id: String { code.rawValue }
    }

    let day: Date
    let shown: Int
    let heldBack: [HeldBack]
    let startsAfterPrompt: Int
    let startsOnYourOwn: Int
    let ownWorkMinutes: Int
    let goalMinutes: Int
    var id: Date { day }

    var heldBackTotal: Int { heldBack.reduce(0) { $0 + $1.count } }
    /// Moments the coach decided: shown or held back.
    var decisionMoments: Int { shown + heldBackTotal }
    var starts: Int { startsAfterPrompt + startsOnYourOwn }
}

enum CoachLogSummary {
    /// A recorded block start (`BlockStartEvent`): was a prompt credited with it?
    struct Start: Equatable, Sendable {
        let at: Date
        let afterPrompt: Bool
    }

    static let defaultDays = 7

    /// Lines that are a decision moment the coach showed: the user's own plan cue and a
    /// counter-offer after "Not now" are answers, not new moments.
    static func isShownMoment(_ entry: CoachJournal.Entry) -> Bool {
        guard entry.kind == .shown else { return false }
        return entry.code != .counterOffer && entry.code != .plannedCue && entry.code != .planTomorrow
    }

    /// Quiet lines that count as a moment held back. Old lines without a code still count.
    static func heldBackCode(_ entry: CoachJournal.Entry) -> CoachJournal.Code? {
        guard entry.kind == .quiet else { return nil }
        if let code = entry.code {
            // Outside your windows there was no moment at all.
            return code == .outsideOwnWindow || code == .outsideWindow || code == .disabled ? nil : code
        }
        if entry.text.hasPrefix("Held back on purpose") { return .control }
        if entry.text.contains("Daily prompt cap") { return .dailyCap }
        if entry.text.contains("Outside your learned") { return nil }
        return .noSurface
    }

    /// Newest day first. Starts come from the start records when that day has any, else from
    /// the journal's start lines (days before the records existed).
    static func days(
        entries: [CoachJournal.Entry],
        starts: [Start],
        ownWorkMinutes: (Date) -> Int,
        goalMinutes: Int,
        now: Date,
        count: Int = defaultDays,
        calendar: Calendar = .current
    ) -> [CoachLogDay] {
        let today = calendar.startOfDay(for: now)
        return (0..<max(count, 1)).compactMap { offset -> CoachLogDay? in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let dayEntries = entries.filter { calendar.isDate($0.at, inSameDayAs: day) }
            let held = Dictionary(grouping: dayEntries.compactMap(heldBackCode), by: { $0 })
                .map { CoachLogDay.HeldBack(code: $0.key, count: $0.value.count) }
                .sorted { $0.count != $1.count ? $0.count > $1.count : $0.code.rawValue < $1.code.rawValue }
            let dayStarts = starts.filter { calendar.isDate($0.at, inSameDayAs: day) }
            let afterPrompt: Int
            let onYourOwn: Int
            if dayStarts.isEmpty {
                let lines = dayEntries.filter { $0.kind == .started }
                let prompted = lines.filter { line in
                    line.code.map { $0 == .afterPrompt } ?? !line.text.contains("on your own")
                }.count
                afterPrompt = prompted
                onYourOwn = lines.count - prompted
            } else {
                afterPrompt = dayStarts.filter(\.afterPrompt).count
                onYourOwn = dayStarts.count - afterPrompt
            }
            return CoachLogDay(
                day: day,
                shown: dayEntries.filter(isShownMoment).count,
                heldBack: held,
                startsAfterPrompt: afterPrompt,
                startsOnYourOwn: onYourOwn,
                ownWorkMinutes: ownWorkMinutes(day),
                goalMinutes: goalMinutes
            )
        }
    }
}
