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
}
