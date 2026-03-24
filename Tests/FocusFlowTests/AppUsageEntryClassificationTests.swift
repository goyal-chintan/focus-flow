import XCTest
@testable import FocusFlow

final class AppUsageEntryClassificationTests: XCTestCase {

    func testClassifiesXcodeAsProductive() {
        let category = AppUsageEntry.classify(
            bundleIdentifier: "com.apple.dt.Xcode",
            appName: "Xcode"
        )
        XCTAssertEqual(category, .productive)
    }

    func testClassifiesSocialAppsAsDistracting() {
        let category = AppUsageEntry.classify(
            bundleIdentifier: "com.apple.Safari",
            appName: "YouTube"
        )
        XCTAssertEqual(category, .distracting)
    }

    func testRecommendedBlockTargetMapsDistractingDomain() {
        let target = AppUsageEntry.recommendedBlockTarget(
            bundleIdentifier: "company.thebrowser",
            appName: "YouTube - Watch"
        )
        XCTAssertEqual(target, "youtube.com")
    }

    func testRecommendedBlockTargetReturnsNilForUnknownApp() {
        let target = AppUsageEntry.recommendedBlockTarget(
            bundleIdentifier: "com.apple.finder",
            appName: "Finder"
        )
        XCTAssertNil(target)
    }
}
