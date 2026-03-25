import Foundation

@MainActor
final class BlockingService {
    static let shared = BlockingService()
    private init() {}

    let appBlocker = AppBlocker()
    private(set) var isActive = false
    private var activeProfiles: [BlockProfile] = []
    private var activeBlockedWebsites: [String] = []

    func activate(profile: BlockProfile) {
        activate(profiles: [profile])
    }

    func activate(profiles: [BlockProfile]) {
        let uniqueProfiles = deduplicatedProfiles(profiles)
        guard !uniqueProfiles.isEmpty else {
            print("[BlockingService] No profiles provided; skipping activation")
            return
        }

        if isActive {
            deactivate()
        }

        activeProfiles = uniqueProfiles
        isActive = true
        let profileNames = uniqueProfiles.map(\.name).joined(separator: ", ")
        print("[BlockingService] Activating profiles: \(profileNames)")

        let websites = Array(Set(uniqueProfiles.flatMap(\.blockedWebsites))).sorted()
        activeBlockedWebsites = websites
        let logMsg = "[BlockingService] profiles=\(profileNames) parsedWebsites=\(websites)\n"
        let logPath = NSHomeDirectory() + "/Library/Application Support/FocusFlow/blocking.log"
        try? logMsg.write(toFile: logPath, atomically: true, encoding: .utf8)
        if !websites.isEmpty {
            print("[BlockingService] Calling BlockingHelper.blockWebsites...")
            BlockingHelper.blockWebsites(websites)
        } else {
            print("[BlockingService] WARNING: No websites to block!")
        }

        let apps = Array(Set(uniqueProfiles.flatMap(\.blockedApps))).sorted()
        print("[BlockingService] Blocking \(apps.count) apps: \(apps)")
        if !apps.isEmpty {
            appBlocker.activate(bundleIDs: apps)
        }
    }

    func deactivate() {
        guard isActive else { return }
        print("[BlockingService] Deactivating blocking")
        if !activeBlockedWebsites.isEmpty {
            BlockingHelper.unblockWebsites()
        }
        appBlocker.deactivate()
        activeProfiles = []
        activeBlockedWebsites = []
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

    private func deduplicatedProfiles(_ profiles: [BlockProfile]) -> [BlockProfile] {
        var seen = Set<UUID>()
        var unique: [BlockProfile] = []
        for profile in profiles {
            if seen.insert(profile.id).inserted {
                unique.append(profile)
            }
        }
        return unique
    }
}
