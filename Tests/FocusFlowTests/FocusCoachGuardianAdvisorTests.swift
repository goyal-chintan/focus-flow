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
}
