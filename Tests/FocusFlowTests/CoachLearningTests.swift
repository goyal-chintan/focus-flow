import XCTest
@testable import FocusFlow

/// Coach v5 learning engine: the maths, and simulated users the learners must figure out.
final class CoachLearningTests: XCTestCase {

    // MARK: Bayesian linear regression

    func testPosteriorMatchesTheClosedForm() {
        // Prior N(0, 1), noise sd 1, n observations of y = 2 at x = 1 → mean 2n / (n + 1), var 1 / (n + 1).
        var model = BayesianLinearModel(priorMean: [0], priorSD: 1, noiseSD: 1)
        for _ in 0..<4 { model.update(x: [1], y: 2) }
        XCTAssertEqual(model.mean[0], 8.0 / 5, accuracy: 1e-9)
        XCTAssertEqual(model.covariance[0], 1.0 / 5, accuracy: 1e-9)
        XCTAssertEqual(model.count, 4)
    }

    func testTwoDimensionalRegressionRecoversTheWeights() {
        var model = BayesianLinearModel(priorMean: [0, 0], priorSD: 10, noiseSD: 0.1)
        var rng = SplitMix64(seed: 1)
        for _ in 0..<400 {
            let a = Double.random(in: -1...1, using: &rng), b = Double.random(in: -1...1, using: &rng)
            model.update(x: [a, b], y: 0.7 * a - 0.3 * b + 0.1 * BetaSampler.normal(using: &rng))
        }
        XCTAssertEqual(model.mean[0], 0.7, accuracy: 0.03)
        XCTAssertEqual(model.mean[1], -0.3, accuracy: 0.03)
    }

    func testSamplesAreCentredOnThePosterior() {
        var model = BayesianLinearModel(priorMean: [0.2, -0.1], priorSD: 0.5, noiseSD: 1)
        model.update(x: [1, 1], y: 1)
        var rng = SplitMix64(seed: 7)
        let draws = (0..<4000).map { _ in model.sample(using: &rng) }
        let mean = model.mean
        XCTAssertEqual(draws.map { $0[0] }.reduce(0, +) / 4000, mean[0], accuracy: 0.03)
        XCTAssertEqual(draws.map { $0[1] }.reduce(0, +) / 4000, mean[1], accuracy: 0.03)
    }

    // MARK: Reward

    func testRewardCountsTheStartAndTheMomentum() {
        let t = Date(timeIntervalSince1970: 1_800_000_000)
        let blocks = [
            CoachDecisionReward.Block(start: t.addingTimeInterval(120), seconds: 25 * 60),
            CoachDecisionReward.Block(start: t.addingTimeInterval(30 * 60), seconds: 60 * 60),
        ]
        XCTAssertNil(CoachDecisionReward.reward(decidedAt: t, now: t.addingTimeInterval(59 * 60), blocks: blocks), "Wait for the hour")
        // 25 min + 30 min (clipped at the hour) = 55 → capped at 50 → 1 + 0.5.
        XCTAssertEqual(CoachDecisionReward.reward(decidedAt: t, now: t.addingTimeInterval(3600), blocks: blocks)!, 1.5, accuracy: 1e-9)
        // A start after the 20-minute window is momentum only, not a start.
        let late = [CoachDecisionReward.Block(start: t.addingTimeInterval(35 * 60), seconds: 25 * 60)]
        XCTAssertEqual(CoachDecisionReward.reward(decidedAt: t, now: t.addingTimeInterval(7200), blocks: late)!, 0.25, accuracy: 1e-9)
        XCTAssertEqual(CoachDecisionReward.reward(decidedAt: t, now: t.addingTimeInterval(7200), blocks: [])!, 0)
    }

    // MARK: Learner A on a simulated user

    /// A user who always starts at their usual hour (prompt or not) and who only responds to prompts
    /// when they just came back to the desk. A correlational learner would credit prompts in the usual
    /// hour; the action-centred learner must not.
    func testPromptLearnerFindsTheRealEffectAndIgnoresStartsThatHappenAnyway() {
        var rng = SplitMix64(seed: 42)
        var observations: [CoachPromptPolicy.Observation] = []
        func features(usualHour: Bool, arrival: Bool) -> [Double] {
            CoachPromptFeatures(
                availabilityLift: usualHour ? 4 : 1, arrival: arrival, hoursSinceLastBlock: 0, hasBlockToday: false,
                promptsSeen24h: 0, lateNight: false, front: .neutral, tiredRecently: false, missedYesterday: false, weekend: false
            ).vector
        }
        for i in 0..<800 {
            let usualHour = i % 2 == 0
            let arrival = i % 3 == 0
            let x = features(usualHour: usualHour, arrival: arrival)
            let model = CoachPromptPolicy.model(from: observations)
            let (prompt, p) = CoachPromptPolicy.decide(x: x, model: model, using: &rng)
            let baseline = usualHour ? 0.6 : 0.05
            let effect = prompt && arrival ? 0.35 : 0
            let started = Double.random(in: 0..<1, using: &rng) < baseline + effect
            observations.append(.init(x: x, treated: prompt, propensity: p, reward: started ? 1 : 0))
        }
        let model = CoachPromptPolicy.model(from: observations)
        let weights = model.mean
        XCTAssertGreaterThan(weights[2], 0.15, "Arrival is where prompts work")
        XCTAssertLessThan(abs(weights[1]), 0.1, "The usual hour has starts, but prompts don't cause them")
        let arrivalP = CoachPromptPolicy.probability(x: features(usualHour: false, arrival: true), model: model)
        let usualP = CoachPromptPolicy.probability(x: features(usualHour: true, arrival: false), model: model)
        XCTAssertEqual(arrivalP, CoachPromptPolicy.maxProbability, accuracy: 0.01)
        XCTAssertLessThan(usualP, 0.45, "No effect: below even odds after ~800 decisions (still exploring)")
        XCTAssertLessThan(usualP, arrivalP - 0.3)
        XCTAssertGreaterThanOrEqual(usualP, CoachPromptPolicy.minProbability, "Never zero: keeps learning")
        XCTAssertEqual(CoachPromptPolicy.strongestEffects(model).first?.name, "Coming back to the desk")
    }

