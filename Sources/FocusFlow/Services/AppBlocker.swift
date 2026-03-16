import Foundation
import AppKit

final class AppBlocker {
    private var blockedBundleIDs: Set<String> = []
    private var monitorTimer: Timer?

    func activate(bundleIDs: [String]) {
        guard !bundleIDs.isEmpty else { return }
        blockedBundleIDs = Set(bundleIDs)
        terminateBlockedApps()
        monitorTimer?.invalidate()
        let t = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.terminateBlockedApps() }
        }
        RunLoop.main.add(t, forMode: .common)
        monitorTimer = t
    }

    func deactivate() {
        monitorTimer?.invalidate()
        monitorTimer = nil
        blockedBundleIDs.removeAll()
    }

    var isActive: Bool { !blockedBundleIDs.isEmpty }

    private func terminateBlockedApps() {
        for app in NSWorkspace.shared.runningApplications {
            guard let bundleID = app.bundleIdentifier else { continue }
            if blockedBundleIDs.contains(bundleID) {
                app.terminate()
            }
        }
    }

    static func installedApps() -> [(name: String, bundleID: String)] {
        var apps: [(String, String)] = []
        let dirs = [URL(fileURLWithPath: "/Applications"), URL(fileURLWithPath: "/System/Applications")]
        for dir in dirs {
            guard let contents = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            for url in contents where url.pathExtension == "app" {
                guard let bundle = Bundle(url: url),
                      let bundleID = bundle.bundleIdentifier else { continue }
                let name = (bundle.infoDictionary?["CFBundleName"] as? String)
                    ?? (bundle.infoDictionary?["CFBundleDisplayName"] as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                apps.append((name, bundleID))
            }
        }
        return apps.sorted { $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }
    }
}
