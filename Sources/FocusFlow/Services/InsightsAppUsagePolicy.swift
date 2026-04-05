import Foundation

enum InsightsAppUsagePolicy {
    static func visibleEntries(
        from entries: [AppUsageEntry],
        collectRawDomains: Bool
    ) -> [AppUsageEntry] {
        entries.filter { entry in
            if CompanionAnalyticsBuilder.isPersistedDomainBundleIdentifier(entry.bundleIdentifier) {
                guard collectRawDomains else { return false }
                return CompanionAnalyticsBuilder.validPersistedDomainHost(for: entry.bundleIdentifier) != nil
            }
            return true
        }
    }
}
