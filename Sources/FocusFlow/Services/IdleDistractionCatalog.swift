import Foundation

struct IdleDistractionCatalog {
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
        let relevantItems = items.filter {
            $0.targetKind == target.kind &&
            $0.key == target.normalizedKey &&
            $0.status != .dismissed
        }
        let hasSuggestion = relevantItems.contains {
            $0.source == .suggested && $0.status == .pending
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
}
