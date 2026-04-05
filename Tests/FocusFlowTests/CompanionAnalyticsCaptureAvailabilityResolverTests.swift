import XCTest
@testable import FocusFlow

final class CompanionAnalyticsCaptureAvailabilityResolverTests: XCTestCase {
    func testResolveReturnsUnavailableForUnsupportedBrowserWithoutScreenCapture() {
        let availability = CompanionAnalyticsCaptureAvailabilityResolver.resolve(
            frontmostBundleId: "org.mozilla.firefox",
            screenCaptureAccessGranted: false
        )

        XCTAssertEqual(availability, .unavailable)
    }

    func testResolveReturnsAvailableForSupportedBrowserWithoutScreenCapture() {
        let availability = CompanionAnalyticsCaptureAvailabilityResolver.resolve(
            frontmostBundleId: "com.apple.Safari",
            screenCaptureAccessGranted: false
        )

        XCTAssertEqual(availability, .available)
    }

    func testResolveReturnsAvailableForNonBrowserWithoutScreenCapture() {
        let availability = CompanionAnalyticsCaptureAvailabilityResolver.resolve(
            frontmostBundleId: "com.apple.dt.Xcode",
            screenCaptureAccessGranted: false
        )

        XCTAssertEqual(availability, .available)
    }

    func testResolveReturnsAvailableForFallbackOnlyBrowserWhenScreenCaptureGranted() {
        let availability = CompanionAnalyticsCaptureAvailabilityResolver.resolve(
            frontmostBundleId: "org.mozilla.firefox",
            screenCaptureAccessGranted: true
        )

        XCTAssertEqual(availability, .available)
    }

    func testResolveReturnsAvailableForSupportedBrowserAndNonBrowserApps() {
        let supportedBrowser = CompanionAnalyticsCaptureAvailabilityResolver.resolve(
            frontmostBundleId: "com.apple.Safari",
            screenCaptureAccessGranted: true
        )
        let nonBrowser = CompanionAnalyticsCaptureAvailabilityResolver.resolve(
            frontmostBundleId: "com.apple.dt.Xcode",
            screenCaptureAccessGranted: true
        )

        XCTAssertEqual(supportedBrowser, .available)
        XCTAssertEqual(nonBrowser, .available)
    }

    func testResolveReturnsAvailableWhenNoFrontmostAppIsKnown() {
        let availability = CompanionAnalyticsCaptureAvailabilityResolver.resolve(
            frontmostBundleId: nil,
            screenCaptureAccessGranted: false
        )

        XCTAssertEqual(availability, .available)
    }
}
