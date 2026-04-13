import Foundation
import SwiftData

enum IdleDistractionTargetKind: String, Codable {
    case app
    case website
}

enum IdleDistractionSeverity: String, Codable {
    case major
    case minor
    case allowed
}

enum IdleDistractionSource: String, Codable {
    case manual
    case suggested
}

enum IdleDistractionStatus: String, Codable {
    case pending
    case active
    case dismissed
}

@Model
final class IdleDistractionItem {
    var key: String
    var displayName: String
    var targetKindRawValue: String
    var severityRawValue: String
    var sourceRawValue: String
    var statusRawValue: String
    var evidenceCount: Int
    var createdAt: Date
    var updatedAt: Date

    var targetKind: IdleDistractionTargetKind {
        get { IdleDistractionTargetKind(rawValue: targetKindRawValue) ?? .app }
        set { targetKindRawValue = newValue.rawValue }
    }

    var severity: IdleDistractionSeverity {
        get { IdleDistractionSeverity(rawValue: severityRawValue) ?? .minor }
        set { severityRawValue = newValue.rawValue }
    }

    var source: IdleDistractionSource {
        get { IdleDistractionSource(rawValue: sourceRawValue) ?? .suggested }
        set { sourceRawValue = newValue.rawValue }
    }

    var status: IdleDistractionStatus {
        get { IdleDistractionStatus(rawValue: statusRawValue) ?? .pending }
        set { statusRawValue = newValue.rawValue }
    }

    init(
        key: String,
        displayName: String,
        targetKind: IdleDistractionTargetKind,
        severity: IdleDistractionSeverity,
        source: IdleDistractionSource,
        status: IdleDistractionStatus,
        evidenceCount: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.key = key
        self.displayName = displayName
        self.targetKindRawValue = targetKind.rawValue
        self.severityRawValue = severity.rawValue
        self.sourceRawValue = source.rawValue
        self.statusRawValue = status.rawValue
        self.evidenceCount = evidenceCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension IdleDistractionItem {
    static func manualApp(_ bundleIdentifier: String, severity: IdleDistractionSeverity) -> IdleDistractionItem {
        let normalizedKey = normalizedAppKey(from: bundleIdentifier)
        return IdleDistractionItem(
            key: normalizedKey,
            displayName: AppUsageEntry.recommendationDisplayLabel(for: "app:\(normalizedKey)"),
            targetKind: .app,
            severity: severity,
            source: .manual,
            status: .active
        )
    }

    static func suggestedApp(_ bundleIdentifier: String, severity: IdleDistractionSeverity) -> IdleDistractionItem {
        let normalizedKey = normalizedAppKey(from: bundleIdentifier)
        return IdleDistractionItem(
            key: normalizedKey,
            displayName: AppUsageEntry.recommendationDisplayLabel(for: "app:\(normalizedKey)"),
            targetKind: .app,
            severity: severity,
            source: .suggested,
            status: .pending
        )
    }

    static func manualWebsite(_ hostOrURL: String, severity: IdleDistractionSeverity) -> IdleDistractionItem {
        let normalizedKey = normalizedWebsiteKey(from: hostOrURL)
        return IdleDistractionItem(
            key: normalizedKey,
            displayName: AppUsageEntry.domainDisplayName(for: normalizedKey),
            targetKind: .website,
            severity: severity,
            source: .manual,
            status: .active
        )
    }

    static func suggestedWebsite(_ hostOrURL: String, severity: IdleDistractionSeverity) -> IdleDistractionItem {
        let normalizedKey = normalizedWebsiteKey(from: hostOrURL)
        return IdleDistractionItem(
            key: normalizedKey,
            displayName: AppUsageEntry.domainDisplayName(for: normalizedKey),
            targetKind: .website,
            severity: severity,
            source: .suggested,
            status: .pending
        )
    }

    private static func normalizedAppKey(from bundleIdentifier: String) -> String {
        bundleIdentifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static func normalizedWebsiteKey(from hostOrURL: String) -> String {
        AppUsageEntry.normalizedBrowserHost(from: hostOrURL)
            ?? hostOrURL.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
