import Foundation

enum IdleDistractionEvidenceOutcome: Equatable {
    case ignoredNudge
}

struct IdleDistractionCatalog {
    static let suggestionEvidenceThreshold = 2

    enum Target: Equatable {
        case app(String)
        case website(String)

        var kind: IdleDistractionTargetKind {
            switch self {
            case .app:
                return .app
            case .website:
                return .website
            }
        }

        var normalizedKey: String {
            switch self {
            case .app(let bundleIdentifier):
                return bundleIdentifier
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
            case .website(let hostOrURL):
                return AppUsageEntry.normalizedBrowserHost(from: hostOrURL)
                    ?? hostOrURL.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            }
        }
    }

    struct Resolution: Equatable {
        let severity: IdleDistractionSeverity?
        let hasSuggestion: Bool
    }

    var items: [IdleDistractionItem]

    func resolution(for target: Target) -> Resolution {
        let relevantItems = relevantItems(for: target)
        let hasSuggestion = relevantItems.contains {
            $0.source == .suggested &&
            $0.status == .pending &&
            $0.evidenceCount >= Self.suggestionEvidenceThreshold
        }

        if let manualRule = relevantItems.last(where: { $0.source == .manual && $0.status == .active }) {
            return Resolution(severity: manualRule.severity, hasSuggestion: hasSuggestion)
        }

        if let acceptedSuggestion = relevantItems.last(where: {
            $0.source == .suggested && $0.status == .active
        }) {
            return Resolution(severity: acceptedSuggestion.severity, hasSuggestion: hasSuggestion)
        }

        return Resolution(severity: nil, hasSuggestion: hasSuggestion)
    }

    @discardableResult
    mutating func recordIdleEvidence(
        target: Target,
        displayName: String,
        outcome: IdleDistractionEvidenceOutcome
    ) -> IdleDistractionItem? {
        guard outcome == .ignoredNudge else { return nil }
        guard relevantItems(for: target).contains(where: { $0.status == .active }) == false else {
            return nil
        }

        let now = Date()
        if let existingSuggestion = items.last(where: {
            $0.targetKind == target.kind &&
            $0.key == target.normalizedKey &&
            $0.source == .suggested &&
            $0.status == .pending
        }) {
            existingSuggestion.displayName = displayName
            existingSuggestion.evidenceCount += 1
            existingSuggestion.updatedAt = now
            return nil
        }

        let suggestion = IdleDistractionItem(
            key: target.normalizedKey,
            displayName: displayName,
            targetKind: target.kind,
            severity: .minor,
            source: .suggested,
            status: .pending,
            evidenceCount: 1,
            createdAt: now,
            updatedAt: now
        )
        items.append(suggestion)
        return suggestion
    }

    private func relevantItems(for target: Target) -> [IdleDistractionItem] {
        items.filter {
            $0.targetKind == target.kind &&
            $0.key == target.normalizedKey &&
            $0.status != .dismissed
        }
    }
}
