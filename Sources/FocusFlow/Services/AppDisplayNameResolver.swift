import AppKit
import Foundation

/// Resolves a user-facing app name from a bundle identifier, e.g. "Cursor" for
/// com.todesktop.230313mzl4w4u92. Uses the installed .app bundle and caches the result per identifier.
enum AppDisplayNameResolver {
    /// Bundle identifier -> installed .app URL. Tests override this so they never touch the real system.
    nonisolated(unsafe) static var applicationURLProvider: (String) -> URL? = { bundleIdentifier in
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
    }

    /// .app URL -> Finder display name. Tests override this as well.
    nonisolated(unsafe) static var displayNameProvider: (URL) -> String = { url in
        FileManager.default.displayName(atPath: url.path)
    }

    private static let lock = NSLock()
    /// Caches misses too (a nil value), so uninstalled bundle IDs are not re-queried.
    nonisolated(unsafe) private static var cache: [String: String?] = [:]

    /// The installed app's display name with the `.app` suffix stripped, or nil when it cannot be resolved.
    static func displayName(forBundleIdentifier bundleIdentifier: String) -> String? {
        lock.lock()
        if let cached = cache[bundleIdentifier] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let resolved = resolve(bundleIdentifier: bundleIdentifier)

        lock.lock()
        cache[bundleIdentifier] = resolved
        lock.unlock()
        return resolved
    }

    /// Drops cached results. Call before and after overriding the providers in tests.
    static func resetCache() {
        lock.lock()
        cache.removeAll()
        lock.unlock()
    }

    private static func resolve(bundleIdentifier: String) -> String? {
        guard let url = applicationURLProvider(bundleIdentifier) else { return nil }
        var name = displayNameProvider(url).trimmingCharacters(in: .whitespacesAndNewlines)
        if name.hasSuffix(".app") {
            name.removeLast(4)
        }
        return name.isEmpty ? nil : name
    }
}
