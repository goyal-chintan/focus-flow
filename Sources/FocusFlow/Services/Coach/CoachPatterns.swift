import Foundation

// Coach v6 §3.5: what the coach noticed, as plain sentences with numbers. Before v6 no surface
// read break data, and pattern output sat in a collapsed Settings section. Pure, so every
// sentence is unit-tested against fixed data.

struct CoachPattern: Equatable, Sendable, Identifiable {
    enum Kind: String, Sendable {
        case days, hours, windowsFit, breaks, backToBack, lengths, cycle, returnPanel
    }

    let kind: Kind
    let symbol: String
    let title: String
    let sentence: String

    var id: String { kind.rawValue }
}

enum CoachPatterns {
    struct Block: Equatable, Sendable {
        var start: Date
        var end: Date
        /// Planned length in minutes.
        var plannedMinutes: Int
        /// Focused seconds (pauses excluded).
        var focusedSeconds: TimeInterval
        var completed: Bool
        var ownWork: Bool
    }

    struct Break: Equatable, Sendable {
        var suggestedMinutes: Int
        var actualSeconds: Int
        var overrunSeconds: Int
        var returnedToFocus: Bool
    }

    static let minBreaks = 5
    static let minBlocks = 8
    static let minPerLength = 3
    /// A block that starts within this of the last one's end had no break.
    static let backToBackGap: TimeInterval = 120

    static func compute(blocks: [Block], breaks: [Break], declared: [CoachOwnWorkWindow],
                        cycle: CoachCycleStats? = nil, returnEstimate: CoachCycleExperiment.Estimate? = nil,
                        calendar: Calendar = .current) -> [CoachPattern] {
        let own = blocks.filter(\.ownWork).sorted { $0.start < $1.start }
        let fit = CoachWindowFit.compute(startDates: own.map(\.start), declared: declared, calendar: calendar)
        return [
            cycle.flatMap(cyclePattern),
            returnEstimate.map(returnPanelPattern),
            hours(fit, own: own, calendar: calendar),
            windowsFit(fit, declared: declared),
            breakPattern(breaks),
            backToBack(blocks.sorted { $0.start < $1.start }),
            lengths(own),
        ].compactMap { $0 }
    }

    static func hours(_ fit: CoachWindowFit, own: [Block], calendar: Calendar) -> CoachPattern? {
        guard fit.starts >= minBlocks, !fit.observed.isEmpty else { return nil }
        let inside = own.filter { block in fit.observed.contains { $0.contains(block.start, calendar: calendar) } }.count
        return CoachPattern(
            kind: .hours, symbol: "clock",
            title: "When you start",
            sentence: "Your own work starts around \(fit.observedLabel): \(inside) of your last \(fit.starts) blocks."
        )
    }

    static func windowsFit(_ fit: CoachWindowFit, declared: [CoachOwnWorkWindow]) -> CoachPattern? {
        guard !declared.isEmpty, fit.starts >= minBlocks else { return nil }
        let labels = declared.map(\.label).joined(separator: ", ")
        let verdict = fit.isMismatch(declared: declared)
            ? "The coach only spoke in those hours, so it was quiet when you worked."
            : "They match when you work."
        return CoachPattern(
            kind: .windowsFit, symbol: "scope",
            title: "Your set windows",
            sentence: "\(labels) caught \(fit.covered) of \(fit.starts) own-work starts. \(verdict)"
        )
    }

    static func breakPattern(_ breaks: [Break]) -> CoachPattern? {
        guard breaks.count >= minBreaks else { return nil }
        let actual = median(breaks.map { Double($0.actualSeconds) / 60 })
        let planned = median(breaks.map { Double($0.suggestedMinutes) })
        let over = breaks.filter { $0.overrunSeconds > 120 }.count
        let back = breaks.filter(\.returnedToFocus).count
        let length = Int(actual.rounded()) > Int(planned.rounded()) + 2
            ? "Your breaks run about \(Int(actual.rounded())) min against \(Int(planned.rounded())) planned"
            : "Your breaks run about \(Int(actual.rounded())) min, close to plan"
        return CoachPattern(
            kind: .breaks, symbol: "cup.and.saucer",
            title: "Breaks",
            sentence: "\(length). \(over) of \(breaks.count) ran 2+ min over; you came back to focus after \(back)."
        )
    }

    static func backToBack(_ blocks: [Block]) -> CoachPattern? {
        guard blocks.count >= minBlocks else { return nil }
        var chained = 0
        for (previous, next) in zip(blocks, blocks.dropFirst()) where next.start.timeIntervalSince(previous.end) < backToBackGap {
            chained += 1
        }
        guard chained >= 3, Double(chained) / Double(blocks.count - 1) >= 0.15 else { return nil }
        return CoachPattern(
            kind: .backToBack, symbol: "arrow.right.to.line",
            title: "No break between blocks",
            sentence: "\(chained) of your last \(blocks.count) blocks started straight after the one before, with no break."
        )
    }

    static func lengths(_ own: [Block]) -> CoachPattern? {
        let sizes = [5, 15, 25, 50]
        let groups = Dictionary(grouping: own) { block in sizes.min { abs($0 - block.plannedMinutes) < abs($1 - block.plannedMinutes) } ?? 25 }
        let parts: [String] = sizes.compactMap { size in
            guard let group = groups[size], group.count >= minPerLength else { return nil }
            let finished = group.filter(\.completed).count
            let stayed = Int((group.map(\.focusedSeconds).reduce(0, +) / Double(group.count) / 60).rounded())
            return "\(size)m blocks: \(finished) of \(group.count) finished, \(stayed) min on average"
        }
        guard !parts.isEmpty else { return nil }
        return CoachPattern(
            kind: .lengths, symbol: "timer",
            title: "Block length",
            sentence: parts.joined(separator: "; ") + "."
        )
    }

    /// Coach v7: the block → next block cycle, with the stretch fact when it holds.
    static func cyclePattern(_ cycle: CoachCycleStats) -> CoachPattern? {
        cycle.sentence.map { CoachPattern(kind: .cycle, symbol: "arrow.triangle.2.circlepath", title: "Your cycle", sentence: $0) }
    }

    /// Coach v7 learner B: does the return panel get you back? Measured, not assumed.
    static func returnPanelPattern(_ estimate: CoachCycleExperiment.Estimate) -> CoachPattern {
        let with = Int((estimate.treatedRate * 100).rounded()), without = Int((estimate.controlRate * 100).rounded())
        let verdict = estimate.lift >= 0.1 ? "It helps." : estimate.lift <= -0.1 ? "It doesn't help yet; the coach will lean on it less." : "No clear difference yet."
        return CoachPattern(kind: .returnPanel, symbol: "arrow.uturn.left", title: "The back-from-break panel",
                            sentence: "With it you were back within 10 min \(with)% of the time, without it \(without)% (\(estimate.decisions) breaks). \(verdict)")
    }

    static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }
}
