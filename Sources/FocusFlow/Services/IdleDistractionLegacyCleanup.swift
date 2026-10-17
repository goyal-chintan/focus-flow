import Foundation
import OSLog
import SwiftData

/// One-time cleanup of `IdleDistractionItem` rows that should never have been created:
/// - rows keyed by macOS system processes (screen lock, screensaver, auth prompts, Dock), and
/// - pending auto-suggested rows for everyday work tools (Jira, GitHub, Gmail, Slack, Cursor, ...).
enum IdleDistractionLegacyCleanup {
    private static let logger = Logger(subsystem: "FocusFlow", category: "IdleDistractionLegacyCleanup")

    /// UserDefaults flag set once the cleanup has committed successfully.
    static let completedFlagKey = "idleDistractionLegacyCleanupV1Completed"

    static let workToolDomainFragments: [String] = [
        "atlassian.net",
        "github.com",
        "mail.google.com",
    ]

    static let workToolAppFragments: [String] = [
        "slack",
        "cursor",
        "com.todesktop.230313mzl4w4u92",
        "anthropic",
        "claude",
        "jetbrains",
    ]

    /// Pure predicate, so the rules can be tested without SwiftData.
    static func shouldDelete(_ item: IdleDistractionItem) -> Bool {
        let key = item.key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if AppUsageTracker.isIgnoredSystemBundleIdentifier(key) {
            return true
        }
        guard item.status == .pending, item.source == .suggested else { return false }
        return isWorkTool(key: key, kind: item.targetKind)
    }

    static func isWorkTool(key: String, kind: IdleDistractionTargetKind) -> Bool {
        let normalized = key.lowercased()
        switch kind {
        case .website:
            return workToolDomainFragments.contains { normalized.contains($0) }
        case .app:
            return workToolAppFragments.contains { normalized.contains($0) }
        }
    }

    /// Deletes matching rows once per install. Returns the number deleted (0 when already run).
    @discardableResult
    static func runOnce(in context: ModelContext, defaults: UserDefaults = .standard) -> Int {
        guard !defaults.bool(forKey: completedFlagKey) else { return 0 }
        do {
            let items = try context.fetch(FetchDescriptor<IdleDistractionItem>())
            let stale = items.filter(shouldDelete)
            stale.forEach { context.delete($0) }
            try context.save()
            defaults.set(true, forKey: completedFlagKey)
            logger.notice("Legacy idle-distraction cleanup deleted \(stale.count, privacy: .public) rows")
            return stale.count
        } catch {
            logger.error("Legacy idle-distraction cleanup failed: \(error.localizedDescription, privacy: .public)")
            return 0
        }
    }
}
