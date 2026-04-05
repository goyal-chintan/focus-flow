import XCTest
@testable import FocusFlow

final class BrowserDomainResolverTests: XCTestCase {

    func testSafariResolverUsesActiveTabURLAndNormalizesDomain() {
        var executedScripts: [String] = []
        let resolver = BrowserDomainResolver { script in
            executedScripts.append(script)
            return "https://www.youtube.com/watch?v=123"
        }

        let resolution = resolver.resolve(
            bundleIdentifier: "com.apple.Safari",
            windowTitle: "Ignored Title",
            appName: "Safari"
        )

        XCTAssertEqual(resolution?.host, "youtube.com")
        XCTAssertEqual(resolution?.displayLabel, "YouTube")
        XCTAssertTrue(executedScripts.first?.contains(#"application id "com.apple.safari""#) == true)
        XCTAssertTrue(executedScripts.contains { $0.contains("URL of current tab of front window") })
    }

    func testChromiumResolverUsesActiveTabURLAndFriendlyLabel() {
        var executedScripts: [String] = []
        let resolver = BrowserDomainResolver { script in
            executedScripts.append(script)
            return "https://docs.github.com/en/copilot"
        }

        let resolution = resolver.resolve(
            bundleIdentifier: "com.google.Chrome",
            windowTitle: "Ignored Title",
            appName: "Google Chrome"
        )

        XCTAssertEqual(resolution?.host, "docs.github.com")
        XCTAssertEqual(resolution?.displayLabel, "GitHub")
        XCTAssertTrue(executedScripts.first?.contains(#"application id "com.google.chrome""#) == true)
        XCTAssertTrue(executedScripts.contains { $0.contains("URL of active tab of front window") })
    }

    func testResolverRejectsBundleIdentifierMasqueradingAsDomain() {
        let resolver = BrowserDomainResolver { _ in
            "company.thebrowser.browser"
        }

        let resolution = resolver.resolve(
            bundleIdentifier: "company.thebrowser.browser",
            windowTitle: "Arc",
            appName: "Arc"
        )

        XCTAssertNil(resolution)
    }

    func testResolverFallsBackToTitleHeuristicsWhenAppleScriptFails() {
        let resolver = BrowserDomainResolver { _ in nil }

        let resolution = resolver.resolve(
            bundleIdentifier: "org.mozilla.firefox",
            windowTitle: "YouTube - Watch",
            appName: "Firefox"
        )

        XCTAssertEqual(resolution?.host, "youtube.com")
        XCTAssertEqual(resolution?.displayLabel, "YouTube")
    }

    func testResolverFallbackRecognizesSpotifyTitles() {
        let resolver = BrowserDomainResolver { _ in nil }

        let resolution = resolver.resolve(
            bundleIdentifier: "org.mozilla.firefox",
            windowTitle: "Focus Mix - Spotify",
            appName: "Firefox"
        )

        XCTAssertEqual(resolution?.host, "spotify.com")
        XCTAssertEqual(resolution?.displayLabel, "Spotify")
    }

    func testResolverTriesNextAppleScriptBeforeFallingBackToTitleHeuristics() {
        var executedScripts: [String] = []
        let resolver = BrowserDomainResolver { script in
            executedScripts.append(script)
            return executedScripts.count == 1 ? "company.thebrowser.browser" : "https://linear.app/focusflow/issue"
        }

        let resolution = resolver.resolve(
            bundleIdentifier: "com.google.Chrome",
            windowTitle: "YouTube - Watch",
            appName: "Google Chrome"
        )

        XCTAssertEqual(executedScripts.count, 2)
        XCTAssertEqual(resolution?.host, "linear.app")
        XCTAssertEqual(resolution?.displayLabel, "linear.app")
    }
}
