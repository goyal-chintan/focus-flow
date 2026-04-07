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

    func testDomainTrackingRecoveryStateWaitsForFirstCaptureWhenAutomationIsAlreadyApproved() {
        let state = SettingsView.domainTrackingRecoveryState(
            collectRawDomains: true,
            hasCapturedBrowserDomains: false,
            frontmostBundleIdentifier: "company.thebrowser.browser",
            screenRecordingAccess: false,
            automationStatusProvider: { _ in .ready }
        )

        XCTAssertEqual(state, .awaitingFirstCapture)
    }

    func testDomainTrackingRecoveryStateFlagsAutomationOnlyWhenSupportedBrowserPermissionIsMissing() {
        let state = SettingsView.domainTrackingRecoveryState(
            collectRawDomains: true,
            hasCapturedBrowserDomains: false,
            frontmostBundleIdentifier: "company.thebrowser.browser",
            screenRecordingAccess: true,
            automationStatusProvider: { _ in .needsAction }
        )

        XCTAssertEqual(state, .automationUnavailable)
    }

    func testDomainTrackingRecoveryStateFallsBackToScreenRecordingForUnsupportedBrowserContext() {
        let state = SettingsView.domainTrackingRecoveryState(
            collectRawDomains: true,
            hasCapturedBrowserDomains: false,
            frontmostBundleIdentifier: "org.mozilla.firefox",
            screenRecordingAccess: false,
            automationStatusProvider: { _ in nil }
        )

        XCTAssertEqual(state, .screenRecordingUnavailable)
    }
}
