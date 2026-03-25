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

    func testClassifiesGhosttyAsProductive() {
        let category = AppUsageEntry.classify(
            bundleIdentifier: "com.mitchellh.ghostty",
            appName: "Ghostty"
        )
        XCTAssertEqual(category, .productive)
    }

    func testClassifyForContextTreatsGhosttyAsNeutralDuringFocus() {
        let entry = AppUsageEntry(
            appName: "Ghostty",
            bundleIdentifier: "com.mitchellh.ghostty"
        )
        let category = entry.classifyForContext(isInFocusSession: true, projectWorkMode: .deepWork)
        XCTAssertEqual(category, .neutral)
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

    func testRecommendedBlockTargetFallsBackToBundleForDerailerCandidate() {
        let target = AppUsageEntry.recommendedBlockTarget(
            bundleIdentifier: "com.openai.chatgpt",
            appName: "ChatGPT"
        )
        XCTAssertEqual(target, "app:com.openai.chatgpt")
    }

    func testRecommendedBlockTargetDoesNotFallbackToBrowserAppTarget() {
        let target = AppUsageEntry.recommendedBlockTarget(
            bundleIdentifier: "com.apple.Safari",
            appName: "ChatGPT"
        )
        XCTAssertNil(target)
    }

    func testRecommendationDisplayLabelStripsAppPrefix() {
        let label = AppUsageEntry.recommendationDisplayLabel(for: "app:com.mitchellh.ghostty")
        XCTAssertEqual(label, "Ghostty")
    }

    func testRecommendationDisplayLabelMapsKnownBundleIdsToFriendlyNames() {
        XCTAssertEqual(
            AppUsageEntry.recommendationDisplayLabel(for: "app:com.anthropic.claudefordesktop"),
            "Claude"
        )
        XCTAssertEqual(
            AppUsageEntry.recommendationDisplayLabel(for: "app:com.tinyspeck.slackmacgap"),
            "Slack"
        )
        XCTAssertEqual(
            AppUsageEntry.recommendationDisplayLabel(for: "app:com.openai.codex"),
            "Codex"
        )
    }

    func testRecommendationDisplayLabelFallsBackToReadableToken() {
        let label = AppUsageEntry.recommendationDisplayLabel(for: "app:com.example.super-cool_app")
        XCTAssertEqual(label, "Super Cool App")
    }

    func testRecommendationDisplayLabelKeepsDomainUntouched() {
        let label = AppUsageEntry.recommendationDisplayLabel(for: "youtube.com")
        XCTAssertEqual(label, "youtube.com")
    }
}
