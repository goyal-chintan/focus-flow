import Foundation

final class BlockingService: @unchecked Sendable {
    static let shared = BlockingService()
    private init() {}

    let appBlocker = AppBlocker()
    private(set) var isActive = false
    private var activeProfile: BlockProfile?

    func activate(profile: BlockProfile) {
        guard !isActive else {
            print("[BlockingService] Already active, skipping")
            return
        }
        activeProfile = profile
        isActive = true
        print("[BlockingService] Activating profile: \(profile.name)")

        // Website blocking
        let websites = profile.blockedWebsites
        print("[BlockingService] Blocking \(websites.count) websites: \(websites)")
        if !websites.isEmpty {
            BlockingHelper.blockWebsites(websites)
        }

        // App blocking
        let apps = profile.blockedApps
        print("[BlockingService] Blocking \(apps.count) apps: \(apps)")
        if !apps.isEmpty {
            appBlocker.activate(bundleIDs: apps)
        }
    }

    func deactivate() {
        guard isActive else { return }
        print("[BlockingService] Deactivating blocking")
        if !(activeProfile?.blockedWebsites.isEmpty ?? true) {
            BlockingHelper.unblockWebsites()
        }
        appBlocker.deactivate()
        activeProfile = nil
        isActive = false
    }

    /// Only clean up if there are stale entries — checks /etc/hosts without admin
    /// Only prompts for admin password if cleanup is actually needed
    func cleanupIfNeeded() {
        if BlockingHelper.isBlockingActive() {
            print("[BlockingService] Found stale blocking entries — cleaning up")
            BlockingHelper.unblockWebsites()
        } else {
            print("[BlockingService] No stale blocking — skipping cleanup")
        }
    }
}
