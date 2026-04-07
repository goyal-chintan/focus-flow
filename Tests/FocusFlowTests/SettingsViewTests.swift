import XCTest
@testable import FocusFlow

@MainActor
final class SettingsViewTests: XCTestCase {
    func testHasValidCapturedBrowserDomainsIgnoresMalformedDomainRows() {
        let entries = [
            AppUsageEntry(
                date: Date(),
                appName: "Arc",
                bundleIdentifier: "domain:company.thebrowser.browser",
                duringFocusSeconds: 120,
                outsideFocusSeconds: 0
            ),
            AppUsageEntry(
                date: Date(),
                appName: "YouTube",
                bundleIdentifier: "domain:youtube.com",
                duringFocusSeconds: 300,
                outsideFocusSeconds: 0
            )
        ]

        XCTAssertTrue(SettingsView.hasValidCapturedBrowserDomains(in: entries))
    }

    func testHasValidCapturedBrowserDomainsReturnsFalseForMalformedOnlyRows() {
        let entries = [
            AppUsageEntry(
                date: Date(),
                appName: "Arc",
                bundleIdentifier: "domain:company.thebrowser.browser",
                duringFocusSeconds: 120,
                outsideFocusSeconds: 0
            )
        ]

        XCTAssertFalse(SettingsView.hasValidCapturedBrowserDomains(in: entries))
    }
}
