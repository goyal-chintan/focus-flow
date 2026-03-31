import XCTest
@testable import FocusFlow

final class FocusCoachGuardianAdvisorTests: XCTestCase {
    private let advisor = FocusCoachGuardianAdvisor()

    func testRecommendationUsesFrontmostDistractingTarget() {
        let entries = [
            AppUsageEntry(
                date: Date(),
                appName: "YouTube",
                bundleIdentifier: "com.apple.Safari",
                duringFocusSeconds: 600,
                outsideFocusSeconds: 900
            )
        ]
        let project = Project(name: "Interview Prep")

        let recommendation = advisor.recommendation(
            frontmostBundleId: "com.apple.Safari",
            frontmostAppName: "YouTube",
            entries: entries,
            selectedProject: project
        )

        XCTAssertEqual(recommendation?.target, "youtube.com")
        XCTAssertNotNil(recommendation?.reason)
    }

    func testRecommendationSkipsAlreadyBlockedTarget() {
        let entries = [
            AppUsageEntry(
                date: Date(),
                appName: "Reddit",
                bundleIdentifier: "com.apple.Safari",
                duringFocusSeconds: 300,
                outsideFocusSeconds: 1800
            )
        ]
        let project = Project(name: "Deep Work")
        project.blockProfile = BlockProfile(name: "Guard", websites: ["reddit.com"])

        let recommendation = advisor.recommendation(
            frontmostBundleId: "com.apple.Safari",
            frontmostAppName: "Reddit",
            entries: entries,
            selectedProject: project
        )

        XCTAssertNil(recommendation)
    }

    func testRecommendationSkipsTargetBlockedInAnyAssignedProfile() {
        let entries = [
            AppUsageEntry(
                date: Date(),
                appName: "YouTube",
                bundleIdentifier: "com.apple.Safari",
                duringFocusSeconds: 120,
                outsideFocusSeconds: 600
            )
        ]
        let project = Project(name: "Interview Prep")
        project.blockProfiles = [
            BlockProfile(name: "Social", websites: ["reddit.com"]),
            BlockProfile(name: "Video", websites: ["youtube.com"])
        ]

        let recommendation = advisor.recommendation(
            frontmostBundleId: "com.apple.Safari",
            frontmostAppName: "YouTube",
            entries: entries,
            selectedProject: project
        )

        XCTAssertNil(recommendation)
    }

    func testReleaseDurationDoneForTodayIsLonger() {
        let duration = advisor.releaseDuration(for: .doneForToday)
        XCTAssertEqual(duration, 90 * 60)
    }

    func testOutsideSessionChallengeStateRequiresConfidenceOrRepeatedPattern() {
        let state = advisor.guardianState(
            isInActiveSession: false,
            inReleaseWindow: false,
            driftConfidence: 0.72,
            hasRecommendation: false,
            hasRepeatedProjectPattern: false,
            engagementMode: .adaptive
        )
        XCTAssertEqual(state, .watchful)
    }

    func testOutsideSessionRepeatedPatternPromotesChallenge() {
        let state = advisor.guardianState(
            isInActiveSession: false,
            inReleaseWindow: false,
            driftConfidence: 0.72,
            hasRecommendation: false,
            hasRepeatedProjectPattern: true,
            engagementMode: .adaptive
        )
        XCTAssertEqual(state, .challenge)
    }

    func testRecommendationReasonUsesFriendlyLabelForAppContextTarget() {
        let entries = [
            AppUsageEntry(
                date: Date(),
                appName: "ChatGPT",
                bundleIdentifier: "com.openai.chatgpt",
                duringFocusSeconds: 0,
                outsideFocusSeconds: 600
            )
        ]
        let project = Project(name: "Write RFC")

        let recommendation = advisor.recommendation(
            frontmostBundleId: "com.openai.chatgpt",
            frontmostAppName: "ChatGPT",
            entries: entries,
            selectedProject: project
        )

        XCTAssertEqual(recommendation?.target, "app:com.openai.chatgpt")
        XCTAssertFalse(recommendation?.reason.contains("app:") ?? true)
        XCTAssertFalse(recommendation?.reason.contains("com.openai.chatgpt") ?? true)
        XCTAssertTrue(recommendation?.reason.contains("ChatGPT") ?? false)
    }

    func testRecommendationFallsBackToNonWebAppContextFromEntries() {
        let entries = [
            AppUsageEntry(
                date: Date(),
                appName: "ChatGPT",
                bundleIdentifier: "com.openai.chatgpt",
                duringFocusSeconds: 0,
                outsideFocusSeconds: 1800
            )
        ]
        let project = Project(name: "Deep Work")

        let recommendation = advisor.recommendation(
            frontmostBundleId: nil,
            frontmostAppName: nil,
            entries: entries,
            selectedProject: project
        )

        XCTAssertEqual(recommendation?.target, "app:com.openai.chatgpt")
    }

    func testRecommendationSkipsBrowserEntryFallbackWithoutDomainKey() {
        let entries = [
            AppUsageEntry(
                date: Date(),
                appName: "YouTube",
                bundleIdentifier: "com.apple.Safari",
                duringFocusSeconds: 0,
                outsideFocusSeconds: 1800
            )
        ]
        let project = Project(name: "Office Work")

        let recommendation = advisor.recommendation(
            frontmostBundleId: "company.thebrowser.browser",
            frontmostAppName: "Arc",
            entries: entries,
            selectedProject: project
        )

        XCTAssertNil(recommendation)
    }

    func testRecommendationAllowsBrowserFallbackForDomainKeyedEntry() {
        let entries = [
            AppUsageEntry(
                date: Date(),
                appName: "YouTube",
                bundleIdentifier: "domain:youtube.com",
                duringFocusSeconds: 0,
                outsideFocusSeconds: 1800
            )
        ]
        let project = Project(name: "Office Work")

        let recommendation = advisor.recommendation(
            frontmostBundleId: "company.thebrowser.browser",
            frontmostAppName: "Arc",
            entries: entries,
            selectedProject: project
        )

        XCTAssertEqual(recommendation?.target, "youtube.com")
    }

    func testRecommendationSkipsRawBundleIdentifierTargetLeak() {
        let entries = [
            AppUsageEntry(
                date: Date(),
                appName: "Arc",
                bundleIdentifier: "company.thebrowser.browser",
                duringFocusSeconds: 0,
                outsideFocusSeconds: 3600
            )
        ]
        let project = Project(name: "Searching")

        let recommendation = advisor.recommendation(
            frontmostBundleId: nil,
            frontmostAppName: nil,
            entries: entries,
            selectedProject: project
        )

        XCTAssertNil(recommendation)
    }

    func testRecommendationSkipsBrowserDomainKeyThatContainsBundleIdentifier() {
        let entries = [
            AppUsageEntry(
                date: Date(),
                appName: "Arc",
                bundleIdentifier: "domain:company.thebrowser.browser",
                duringFocusSeconds: 0,
                outsideFocusSeconds: 2400
            )
        ]
        let project = Project(name: "Searching")

        let recommendation = advisor.recommendation(
            frontmostBundleId: "company.thebrowser.browser",
            frontmostAppName: "Arc",
            entries: entries,
            selectedProject: project
        )

        XCTAssertNil(recommendation)
    }
}
