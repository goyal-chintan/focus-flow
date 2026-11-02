import XCTest
@testable import FocusFlow

/// Coach audit fixes (2026-10-30): prompt at a fixed rate until there is data, learn from own work,
/// never shrink the ask while you finish full blocks, and show the distance to today's goal.
final class CoachAuditFixTests: XCTestCase {
    func testWarmUpPromptsAtAFixedRateUntilEnoughDecisions() {
        let model = CoachPromptPolicy.model(from: [])
        let x = [Double](repeating: 0, count: CoachPromptFeatures.count)
        var rng = SystemRandomNumberGenerator()
        XCTAssertEqual(CoachPromptPolicy.decide(x: x, model: model, resolvedDecisions: 3, using: &rng).probability, 0.7)
        let learned = CoachPromptPolicy.decide(x: x, model: model, resolvedDecisions: 40, using: &rng).probability
        XCTAssertEqual(learned, CoachPromptPolicy.probability(x: x, model: model), "From 40 decisions the model decides")
    }

    @MainActor func testStartWindowIsTwentyMinutes() {
        XCTAssertEqual(CoachDecisionReward.startWindow, 20 * 60)
        XCTAssertEqual(CoachRewardLedger.startWindow, 20 * 60)
    }

    func testFinishingFullBlocksCancelsEarlierUnansweredAsks() {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let events: [CoachBlockSizeLadder.Event] = [
            .init(at: t0, kind: .declined(reason: nil)),
            .init(at: t0.addingTimeInterval(600), kind: .blockEnded(minutes: 15, completed: true)),
            .init(at: t0.addingTimeInterval(1200), kind: .declined(reason: nil)),
        ]
        XCTAssertEqual(CoachBlockSizeLadder.recommend(events: events).minutes, 15, "One unanswered ask after a finished 15 doesn't shrink it")
        XCTAssertFalse(CoachBlockSizeLadder.Recommendation(minutes: 5, why: .shrunkAfterDeclines).caption.contains("didn't land"))
    }

    func testGoalGradientLineOnlyOnceYouAreOnTheWay() {
        func input(done: Int, goal: Int, minutes: Int = 25) -> CoachComposerInput {
            var facts = CoachFacts()
            facts.doneMinutesToday = done
            facts.goalMinutes = goal
            facts.sessionsToday = done > 0 ? 2 : 0
            return CoachComposerInput(style: .challenger, trigger: .startNudge, facts: facts, target: CoachStartTarget(minutes: minutes))
        }
        XCTAssertNil(CoachMessageComposer.gradientHook(input(done: 20, goal: 150)), "Far off: never the ask")
        XCTAssertEqual(CoachMessageComposer.gradientHook(input(done: 70, goal: 150)), "70 of 150 min today. This 25 puts you at 95.")
        XCTAssertEqual(CoachMessageComposer.gradientHook(input(done: 130, goal: 150)), "130 of 150 min today. This 25 closes today's goal.")
        XCTAssertNil(CoachMessageComposer.gradientHook(input(done: 150, goal: 150)))
    }
}
