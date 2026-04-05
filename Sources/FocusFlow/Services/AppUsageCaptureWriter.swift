import Foundation

struct AppUsageCaptureWriter {
    typealias EntryResolver = (_ bundleIdentifier: String, _ appName: String) -> AppUsageEntry

    @discardableResult
    func recordBrowserDomainUsage(
        resolvedHost: String?,
        settings: AppSettings?,
        isFocusing: Bool,
        entryForKey: EntryResolver
    ) -> AppUsageEntry? {
        guard settings?.coachCollectRawDomains == true,
              let host = AppUsageEntry.normalizedBrowserHost(from: resolvedHost) else {
            return nil
        }

        let entry = entryForKey("domain:\(host)", AppUsageEntry.domainDisplayName(for: host))
        if isFocusing {
            entry.duringFocusSeconds += 1
        } else {
            entry.outsideFocusSeconds += 1
        }
        return entry
    }
}