    func testPromptPriorFollowsTheScienceBeforeAnyData() {
        let model = CoachPromptPolicy.model(from: [])
        func p(_ build: (inout CoachPromptFeatures) -> Void) -> Double {
            var f = CoachPromptFeatures(
                availabilityLift: 1, arrival: false, hoursSinceLastBlock: 6, hasBlockToday: false, promptsSeen24h: 0,
                lateNight: false, front: .neutral, tiredRecently: false, missedYesterday: false, weekend: false
            )
            build(&f)
            return CoachPromptPolicy.probability(x: f.vector, model: model)
        }
        let plain = p { _ in }
        XCTAssertGreaterThan(p { $0.arrival = true; $0.availabilityLift = 3 }, plain, "Receptive moment")
        XCTAssertLessThan(p { $0.promptsSeen24h = 6 }, plain, "Habituation")
        XCTAssertLessThan(p { $0.tiredRecently = true; $0.lateNight = true }, plain)
    }

    // MARK: Learner B on a simulated user

    func testSizeLearnerMovesToTheSizeThisUserActuallyStarts() {
        var rng = SplitMix64(seed: 9)
        let context = CoachSizePolicy.Context(ruleMinutes: 15, lateNight: false, hasBlockToday: false)
        XCTAssertEqual(CoachSizePolicy.best(context: context, models: CoachSizePolicy.models(from: [])), 15, "No data: the rule decides")
        var observations: [CoachSizePolicy.Observation] = []
        let startRate = [5: 0.7, 15: 0.1, 25: 0.05]
        for _ in 0..<80 {
            let models = CoachSizePolicy.models(from: observations)
            let arm = CoachSizePolicy.choose(context: context, models: models, using: &rng)
            let started = Double.random(in: 0..<1, using: &rng) < startRate[arm]!
            let reward = started ? 1 + 0.5 * Double(arm) / 50 : 0
            observations.append(.init(x: context.vector, arm: arm, reward: reward))
        }
        XCTAssertEqual(CoachSizePolicy.best(context: context, models: CoachSizePolicy.models(from: observations)), 5)
        let asks5 = observations.suffix(30).filter { $0.arm == 5 }.count
        XCTAssertGreaterThan(asks5, 20, "Thompson sampling mostly exploits once it knows")
    }

    // MARK: Lift

    func testLiftEstimateNeedsRandomisedDataAndRecoversTheEffect() {
        XCTAssertNil(CoachLiftEstimate.estimate([]))
        var rng = SplitMix64(seed: 3)
        let decisions: [CoachLiftEstimate.Decision] = (0..<2000).map { _ in
            let p = Double.random(in: 0.1...0.8, using: &rng)
            let treated = Double.random(in: 0..<1, using: &rng) < p
            let started = Double.random(in: 0..<1, using: &rng) < (treated ? 0.30 : 0.10)
            return .init(treated: treated, propensity: p, started: started)
        }
        let result = try! XCTUnwrap(CoachLiftEstimate.estimate(decisions))
        XCTAssertEqual(result.withPrompt, 0.30, accuracy: 0.04)
        XCTAssertEqual(result.withoutPrompt, 0.10, accuracy: 0.04)
    }

    func testFeatureEncodingRoundTrips() {
        let f = CoachPromptFeatures(
            availabilityLift: 2, arrival: true, hoursSinceLastBlock: nil, hasBlockToday: true, promptsSeen24h: 3,
            lateNight: false, front: .derailer, tiredRecently: false, missedYesterday: true, weekend: false
        ).vector
        let decoded = try! XCTUnwrap(CoachPromptFeatures.decode(CoachPromptFeatures.encode(f)))
        XCTAssertEqual(decoded.count, CoachPromptFeatures.count)
        for (a, b) in zip(decoded, f) { XCTAssertEqual(a, b, accuracy: 1e-4) }
        XCTAssertNil(CoachPromptFeatures.decode("1,2"))
    }
}
