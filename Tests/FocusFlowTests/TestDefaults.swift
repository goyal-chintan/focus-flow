import Foundation
import XCTest

/// Preferences suites for tests. Each suite has a unique name and is removed afterwards, file
/// included: macOS keeps an empty `<suite>.plist` after `removePersistentDomain`, and one file per
/// test run had filled ~/Library/Preferences with about 8,700 of them (found 6 Nov 2026).
enum TestDefaults {
    static let prefix = "FocusFlowTests."

    static func make(_ tag: String) -> (defaults: UserDefaults, name: String) {
        let name = "\(prefix)\(tag).\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }

    /// Clears the suite and deletes its file.
    static func remove(_ name: String) {
        UserDefaults(suiteName: name)?.removePersistentDomain(forName: name)
        // Let the preferences daemon write the removal now; otherwise it recreates the file
        // after we delete it.
        CFPreferencesAppSynchronize(name as CFString)
        let file = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/\(name).plist")
        try? FileManager.default.removeItem(at: file)
    }
}

extension XCTestCase {
    /// A fresh suite, removed (file too) when the test ends.
    func cleanDefaults(_ tag: String) -> UserDefaults {
        let (defaults, name) = TestDefaults.make(tag)
        addTeardownBlock { TestDefaults.remove(name) }
        return defaults
    }
}
