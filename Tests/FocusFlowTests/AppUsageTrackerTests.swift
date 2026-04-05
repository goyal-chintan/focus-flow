import XCTest
@testable import FocusFlow

@MainActor
final class AppUsageTrackerTests: XCTestCase {
    func testFrontmostBrowserContextSanitizesBrowserCoachingSignalsWhenDomainCaptureDisabled() {
        let settings = AppSettings()
        settings.coachCollectRawDomains = false

        let context = AppUsageTracker.frontmostContextPresentation(
            bundleIdentifier: "com.apple.Safari",
            appName: "Safari",
            windowTitle: "Sorting Algorithms - YouTube",
            resolvedBrowserHost: "https://www.youtube.com/watch?v=123",
            settings: settings
        )

        XCTAssertNil(context.browserHost)
        XCTAssertNil(context.domainLabel)
        XCTAssertEqual(context.displayLabel, "Safari")
        XCTAssertEqual(context.effectiveWindowTitle, "Safari")
        XCTAssertEqual(context.category, .neutral)
    }

    func testFrontmostBrowserContextExposesFriendlyDomainWhenDomainCaptureEnabled() {
        let settings = AppSettings()
        settings.coachCollectRawDomains = true

        let context = AppUsageTracker.frontmostContextPresentation(
            bundleIdentifier: "com.apple.Safari",
            appName: "Safari",
            windowTitle: "Sorting Algorithms - YouTube",
            resolvedBrowserHost: "https://www.youtube.com/watch?v=123",
            settings: settings
        )

        XCTAssertEqual(context.browserHost, "youtube.com")
        XCTAssertEqual(context.domainLabel, "YouTube")
        XCTAssertEqual(context.displayLabel, "YouTube")
        XCTAssertEqual(context.effectiveWindowTitle, "Sorting Algorithms - YouTube")
        XCTAssertEqual(context.category, .distracting)
    }

    func testFrontmostBrowserContextDefaultsToAppLabelWithoutSettings() {
        let context = AppUsageTracker.frontmostContextPresentation(
            bundleIdentifier: "com.apple.Safari",
            appName: "Safari",
            windowTitle: "YouTube",
            resolvedBrowserHost: "youtube.com",
            settings: nil
        )

        XCTAssertNil(context.browserHost)
        XCTAssertNil(context.domainLabel)
        XCTAssertEqual(context.displayLabel, "Safari")
        XCTAssertEqual(context.effectiveWindowTitle, "Safari")
        XCTAssertEqual(context.category, .neutral)
    }

    func testHydratedFocusTotalsExcludePersistedDomainRowsFromTotalButUseThemForDistractingFocus() {
        let entries = [
            AppUsageEntry(
                date: Date(),
                appName: "Safari",
                bundleIdentifier: "com.apple.Safari",
                duringFocusSeconds: 1200,
                outsideFocusSeconds: 0
            ),
            AppUsageEntry(
                date: Date(),
                appName: "YouTube",
                bundleIdentifier: "domain:youtube.com",
                duringFocusSeconds: 900,
                outsideFocusSeconds: 0
            ),
            AppUsageEntry(
                date: Date(),
                appName: "Reddit",
                bundleIdentifier: "com.reddit.Reddit",
                duringFocusSeconds: 300,
                outsideFocusSeconds: 0
            )
        ]

        let totals = AppUsageTracker.focusTotals(for: entries)
        XCTAssertEqual(totals.totalFocusSeconds, 1500)
        XCTAssertEqual(totals.distractingFocusSeconds, 1200)
    }
}
