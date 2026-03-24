import XCTest
@testable import FocusFlow

final class ScreenShareGuardTests: XCTestCase {
    func testSuppressionDisabledReturnsFalseEvenWhenScreenSharing() {
        let guardService = ScreenShareGuard(isScreenSharingProvider: { true })
        XCTAssertFalse(guardService.shouldSuppressGuardianPopups(enabled: false))
    }

    func testSuppressionEnabledReturnsTrueWhenScreenSharing() {
        let guardService = ScreenShareGuard(isScreenSharingProvider: { true })
        XCTAssertTrue(guardService.shouldSuppressGuardianPopups(enabled: true))
    }

    func testSuppressionEnabledReturnsFalseWhenNotScreenSharing() {
        let guardService = ScreenShareGuard(isScreenSharingProvider: { false })
        XCTAssertFalse(guardService.shouldSuppressGuardianPopups(enabled: true))
    }

    func testHeuristicDetectsKnownMeetingBundleIdentifiers() {
        XCTAssertTrue(
            ScreenShareGuard.isLikelyScreenShareSensitiveContext(
                bundleIdentifier: "us.zoom.xos",
                appName: "zoom.us"
            )
        )
        XCTAssertTrue(
            ScreenShareGuard.isLikelyScreenShareSensitiveContext(
                bundleIdentifier: "com.microsoft.teams2",
                appName: "Microsoft Teams"
            )
        )
        XCTAssertTrue(
            ScreenShareGuard.isLikelyScreenShareSensitiveContext(
                bundleIdentifier: "com.cisco.webexmeetingsapp",
                appName: "Webex"
            )
        )
    }

    func testDefaultHeuristicEvaluatorCanSuppressMeetingFrontmostApp() {
        let frontmost = ScreenShareGuard.FrontmostApplication(
            bundleIdentifier: "com.microsoft.teams2",
            localizedName: "Microsoft Teams"
        )

        XCTAssertTrue(ScreenShareGuard.shouldSuppressForFrontmostApplication(frontmost))
    }

    func testDefaultHeuristicPathCanTriggerSuppressionWhenShareProviderReturnsFalse() {
        let guardService = ScreenShareGuard(
            isScreenSharingProvider: { false },
            frontmostApplicationProvider: {
                ScreenShareGuard.FrontmostApplication(
                    bundleIdentifier: "com.microsoft.teams",
                    localizedName: "Microsoft Teams"
                )
            }
        )

        XCTAssertTrue(guardService.shouldSuppressGuardianPopups(enabled: true))
    }
}
