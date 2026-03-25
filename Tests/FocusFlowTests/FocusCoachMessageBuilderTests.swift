import XCTest
@testable import FocusFlow

final class FocusCoachMessageBuilderTests: XCTestCase {
    func testBlockRecommendationHeadlineUsesFriendlyAppLabel() {
        let context = FocusCoachContext(
            idleSeconds: 0,
            frontmostAppName: nil,
            frontmostBundleIdentifier: nil,
            frontmostAppCategory: .neutral,
            isInActiveSession: false,
            todayFocusSeconds: 0,
            dailyGoalSeconds: 7200,
            todaySessionCount: 0,
            selectedProjectName: "Write Spec",
            selectedWorkMode: .deepWork,
            hourOfDay: 11,
            topDistractingAppName: nil,
            topDistractingAppMinutes: 0,
            recentLowPriorityWorkCount: 0,
            suggestedBlockTarget: "app:com.openai.chatgpt",
            blockRecommendationReason: "com.openai.chatgpt has been a repeated distraction (10m today).",
            inReleaseWindow: false
        )

        let message = FocusCoachMessageBuilder.build(context: context, sessionSeed: 0)

        XCTAssertFalse(message.headline.contains("app:"))
        XCTAssertFalse(message.bannerLabel?.contains("app:") ?? true)
        XCTAssertTrue(message.headline.contains("com.openai.chatgpt"))
    }
}
