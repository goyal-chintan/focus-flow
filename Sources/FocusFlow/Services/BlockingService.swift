import Foundation

final class BlockingService: @unchecked Sendable {
    static let shared = BlockingService()
    private init() {}

    let appBlocker = AppBlocker()
    private(set) var isActive = false
    private var activeProfile: BlockProfile?

    func activate(profile: BlockProfile) {
        guard !isActive else { return }
        activeProfile = profile
        isActive = true
        let websites = profile.blockedWebsites
        if !websites.isEmpty { BlockingHelper.blockWebsites(websites) }
        let apps = profile.blockedApps
        if !apps.isEmpty { appBlocker.activate(bundleIDs: apps) }
    }

    func deactivate() {
        guard isActive else { return }
        if !(activeProfile?.blockedWebsites.isEmpty ?? true) { BlockingHelper.unblockWebsites() }
        appBlocker.deactivate()
        activeProfile = nil
        isActive = false
    }

    func cleanupIfNeeded() {
        if BlockingHelper.isBlockingActive() { BlockingHelper.unblockWebsites() }
    }
}
