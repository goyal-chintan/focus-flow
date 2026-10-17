import XCTest
@testable import FocusFlow

final class AppDisplayNameResolverTests: XCTestCase {
    private var savedURLProvider: ((String) -> URL?)!
    private var savedNameProvider: ((URL) -> String)!

    override func setUp() {
        super.setUp()
        savedURLProvider = AppDisplayNameResolver.applicationURLProvider
        savedNameProvider = AppDisplayNameResolver.displayNameProvider
        AppDisplayNameResolver.resetCache()
    }

    override func tearDown() {
        AppDisplayNameResolver.applicationURLProvider = savedURLProvider
        AppDisplayNameResolver.displayNameProvider = savedNameProvider
        AppDisplayNameResolver.resetCache()
        super.tearDown()
    }

    func testResolvesInstalledAppNameAndStripsAppSuffix() {
        AppDisplayNameResolver.applicationURLProvider = { _ in URL(fileURLWithPath: "/Applications/Cursor.app") }
        AppDisplayNameResolver.displayNameProvider = { _ in "Cursor.app" }

        XCTAssertEqual(
            AppDisplayNameResolver.displayName(forBundleIdentifier: "com.todesktop.230313mzl4w4u92"),
            "Cursor"
        )
    }

    func testKeepsNameWithoutAppSuffixUnchanged() {
        AppDisplayNameResolver.applicationURLProvider = { _ in URL(fileURLWithPath: "/Applications/Slack.app") }
        AppDisplayNameResolver.displayNameProvider = { _ in "Slack" }

        XCTAssertEqual(AppDisplayNameResolver.displayName(forBundleIdentifier: "com.tinyspeck.slackmacgap"), "Slack")
    }

    func testReturnsNilWhenAppIsNotInstalled() {
        AppDisplayNameResolver.applicationURLProvider = { _ in nil }

        XCTAssertNil(AppDisplayNameResolver.displayName(forBundleIdentifier: "com.example.missing"))
    }

    func testReturnsNilForBlankDisplayName() {
        AppDisplayNameResolver.applicationURLProvider = { _ in URL(fileURLWithPath: "/Applications/.app") }
        AppDisplayNameResolver.displayNameProvider = { _ in "  .app" }

        XCTAssertNil(AppDisplayNameResolver.displayName(forBundleIdentifier: "com.example.blank"))
    }

    func testCachesResolvedNamePerBundleIdentifier() {
        var lookups = 0
        AppDisplayNameResolver.applicationURLProvider = { _ in
            lookups += 1
            return URL(fileURLWithPath: "/Applications/Cursor.app")
        }
        AppDisplayNameResolver.displayNameProvider = { _ in "Cursor.app" }

        _ = AppDisplayNameResolver.displayName(forBundleIdentifier: "com.todesktop.230313mzl4w4u92")
        _ = AppDisplayNameResolver.displayName(forBundleIdentifier: "com.todesktop.230313mzl4w4u92")

        XCTAssertEqual(lookups, 1)
    }

    func testCachesMissesSoUninstalledAppsAreNotRequeried() {
        var lookups = 0
        AppDisplayNameResolver.applicationURLProvider = { _ in
            lookups += 1
            return nil
        }

        XCTAssertNil(AppDisplayNameResolver.displayName(forBundleIdentifier: "com.example.missing"))
        XCTAssertNil(AppDisplayNameResolver.displayName(forBundleIdentifier: "com.example.missing"))

        XCTAssertEqual(lookups, 1)
    }

    func testRecommendationDisplayLabelUsesInstalledNameForCursor() {
        AppDisplayNameResolver.applicationURLProvider = { bundleIdentifier in
            bundleIdentifier == "com.todesktop.230313mzl4w4u92" ? URL(fileURLWithPath: "/Applications/Cursor.app") : nil
        }
        AppDisplayNameResolver.displayNameProvider = { _ in "Cursor.app" }

        XCTAssertEqual(
            AppUsageEntry.recommendationDisplayLabel(for: "app:com.todesktop.230313mzl4w4u92"),
            "Cursor"
        )
    }
}
