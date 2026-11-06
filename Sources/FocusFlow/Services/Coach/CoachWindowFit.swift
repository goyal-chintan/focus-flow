import Foundation

// Coach v6 §3.1 (docs/plans/2026-11-06-coach-v6-adapt-and-speak.md): declared own-work windows
// are a starting belief, not a fence. On 6 Nov 2026 the declared 07–09 and 20–22 caught about 6
// of 47 own-work starts in 30 days (none in 20–22, 17 between 22:00 and 03:00), and outside them
// the coach made no decisions at all. The fit reads when blocks actually start and offers those
// hours, until the user answers the window question.

struct CoachWindowFit: Equatable, Sendable {
    /// Own-work block starts in the lookback.
    let starts: Int
    /// How many of them began inside a declared window.
    let covered: Int
    /// Where starts cluster: at most `maxWindows`, each 1–3 h with at least `minStartsPerWindow`.
    let observed: [CoachOwnWorkWindow]

    static let lookbackDays = 28
    static let minStarts = 8
    static let mismatchCoverage = 0.4
    static let maxWindows = 3
    static let maxWindowHours = 3
    static let minStartsPerWindow = 3

    var coverage: Double { starts == 0 ? 1 : Double(covered) / Double(starts) }

    /// Enough starts, and the declared windows catch fewer than 40 % of them.
    func isMismatch(declared: [CoachOwnWorkWindow]) -> Bool {
        !declared.isEmpty && starts >= Self.minStarts && coverage < Self.mismatchCoverage
            && observed.contains { !declared.contains($0) }
    }

    /// Observed windows that don't overlap a declared one.
    func additions(to declared: [CoachOwnWorkWindow]) -> [CoachOwnWorkWindow] {
        observed.filter { window in
            !declared.contains { $0.startMinute < window.endMinute && window.startMinute < $0.endMinute }
        }
    }

    /// "22:00–00:00 and 11:00–14:00".
    var observedLabel: String {
        let labels = observed.map(\.label)
        switch labels.count {
        case 0: return ""
        case 1: return labels[0]
        default: return labels.dropLast().joined(separator: ", ") + " and " + labels.last!
        }
    }

    static func compute(startDates: [Date], declared: [CoachOwnWorkWindow], calendar: Calendar = .current) -> CoachWindowFit {
        var perHour = Array(repeating: 0, count: 24)
        var covered = 0
        for date in startDates {
            perHour[calendar.component(.hour, from: date)] += 1
            if declared.contains(where: { $0.contains(date, calendar: calendar) }) { covered += 1 }
        }
        return CoachWindowFit(starts: startDates.count, covered: covered, observed: clusters(perHour))
    }

    /// Greedy: take the busiest unused hour, grow it into neighbours that hold at least half its
    /// starts (never past midnight, at most 3 h), keep it if it holds 3+ starts.
    static func clusters(_ perHour: [Int]) -> [CoachOwnWorkWindow] {
        guard perHour.count == 24 else { return [] }
        var used = Array(repeating: false, count: 24)
        var windows: [CoachOwnWorkWindow] = []
        while windows.count < maxWindows {
            guard let peak = (0..<24).filter({ !used[$0] && perHour[$0] > 0 }).max(by: { perHour[$0] < perHour[$1] || (perHour[$0] == perHour[$1] && $0 > $1) }) else { break }
            let floor = max(1, (perHour[peak] + 1) / 2)
            var lo = peak, hi = peak
            while hi - lo + 1 < maxWindowHours {
                let left = lo - 1 >= 0 && !used[lo - 1] && perHour[lo - 1] >= floor ? perHour[lo - 1] : -1
                let right = hi + 1 < 24 && !used[hi + 1] && perHour[hi + 1] >= floor ? perHour[hi + 1] : -1
                if left < 0 && right < 0 { break }
                if right >= left { hi += 1 } else { lo -= 1 }
            }
            for hour in lo...hi { used[hour] = true }
            let total = perHour[lo...hi].reduce(0, +)
            if total >= minStartsPerWindow {
                windows.append(CoachOwnWorkWindow(startMinute: lo * 60, endMinute: (hi + 1) * 60))
            }
        }
        return CoachOwnWorkWindows.normalized(windows)
    }

    /// Declared windows plus the observed ones that don't overlap them, sorted.
    static func effective(declared: [CoachOwnWorkWindow], fit: CoachWindowFit?, keepMine: Bool) -> [CoachOwnWorkWindow] {
        guard !keepMine, let fit, fit.isMismatch(declared: declared) else { return declared }
        let merged = (declared + fit.additions(to: declared)).sorted { $0.startMinute < $1.startMinute }
        return Array(merged.prefix(CoachOwnWorkWindows.maxWindows + maxWindows))
    }
}
