import XCTest
@testable import FocusFlow

final class ContextObservationNormalizationTests: XCTestCase {

    func testNormalizeContextKeyPrefersBrowserHostAndLowercases() {
        let observation = SuspiciousContextObservation(
            bundleIdentifier: "com.apple.Safari",
            localizedAppName: "Safari",
            isInSession: true
        )

        let key = observation.normalizedContextKey(
            browserHost: "YouTube.COM",
            terminalWorkspace: "Repo-A",
            editorWorkspace: "Workspace-B",
            bundleIdentifier: "com.apple.Safari",
            appName: "Safari"
        )

        XCTAssertEqual(key, "youtube.com")
    }

    func testNormalizeContextKeyFallsBackToWorkspaceThenBundleThenAppName() {
        let observation = SuspiciousContextObservation(
            bundleIdentifier: "com.mitchellh.ghostty",
            localizedAppName: "Ghostty",
            isInSession: true
        )

        let workspaceKey = observation.normalizedContextKey(
            browserHost: nil,
            terminalWorkspace: "MyRepo",
            editorWorkspace: "OtherWorkspace",
            bundleIdentifier: "com.mitchellh.ghostty",
            appName: "Ghostty"
        )
        XCTAssertEqual(workspaceKey, "myrepo")

        let bundleKey = observation.normalizedContextKey(
            browserHost: nil,
            terminalWorkspace: nil,
            editorWorkspace: nil,
            bundleIdentifier: "com.Mitchellh.Ghostty",
            appName: "Ghostty"
        )
        XCTAssertEqual(bundleKey, "com.mitchellh.ghostty")

        let appKey = observation.normalizedContextKey(
            browserHost: nil,
            terminalWorkspace: nil,
            editorWorkspace: nil,
            bundleIdentifier: "",
            appName: "  My Cool App  "
        )
        XCTAssertEqual(appKey, "my cool app")
    }
}
