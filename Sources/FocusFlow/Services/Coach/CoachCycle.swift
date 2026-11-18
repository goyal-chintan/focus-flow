import Foundation

// Coach v7 (docs/plans/2026-11-06-coach-v7-land-and-return.md): the block → break → next block
// cycle. In the live store (1 Sep – 6 Nov 2026) 48 % of blocks ran 5+ min past plan, and after
// those the next block started after a median 86 min (24 min after blocks that ended on time).
// Pure logic here; `TimerViewModel` wires it to the timer.

// MARK: - Landing

enum CoachLanding {
    /// The landing cue ("2 min left. Next step?") this long before the planned end.
    static let cueSeconds = 120
    /// "Keep going" is a lap of this many minutes, then the block-end window comes back.
    static let lapMinutes = 10
    /// Unchosen overtime: the stretch nudge (your own numbers) at +5 min…
    static let stretchNudgeSeconds = 300
    /// …and the block-end window comes back to the front at +10 min.
    static let resurfaceSeconds = 600

    /// What happens at this second of a block's overtime. `lapEndsAt` is the overtime second a
    /// chosen lap ends at (nil: no lap chosen).
    enum OvertimeStep: Equatable { case none, stretchNudge, resurface, lapEnded }

    static func overtimeStep(overtimeSeconds: Int, lapEndsAt: Int?) -> OvertimeStep {
        if let lapEndsAt {
            return overtimeSeconds == lapEndsAt ? .lapEnded : .none
        }
        switch overtimeSeconds {
        case stretchNudgeSeconds: return .stretchNudge
        case resurfaceSeconds: return .resurface
        default: return .none
        }
    }
}

// MARK: - Return ladder

enum CoachReturnLadder {
    /// "1 min. Next: …" this long before a break ends (replaces the 2- and 5-min "elapsed" alerts).
    static let preEndSeconds = 60
    /// The break is closed (ended, not a return) this long past its end.
    static let closeSeconds = 30 * 60
    /// Default re-entry offer ("Start 5m on …") past the break's end, before the hazard model has data.
    static let defaultReentrySeconds = 10 * 60

    enum Step: Equatable { case none, reentry, close }

    /// What happens at this second of a break's overrun.
    static func step(overrunSeconds: Int, reentrySeconds: Int) -> Step {
        if overrunSeconds == closeSeconds { return .close }
        if overrunSeconds == reentrySeconds { return .reentry }
        return .none
    }

    /// Return panel sizes: your usual length and a short way back in; after the re-entry point,
    /// only the short one (a small start after a long break, v4's proximal-goal logic).
    static func sizes(regular: Int, reentry: Bool) -> [Int] {
        reentry ? [5] : [regular, min(10, regular)].reduce(into: [Int]()) { if !$0.contains($1) { $0.append($1) } }
    }
}

// MARK: - Return hazard (learner A)

/// A discrete-time hazard for "minutes from a break's planned end to the next block's start",
/// fitted per bucket with a Beta prior (a Bayesian life table). Right-censored: a break with no
/// start within `horizonMinutes` counts as survival through every bucket. Explainable, works
/// with a few dozen breaks, and tells the coach when your return probability collapses.
struct CoachReturnHazard: Equatable, Sendable {
    /// Bucket starts in minutes; each bucket runs to the next start (the last to the horizon).
    static let buckets = [0, 3, 6, 10, 20]
    static let horizonMinutes = 60
    /// Beta(1, 9) per minute: a 10 % chance of starting in any given minute before data.
    static let priorStarts = 1.0
    static let priorNonStarts = 9.0
    static let minEpisodes = 8

    /// Posterior mean per-minute hazard for each bucket.
    let hazard: [Double]
    let episodes: Int

    /// `latencies`: minutes from each break's planned end to the next start; nil when nothing
    /// started within the horizon. Negative values (started before the break ended) count as 0.
    static func fit(latencies: [Double?]) -> CoachReturnHazard {
        var starts = Array(repeating: 0.0, count: buckets.count)
        var exposure = Array(repeating: 0.0, count: buckets.count)
        for raw in latencies {
            // Past the horizon is the same as no start: censored.
            let event = raw.flatMap { $0 <= Double(horizonMinutes) ? max(0, $0) : nil }
            for (i, lo) in buckets.enumerated() {
                let hi = Double(i + 1 < buckets.count ? buckets[i + 1] : horizonMinutes)
                if let event, event < hi {
                    // The minute the block started in counts as exposure.
                    exposure[i] += event - Double(lo) + 1
                    starts[i] += 1
                    break
                }
                exposure[i] += hi - Double(lo)
            }
        }
        let hazard = zip(starts, exposure).map { s, e in (priorStarts + s) / (priorStarts + priorNonStarts + e) }
        return CoachReturnHazard(hazard: hazard, episodes: latencies.count)
    }

