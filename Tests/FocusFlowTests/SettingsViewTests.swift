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

    // MARK: Tab bar and transitions

    func testPermissionsTabKeepsStoredRawValueAndLockShieldSymbol() {
        XCTAssertEqual(SettingsTab.integrations.title, "Permissions")
        XCTAssertEqual(SettingsTab.integrations.icon, "lock.shield")
        XCTAssertEqual(SettingsTab(rawValue: "integrations"), .integrations)
        XCTAssertEqual(SettingsTab.allCases.map(\.title), ["General", "Timer", "Coach", "Distractions", "Permissions"])
        XCTAssertEqual(SettingsTab.allCases.map(\.order), [0, 1, 2, 3, 4])
    }

    func testSlideDirectionFollowsTabOrder() {
        XCTAssertEqual(SettingsTabSlideDirection(from: .general, to: .coach), .forward)
        XCTAssertEqual(SettingsTabSlideDirection(from: .integrations, to: .timer), .backward)
        XCTAssertEqual(SettingsTabSlideDirection.forward.sign, 1)
        XCTAssertEqual(SettingsTabSlideDirection.backward.sign, -1)
        XCTAssertEqual(SettingsTabMotion.slideDistance, 8)
    }

    func testRequestedTabIsConsumedOnce() throws {
        let suite = "SettingsViewTests.requestedTab.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertNil(SettingsTab.consumeRequestedTab(from: defaults))
        defaults.set("coach", forKey: SettingsTab.requestedTabKey)
        XCTAssertEqual(SettingsTab.consumeRequestedTab(from: defaults), .coach)
        XCTAssertNil(defaults.string(forKey: SettingsTab.requestedTabKey))
        XCTAssertNil(SettingsTab.consumeRequestedTab(from: defaults))

        defaults.set("bogus", forKey: SettingsTab.requestedTabKey)
        XCTAssertNil(SettingsTab.consumeRequestedTab(from: defaults))
        XCTAssertNil(defaults.string(forKey: SettingsTab.requestedTabKey))
    }

    // MARK: Coach rescue

    func testPauseScreenOffOfferOnlyForSofterStylesWhileOn() {
        XCTAssertTrue(CoachSettingsTab.shouldOfferPauseScreenOff(style: .gentle, pauseScreenEnabled: true))
        XCTAssertTrue(CoachSettingsTab.shouldOfferPauseScreenOff(style: .data, pauseScreenEnabled: true))
        XCTAssertFalse(CoachSettingsTab.shouldOfferPauseScreenOff(style: .challenger, pauseScreenEnabled: true))
        XCTAssertFalse(CoachSettingsTab.shouldOfferPauseScreenOff(style: .gentle, pauseScreenEnabled: false))
    }

    func testStarterBlockChoiceSnapsToOfferedLengths() {
        XCTAssertEqual(CoachSettingsTab.starterBlockChoices, [2, 5, 10])
        XCTAssertEqual(CoachSettingsTab.starterBlockChoice(for: 5), 5)
        XCTAssertEqual(CoachSettingsTab.starterBlockChoice(for: 1), 2)
        XCTAssertEqual(CoachSettingsTab.starterBlockChoice(for: 8), 10)
        XCTAssertEqual(CoachSettingsTab.starterBlockChoice(for: 25), 10)
        XCTAssertEqual(AppSettings().coachStarterBlockMinutes, 5)
    }
}
