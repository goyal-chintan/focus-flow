import Foundation
import AppKit

@MainActor
final class AppBlocker: NSObject {
    private var blockedBundleIDs: Set<String> = []
    private var monitorTimer: Timer?
    private let monitorInterval: TimeInterval = 15

    func activate(bundleIDs: [String]) {
        guard !bundleIDs.isEmpty else { return }
        blockedBundleIDs = Set(bundleIDs)
        installWorkspaceObservers()
        terminateBlockedApps()
        monitorTimer?.invalidate()
        let timer = Timer.scheduledTimer(
            timeInterval: monitorInterval,
            target: self,
            selector: #selector(handleMonitorTimer),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer, forMode: .common)
        monitorTimer = timer
    }

    func deactivate() {
        monitorTimer?.invalidate()
        monitorTimer = nil
        removeWorkspaceObservers()
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

    private func installWorkspaceObservers() {
        let notificationCenter = NSWorkspace.shared.notificationCenter
        notificationCenter.removeObserver(
            self,
            name: NSWorkspace.didLaunchApplicationNotification,
            object: nil
        )
        notificationCenter.removeObserver(
            self,
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(handleDidLaunchApplication(_:)),
            name: NSWorkspace.didLaunchApplicationNotification,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(handleDidActivateApplication(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    private func removeWorkspaceObservers() {
        let notificationCenter = NSWorkspace.shared.notificationCenter
        notificationCenter.removeObserver(
            self,
            name: NSWorkspace.didLaunchApplicationNotification,
            object: nil
        )
        notificationCenter.removeObserver(
            self,
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    private func terminateBlockedApplication(app: NSRunningApplication, bundleID: String) {
        guard blockedBundleIDs.contains(bundleID) else { return }
        app.terminate()
    }

    @objc
    private func handleMonitorTimer() {
        terminateBlockedApps()
    }

    @objc
    private func handleDidLaunchApplication(_ notification: Notification) {
        handleWorkspaceApplicationNotification(notification)
    }

    @objc
    private func handleDidActivateApplication(_ notification: Notification) {
        handleWorkspaceApplicationNotification(notification)
    }

    private func handleWorkspaceApplicationNotification(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleID = app.bundleIdentifier else { return }
        terminateBlockedApplication(app: app, bundleID: bundleID)
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
