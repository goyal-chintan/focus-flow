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

    func testRecommendationDisplayLabelUsesFriendlyDomainLabel() {
        let label = AppUsageEntry.recommendationDisplayLabel(for: "youtube.com")
        XCTAssertEqual(label, "YouTube")
    }

    func testNormalizedBrowserHostExtractsHostFromURL() {
        let host = AppUsageEntry.normalizedBrowserHost(from: "https://www.youtube.com/watch?v=123")
        XCTAssertEqual(host, "youtube.com")
    }

    func testNormalizedBrowserHostAcceptsUncommonValidTLDs() {
        XCTAssertEqual(
            AppUsageEntry.normalizedBrowserHost(from: "https://focusflow.cloud/dashboard"),
            "focusflow.cloud"
        )
        XCTAssertEqual(
            AppUsageEntry.normalizedBrowserHost(from: "store.example.shop"),
            "store.example.shop"
        )
        XCTAssertEqual(
            AppUsageEntry.normalizedBrowserHost(from: "planner.online"),
            "planner.online"
        )
    }

    func testNormalizedBrowserHostRejectsBundleIdentifierMasqueradingAsDomain() {
        let host = AppUsageEntry.normalizedBrowserHost(from: "company.thebrowser.browser")
        XCTAssertNil(host)
    }

    func testBrowserDomainDisplayLabelReturnsNilForInvalidHost() {
        let label = AppUsageEntry.browserDomainDisplayLabel(for: "com.apple.Safari")
        XCTAssertNil(label)
    }

    func testRecommendationDisplayLabelTreatsBundleIdentifierAsAppNotDomain() {
        let label = AppUsageEntry.recommendationDisplayLabel(for: "company.thebrowser.browser")
        XCTAssertEqual(label, "Arc")
    }

    func testRecommendationDisplayLabelTreatsArcBundleIdentifierVariantAsApp() {
        let label = AppUsageEntry.recommendationDisplayLabel(for: "company.thebrowser.Browser")
        XCTAssertEqual(label, "Arc")
    }

    // MARK: - Domain-prefix key handling (added by AppUsageTracker for browser tab contexts)

    func testRecommendedBlockTargetReturnsDomainForDomainPrefixKey() {
        // AppUsageTracker stores browser tab entries as bundleIdentifier="domain:<host>"
        let target = AppUsageEntry.recommendedBlockTarget(
            bundleIdentifier: "domain:youtube.com",
            appName: "YouTube"
        )
        XCTAssertEqual(target, "youtube.com")
    }

    func testRecommendedBlockTargetHandlesArbitraryDomainPrefix() {
        let target = AppUsageEntry.recommendedBlockTarget(
            bundleIdentifier: "domain:github.com",
            appName: "GitHub"
        )
        XCTAssertEqual(target, "github.com")
    }

    func testRecommendedBlockTargetReturnsDomainForNonMappedSocialSite() {
        let target = AppUsageEntry.recommendedBlockTarget(
            bundleIdentifier: "domain:linkedin.com",
            appName: "LinkedIn"
        )
        XCTAssertEqual(target, "linkedin.com")
    }

    func testRecommendedBlockTargetRejectsEmptyDomainPrefix() {
        let target = AppUsageEntry.recommendedBlockTarget(
            bundleIdentifier: "domain:",
            appName: ""
        )
        XCTAssertNil(target)
    }

    func testRecommendedBlockTargetRejectsDomainPrefixWithBundleIdentifier() {
        let target = AppUsageEntry.recommendedBlockTarget(
            bundleIdentifier: "domain:company.thebrowser.browser",
            appName: "Arc"
        )
        XCTAssertNil(target)
    }
}
