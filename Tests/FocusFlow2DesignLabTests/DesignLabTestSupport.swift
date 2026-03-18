import Foundation
import Darwin

enum DesignLabTestSupport {
    private static let appSupportOverrideEnv = "FOCUSFLOW2_APP_SUPPORT_ROOT"

    static func withTemporaryHome<T>(_ body: () throws -> T) rethrows -> T {
        let originalHome = ProcessInfo.processInfo.environment["HOME"]
        let originalAppSupportOverride = ProcessInfo.processInfo.environment[appSupportOverrideEnv]
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("FocusFlow2DesignLabTests-\(UUID().uuidString)", isDirectory: true)
        let appSupportRoot = tempRoot.appendingPathComponent("Application Support", isDirectory: true)

        try? FileManager.default.createDirectory(at: appSupportRoot, withIntermediateDirectories: true)
        setenv("HOME", tempRoot.path, 1)
        setenv(appSupportOverrideEnv, appSupportRoot.path, 1)

        defer {
            if let originalHome {
                setenv("HOME", originalHome, 1)
            } else {
                unsetenv("HOME")
            }
            if let originalAppSupportOverride {
                setenv(appSupportOverrideEnv, originalAppSupportOverride, 1)
            } else {
                unsetenv(appSupportOverrideEnv)
            }
            try? FileManager.default.removeItem(at: tempRoot)
        }

        return try body()
    }

    static func applicationSupportRoot() -> URL {
        if let override = ProcessInfo.processInfo.environment[appSupportOverrideEnv], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    }

    static func designLabRoot() -> URL {
        applicationSupportRoot()
            .appendingPathComponent("FocusFlow2", isDirectory: true)
            .appendingPathComponent("DesignLab", isDirectory: true)
    }

    static func variantLabRoot() -> URL {
        applicationSupportRoot()
            .appendingPathComponent("FocusFlow2", isDirectory: true)
            .appendingPathComponent("VariantLab", isDirectory: true)
    }

    static func readString(_ url: URL) -> String? {
        try? String(contentsOf: url, encoding: .utf8)
    }

    static func removeIfExists(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