    /// Chance of having started within `minutes` of the break's end.
    func startedWithin(_ minutes: Int) -> Double {
        var survival = 1.0
        for (i, lo) in Self.buckets.enumerated() where lo < minutes {
            let hi = min(i + 1 < Self.buckets.count ? Self.buckets[i + 1] : Self.horizonMinutes, minutes)
            survival *= pow(1 - hazard[i], Double(hi - lo))
        }
        return 1 - survival
    }

    /// When to offer the small re-entry: the start of the first bucket whose per-minute hazard is
    /// under half the first bucket's (that is where returns stop happening on their own),
    /// clamped to 3–15 min. The default 10 min until there are `minEpisodes` breaks.
    var reentryMinute: Int {
        guard episodes >= Self.minEpisodes, let first = hazard.first else { return CoachReturnLadder.defaultReentrySeconds / 60 }
        let index = hazard.indices.dropFirst().first { hazard[$0] < first / 2 } ?? (Self.buckets.count - 1)
        return min(15, max(3, Self.buckets[index]))
    }
}


// MARK: - Randomised return panel (learner B)

/// Micro-randomised: at each break end the coach shows the return panel with probability `π`
/// (otherwise only the notification and the break-over window). Starts within 10 min are
/// compared by inverse-propensity weighting, so the coach learns whether the panel *causes*
/// faster returns (HeartSteps-style; Klasnja et al., 2015).
enum CoachCycleExperiment {
    /// A 30 % quiet control group keeps the estimate honest while most breaks get the panel.
    static let probability = 0.7
    static let window: TimeInterval = 10 * 60
    static let minDecisions = 20

    struct Decision: Codable, Equatable, Sendable {
        var at: Date
        var treated: Bool
        var propensity: Double
    }

    struct Estimate: Equatable, Sendable {
        let treatedRate: Double
        let controlRate: Double
        let decisions: Int
        var lift: Double { treatedRate - controlRate }
    }

    /// IPW start-within-10-min rates for panel vs no panel. Nil under `minDecisions` or without both arms.
    static func estimate(_ decisions: [Decision], starts: [Date], now: Date) -> Estimate? {
        let resolved = decisions.filter { now.timeIntervalSince($0.at) >= window }
        guard resolved.count >= minDecisions, resolved.contains(where: \.treated), resolved.contains(where: { !$0.treated }) else { return nil }
        func started(_ d: Decision) -> Double {
            starts.contains { $0 >= d.at.addingTimeInterval(-60) && $0 <= d.at.addingTimeInterval(window) } ? 1 : 0
        }
        var t = 0.0, tw = 0.0, c = 0.0, cw = 0.0
        for d in resolved {
            if d.treated { let w = 1 / d.propensity; t += w * started(d); tw += w }
            else { let w = 1 / (1 - d.propensity); c += w * started(d); cw += w }
        }
        return Estimate(treatedRate: t / tw, controlRate: c / cw, decisions: resolved.count)
    }
}

struct CoachCycleLog {
    static let key = "focusflow.coachCycle.returnDecisions.v1"
    static let maxEntries = 400
    let defaults: UserDefaults

    func load() -> [CoachCycleExperiment.Decision] {
        guard let data = defaults.data(forKey: Self.key) else { return [] }
        return (try? JSONDecoder().decode([CoachCycleExperiment.Decision].self, from: data)) ?? []
    }

    func append(_ decision: CoachCycleExperiment.Decision) {
        let entries = Array((load() + [decision]).suffix(Self.maxEntries))
        if let data = try? JSONEncoder().encode(entries) { defaults.set(data, forKey: Self.key) }
    }
}

// MARK: - Cycle stats (what the coach says about your cycle)

