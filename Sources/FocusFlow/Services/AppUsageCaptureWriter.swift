import Foundation

struct AppUsageCaptureWriter {
    struct DomainUsageIdentity {
        let bundleIdentifier: String
        let appName: String
    }

    typealias EntryResolver = (_ bundleIdentifier: String, _ appName: String) -> AppUsageEntry

    func browserDomainUsageIdentity(
        resolvedHost: String?,
        settings: AppSettings?
    ) -> DomainUsageIdentity? {
        guard settings?.coachCollectRawDomains == true,
              let host = AppUsageEntry.normalizedBrowserHost(from: resolvedHost) else {
            return nil
        }

        return DomainUsageIdentity(
            bundleIdentifier: "domain:\(host)",
            appName: AppUsageEntry.domainDisplayName(for: host)
        )
    }

    @discardableResult
    func recordBrowserDomainUsage(
        resolvedHost: String?,
        settings: AppSettings?,
        isFocusing: Bool,
        entryForKey: EntryResolver
    ) -> AppUsageEntry? {
        guard let identity = browserDomainUsageIdentity(
            resolvedHost: resolvedHost,
            settings: settings
        ) else {
            return nil
        }

        let entry = entryForKey(identity.bundleIdentifier, identity.appName)
        if isFocusing {
            entry.duringFocusSeconds += 1
        } else {
            entry.outsideFocusSeconds += 1
        }
        return entry
    }
}
