import SwiftUI

@MainActor
@Observable
final class DesignLabDecisionStore {
    private(set) var decisions: [DesignLabComponent: DesignLabComponentDecision] = [:]
    private let archiveURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let labRoot = appSupport.appendingPathComponent("FocusFlow2/DesignLab", isDirectory: true)
        archiveURL = labRoot.appendingPathComponent("component-decisions.json")

        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        load()
    }

    func decision(for component: DesignLabComponent) -> DesignLabComponentDecision {
        if let decision = decisions[component] {
            return decision
        }
        let decision = DesignLabComponentDecision(component: component)
        decisions[component] = decision
        return decision
    }

    func notesBinding(for component: DesignLabComponent) -> Binding<String> {
        Binding(
            get: { [weak self] in
                self?.decision(for: component).notes ?? ""
            },
            set: { [weak self] newValue in
                self?.updateNotes(newValue, for: component)
            }
        )
    }

    func winnerBinding(for component: DesignLabComponent) -> Binding<DesignLabVariant> {
        Binding(
            get: { [weak self] in
                self?.decision(for: component).winner ?? .a
            },
            set: { [weak self] newValue in
                self?.setWinner(newValue, for: component)
            }
        )
    }

    func statusBinding(for component: DesignLabComponent) -> Binding<DesignLabDecisionPhase> {
        Binding(
            get: { [weak self] in
                self?.decision(for: component).phase ?? .draft
            },
            set: { [weak self] newValue in
                self?.setPhase(newValue, for: component)
            }
        )
    }

    func hasUnlockedChanges(for component: DesignLabComponent) -> Bool {
        let decision = decision(for: component)
        return decision.phase != .locked && decision.phase != .promoted
    }

    func isLocked(for component: DesignLabComponent) -> Bool {
        decision(for: component).phase == .locked || decision(for: component).phase == .promoted
    }

    func isPromoted(for component: DesignLabComponent) -> Bool {
        decision(for: component).phase == .promoted
    }

    func variantDecision(for component: DesignLabComponent, variant: DesignLabVariant) -> DesignLabVariantDecision {
        decision(for: component).variantDecisions[variant.rawValue] ?? DesignLabVariantDecision()
    }

    func variantDecisionBinding(
        for component: DesignLabComponent,
        variant: DesignLabVariant
    ) -> Binding<DesignLabVariantDecision> {
        Binding(
            get: { [weak self] in
                self?.variantDecision(for: component, variant: variant) ?? DesignLabVariantDecision()
            },
            set: { [weak self] newValue in
                self?.updateVariantDecision(newValue, for: component, variant: variant)
            }
        )
    }

    func variantNotesBinding(for component: DesignLabComponent, variant: DesignLabVariant) -> Binding<String> {
        Binding(
            get: { [weak self] in
                self?.variantDecision(for: component, variant: variant).notes ?? ""
            },
            set: { [weak self] newValue in
                self?.updateVariantNotes(newValue, for: component, variant: variant)
            }
        )
    }

    func variantVerdictBinding(
        for component: DesignLabComponent,
        variant: DesignLabVariant
    ) -> Binding<DesignLabVariantVerdict> {
        Binding(
            get: { [weak self] in
                self?.variantDecision(for: component, variant: variant).verdict ?? .needsTweak
            },
            set: { [weak self] newValue in
                self?.setVariantVerdict(newValue, for: component, variant: variant)
            }
        )
    }

    func setWinner(_ winner: DesignLabVariant, for component: DesignLabComponent) {
        var decision = decision(for: component)
        guard decision.phase != .locked && decision.phase != .promoted else { return }
        decision.winner = winner
        decision.phase = decision.phase == .draft ? .compared : decision.phase
        decision.lastUpdatedAt = .now
        decisions[component] = decision
        persist()
    }

    func updateNotes(_ notes: String, for component: DesignLabComponent) {
        var decision = decision(for: component)
        guard decision.phase != .promoted else { return }
        decision.notes = notes
        if decision.phase == .draft {
            decision.phase = .compared
        }
        decision.lastUpdatedAt = .now
        decisions[component] = decision
        persist()
    }

    func updateVariantDecision(
        _ variantDecision: DesignLabVariantDecision,
        for component: DesignLabComponent,
        variant: DesignLabVariant
    ) {
        var decision = decision(for: component)
        guard decision.phase != .promoted else { return }
        decision.variantDecisions[variant.rawValue] = variantDecision
        decision.phase = decision.phase == .draft ? .compared : decision.phase
        decision.lastUpdatedAt = .now
        decisions[component] = decision
        persist()
    }

    func updateVariantNotes(_ notes: String, for component: DesignLabComponent, variant: DesignLabVariant) {
        var variantDecision = variantDecision(for: component, variant: variant)
        variantDecision.notes = notes
        variantDecision.updatedAt = .now
        updateVariantDecision(variantDecision, for: component, variant: variant)
    }

    func setVariantVerdict(_ verdict: DesignLabVariantVerdict, for component: DesignLabComponent, variant: DesignLabVariant) {
        var variantDecision = variantDecision(for: component, variant: variant)
        variantDecision.verdict = verdict
        variantDecision.updatedAt = .now
        updateVariantDecision(variantDecision, for: component, variant: variant)
    }

    func setPhase(_ phase: DesignLabDecisionPhase, for component: DesignLabComponent) {
        var decision = decision(for: component)
        guard decision.phase != .promoted else { return }
        decision.phase = phase
        if phase == .locked {
            decision.lockedAt = .now
        }
        if phase == .promoted {
            decision.promotedAt = .now
        }
        decision.lastUpdatedAt = .now
        decisions[component] = decision
        persist()
    }

    func markCompared(for component: DesignLabComponent) {
        setPhase(.compared, for: component)
    }

    func markTuned(for component: DesignLabComponent) {
        var decision = decision(for: component)
        guard decision.phase != .promoted else { return }
        decision.phase = .tuned
        decision.lastUpdatedAt = .now
        decisions[component] = decision
        persist()
    }

    func lock(_ component: DesignLabComponent) -> Bool {
        var decision = decision(for: component)
        guard decision.phase != .promoted else { return false }
        decision.phase = .locked
        decision.lockedAt = .now
        decision.lastUpdatedAt = .now
        decisions[component] = decision
        persist()
        return true
    }

    func promote(_ component: DesignLabComponent) -> Bool {
        var decision = decision(for: component)
        guard decision.phase == .locked else { return false }
        decision.phase = .promoted
        decision.promotedAt = .now
        decision.lastUpdatedAt = .now
        decisions[component] = decision
        persist()
        return true
    }

    func reset(_ component: DesignLabComponent) {
        guard decision(for: component).phase != .promoted else { return }
        decisions[component] = DesignLabComponentDecision(component: component)
        persist()
    }

    func appendSuggestion(_ suggestion: DesignLabGuidedFixSuggestion, for component: DesignLabComponent) {
        var decision = decision(for: component)
        guard decision.phase != .promoted else { return }
        decision.phase = .tuned
        decision.suggestionHistory.append(
            DesignLabSuggestionHistoryEntry(
                title: suggestion.title,
                detail: suggestion.adjustmentSummary
            )
        )
        decision.lastUpdatedAt = .now
        decisions[component] = decision
        persist()
    }

    func statusText(for component: DesignLabComponent) -> String {
        let decision = decision(for: component)
        let suffix = decision.winner.shortName
        return "\(decision.phase.title) · Winner \(suffix)"
    }

    func summary(for component: DesignLabComponent) -> String {
        let decision = decision(for: component)
        let notes = decision.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let noteSummary = notes.isEmpty ? "No notes yet" : String(notes.prefix(72))
        return "\(decision.phase.title) · Winner \(decision.winner.shortName) · \(noteSummary)"
    }

    func verdictBadgeText(for component: DesignLabComponent, variant: DesignLabVariant) -> String {
        variantDecision(for: component, variant: variant).verdict.rawValue
    }

    func entries(in order: [DesignLabComponent] = DesignLabComponent.allCases) -> [DesignLabComponentDecision] {
        order.compactMap { decisions[$0] ?? DesignLabComponentDecision(component: $0) }
    }

    private func persist() {
        let archive = DesignLabDecisionArchive(
            version: 1,
            decisions: entries(),
            updatedAt: .now
        )

        do {
            try FileManager.default.createDirectory(
                at: archiveURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try encoder.encode(archive)
            try data.write(to: archiveURL, options: .atomic)
        } catch {
            // Persistence is best-effort. The live UI remains the source of truth.
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: archiveURL),
              let archive = try? decoder.decode(DesignLabDecisionArchive.self, from: data) else {
            decisions = Dictionary(
                uniqueKeysWithValues: DesignLabComponent.allCases.map { ($0, DesignLabComponentDecision(component: $0)) }
            )
            return
        }

        decisions = Dictionary(uniqueKeysWithValues: archive.decisions.map { ($0.component, $0) })
        for component in DesignLabComponent.allCases where decisions[component] == nil {
            decisions[component] = DesignLabComponentDecision(component: component)
        }
    }
}