struct CoachCycleStats: Equatable, Sendable {
    struct Session: Equatable, Sendable {
        var isFocus: Bool
        var start: Date
        var end: Date
        var plannedSeconds: TimeInterval
        var pausedSeconds: TimeInterval
    }

    /// Minutes from a block's end to the next block's start, same sitting (< 4 h).
    let gaps: [Double]
    let onTimeGaps: [Double]
    let stretchedGaps: [Double]
    let blocks: Int
    let stretchedBlocks: Int

    static let stretchSeconds: TimeInterval = 5 * 60
    static let sittingGap: TimeInterval = 4 * 3600
    static let minPerGroup = 4

    static func compute(_ sessions: [Session]) -> CoachCycleStats {
        let sorted = sessions.sorted { $0.start < $1.start }
        var gaps: [Double] = [], onTime: [Double] = [], stretched: [Double] = []
        var blocks = 0, stretchedBlocks = 0
        for (i, s) in sorted.enumerated() where s.isFocus {
            blocks += 1
            let over = s.end.timeIntervalSince(s.start) - s.pausedSeconds - s.plannedSeconds
            if over > stretchSeconds { stretchedBlocks += 1 }
            guard let next = sorted[(i + 1)...].first(where: \.isFocus) else { continue }
            let gap = next.start.timeIntervalSince(s.end)
            // Restarts within 2 min are chained blocks, not returns; past 4 h is another sitting.
            guard gap >= 120, gap < sittingGap else { continue }
            gaps.append(gap / 60)
            if over > stretchSeconds { stretched.append(gap / 60) } else { onTime.append(gap / 60) }
        }
        return CoachCycleStats(gaps: gaps, onTimeGaps: onTime, stretchedGaps: stretched, blocks: blocks, stretchedBlocks: stretchedBlocks)
    }

    var medianGap: Double? { gaps.isEmpty ? nil : CoachPatterns.median(gaps) }

    /// "Blocks you run 5+ min over are followed by an 86-min gap; blocks that end on time, 24 min."
    /// Only when both groups have data and the gap really is longer after a stretch.
    var stretchFact: String? {
        guard onTimeGaps.count >= Self.minPerGroup, stretchedGaps.count >= Self.minPerGroup else { return nil }
        let stretched = CoachPatterns.median(stretchedGaps), onTime = CoachPatterns.median(onTimeGaps)
        guard stretched >= onTime * 1.5, stretched - onTime >= 10 else { return nil }
        return "Blocks you run 5+ min over are followed by a \(Int(stretched.rounded()))-min gap; blocks that end on time, \(Int(onTime.rounded())) min."
    }

    var sentence: String? {
        guard let median = medianGap, gaps.count >= Self.minPerGroup * 2 else { return nil }
        let share = blocks == 0 ? 0 : Int((Double(stretchedBlocks) / Double(blocks) * 100).rounded())
        var text = "From a block's end to the next start: median \(Int(median.rounded())) min. \(share)% of blocks ran 5+ min past plan."
        if let fact = stretchFact { text += " " + fact }
        return text
    }
}

// MARK: - Natural length

enum CoachNaturalLength {
    static let lookback = 15
    static let minBlocks = 8
    static let overSeconds: TimeInterval = 8 * 60
    static let share = 0.6

    /// Your blocks keep running long while you focus (no pauses): offer the length you actually
    /// work, rounded to 5 min, 30–60, once it is above your usual. Nil otherwise.
    static func suggestion(_ blocks: [CoachCycleStats.Session], regularMinutes: Int) -> Int? {
        let recent = blocks.filter { $0.isFocus && $0.pausedSeconds < 60 && abs($0.plannedSeconds - Double(regularMinutes * 60)) < 30 }
            .sorted { $0.start < $1.start }.suffix(lookback)
        guard recent.count >= minBlocks else { return nil }
        let active = recent.map { $0.end.timeIntervalSince($0.start) - $0.pausedSeconds }
        let over = zip(recent, active).filter { $1 - $0.plannedSeconds >= overSeconds }.count
        guard Double(over) / Double(recent.count) >= share else { return nil }
        let minutes = Int((CoachPatterns.median(active) / 60 / 5).rounded()) * 5
        let suggested = min(60, max(30, minutes))
        return suggested > regularMinutes ? suggested : nil
    }
}
