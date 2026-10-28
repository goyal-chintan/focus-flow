import Foundation

// Coach v5 learning engine (docs/plans/2026-10-28-coach-v5-learning-engine-design.md §3).
// Learner A decides whether a prompt now would *cause* a start (action-centred Thompson sampling,
// as in HeartSteps). Learner B picks the block size to ask for. Rules are priors; data overrides.

// MARK: - Reward (§3.1)

/// Reward of a decision, read from the sessions table once 60 minutes have passed:
/// 1 for a start within 10 minutes, plus up to 0.5 for focused minutes in the next hour.
enum CoachDecisionReward {
    static let startWindow: TimeInterval = 10 * 60
    static let momentumWindow: TimeInterval = 60 * 60
    static let momentumCapMinutes = 50.0
    static let momentumWeight = 0.5

    struct Block: Sendable, Equatable {
        let start: Date
        let seconds: TimeInterval
        /// The length the block was started at (credits the size learner).
        var plannedMinutes: Int = 25
    }

    /// Nil while the hour is still running.
    static func reward(decidedAt t: Date, now: Date, blocks: [Block]) -> Double? {
        guard now.timeIntervalSince(t) >= momentumWindow else { return nil }
        return outcome(decidedAt: t, blocks: blocks).reward
    }

    static func outcome(decidedAt t: Date, blocks: [Block]) -> (started: Bool, startedBlock: Block?, reward: Double) {
        // A start clicked on the prompt lands a moment after the decision; allow 5 s of clock slack.
        let window = blocks.filter { $0.start >= t.addingTimeInterval(-5) && $0.start <= t.addingTimeInterval(momentumWindow) }
        let first = window.filter { $0.start <= t.addingTimeInterval(startWindow) }.min { $0.start < $1.start }
        let end = t.addingTimeInterval(momentumWindow)
        let minutes = window.reduce(0.0) { sum, block in
            sum + max(0, min(block.seconds, end.timeIntervalSince(block.start))) / 60
        }
        let started = first != nil
        let reward = (started ? 1 : 0) + momentumWeight * min(minutes, momentumCapMinutes) / momentumCapMinutes
        return (started, first, reward)
    }
}

// MARK: - Learner A: prompt now? (§3.2)

/// The context of a decision point, as numbers.
struct CoachPromptFeatures: Sendable, Equatable {
    enum Front: Sendable, Equatable { case work, neutral, derailer }

    var availabilityLift: Double
    var arrival: Bool
    var hoursSinceLastBlock: Double?
    var hasBlockToday: Bool
    var promptsSeen24h: Int
    var lateNight: Bool
    var front: Front
    var tiredRecently: Bool
    var missedYesterday: Bool
    var weekend: Bool

    static let names = [
        "Baseline", "Your good hours", "Coming back to the desk", "Long gap since a block",
        "Already started today", "Prompts already today", "Late night", "Distraction in front",
        "Work app in front", "Said you were tired", "Missed yesterday", "Weekend",
    ]
    static var count: Int { names.count }

    var vector: [Double] {
        [
            1,
            max(-1, min(3, availabilityLift - 1)) / 3,
            arrival ? 1 : 0,
            min(hoursSinceLastBlock ?? 24, 24) / 24,
            hasBlockToday ? 1 : 0,
            Double(min(promptsSeen24h, 6)) / 6,
            lateNight ? 1 : 0,
            front == .derailer ? 1 : 0,
            front == .work ? 1 : 0,
            tiredRecently ? 1 : 0,
            missedYesterday ? 1 : 0,
            weekend ? 1 : 0,
        ]
    }

    static func encode(_ vector: [Double]) -> String {
        vector.map { String(format: "%.4f", $0) }.joined(separator: ",")
    }

    static func decode(_ raw: String?) -> [Double]? {
        guard let raw else { return nil }
        let values = raw.split(separator: ",").compactMap { Double($0) }
        return values.count == count ? values : nil
    }
}

enum CoachPromptPolicy {
    /// `InterventionAttempt.decisionRaw` for a Learner A decision point.
    static let decisionKey = "prompt"
    static let minProbability = 0.05
    static let maxProbability = 0.80
    /// A prompt must raise the start chance by about 5 points to be worth the interruption.
    static let cost = 0.05
    /// Prior sd per weight. The average effect of a prompt is small in the mHealth trials, so the
    /// baseline is held near 0 (sd 0.03). Habituation, late night and fatigue have direct evidence,
    /// so they are held tighter (0.05). Everything else may move freely (0.1). A vague prior means
    /// more exploration there, so a weight we believe in must not be vague.
    static let priorSD: [Double] = [0.03, 0.1, 0.1, 0.1, 0.1, 0.05, 0.05, 0.1, 0.1, 0.05, 0.1, 0.1]
    static let noiseSD = 0.5

    /// Science-based prior on the prompt *effect* (start-probability units), in `CoachPromptFeatures` order:
    /// receptive hours and breakpoints help (Mishra et al., 2021; Iqbal & Bailey, 2008); repeated prompts
    /// and fatigue hurt (habituation); late night hurts.
    static let priorMean: [Double] = [0, 0.05, 0.05, 0, 0, -0.05, -0.03, 0, 0, -0.05, 0, 0]

    struct Observation: Sendable, Equatable {
        let x: [Double]
        let treated: Bool
        let propensity: Double
        let reward: Double
    }

    /// Action-centred fit (Greenewald et al., 2017): with r = g(x) + a·xᵀθ + ε, regress r on
    /// z = (a − π)·x. Because E[a − π | x] = 0, the baseline g(x) (starts that would happen anyway,
    /// however non-linear) is uncorrelated with z and drops out: only the prompt's effect θ is learned.
    ///
    /// Variance reduction: a linear baseline ĝ(x) is fitted first and subtracted from r. Any function
    /// of x is still uncorrelated with z, so this keeps the estimate unbiased; it removes the noise of
    /// "would have started anyway", which otherwise swamps the prompt's effect for weeks.
    static func model(from observations: [Observation]) -> BayesianLinearModel {
        let usable = observations.filter { $0.x.count == CoachPromptFeatures.count && $0.propensity > 0 && $0.propensity < 1 }
        var baseline = BayesianLinearModel(priorMean: [Double](repeating: 0, count: CoachPromptFeatures.count), priorSD: 1, noiseSD: noiseSD)
        for o in usable { baseline.update(x: o.x, y: o.reward) }
        let beta = baseline.mean

        var model = BayesianLinearModel(priorMean: priorMean, priorSD: priorSD, noiseSD: noiseSD)
        for o in usable {
            let centred = (o.treated ? 1 : 0) - o.propensity
            let residual = o.reward - zip(o.x, beta).reduce(0) { $0 + $1.0 * $1.1 }
            model.update(x: o.x.map { $0 * centred }, y: residual)
        }
        return model
    }

    /// P(effect > cost) under the posterior, clipped so the coach keeps learning.
    static func probability(x: [Double], model: BayesianLinearModel) -> Double {
        let (mean, variance) = model.predict(x)
        let sd = max(variance.squareRoot(), 1e-6)
        let p = CoachMath.normalCDF((mean - cost) / sd)
        return min(maxProbability, max(minProbability, p))
    }

    static func decide<G: RandomNumberGenerator>(x: [Double], model: BayesianLinearModel, using rng: inout G) -> (prompt: Bool, probability: Double) {
        let p = probability(x: x, model: model)
        return (Double.random(in: 0..<1, using: &rng) < p, p)
    }

    /// The largest learned weights (away from zero), with names, for Insights.
    static func strongestEffects(_ model: BayesianLinearModel, limit: Int = 3) -> [(name: String, weight: Double)] {
        zip(CoachPromptFeatures.names, model.mean).dropFirst()
            .map { (name: $0.0, weight: $0.1) }
            .filter { abs($0.weight) >= 0.01 }
            .sorted { abs($0.weight) > abs($1.weight) }
            .prefix(limit)
            .map { $0 }
    }
}

// MARK: - Learner B: what size? (§3.3)

enum CoachSizePolicy {
    static let arms = CoachBlockSizeLadder.sizes
    /// With no data the rule's size wins about 85% of draws; ~10 asks at a size move it.
    static let priorSD = 0.1
    static let noiseSD = 0.5
    static let ruleBonus = 0.25
    static let featureNames = ["Baseline", "Rule says 5", "Rule says 15", "Rule says 25", "Late night", "Already started today"]

    static func encode(_ vector: [Double]) -> String { CoachPromptFeatures.encode(vector) }

    static func decode(_ raw: String?) -> [Double]? {
        guard let raw else { return nil }
        let values = raw.split(separator: ",").compactMap { Double($0) }
        return values.count == featureNames.count ? values : nil
    }

    struct Context: Sendable, Equatable {
        var ruleMinutes: Int
        var lateNight: Bool
        var hasBlockToday: Bool

        var vector: [Double] {
            [
                1,
                ruleMinutes == 5 ? 1 : 0,
                ruleMinutes == 15 ? 1 : 0,
                ruleMinutes == 25 ? 1 : 0,
                lateNight ? 1 : 0,
                hasBlockToday ? 1 : 0,
            ]
        }
    }

    struct Observation: Sendable, Equatable {
        let x: [Double]
        let arm: Int
        let reward: Double
    }

    /// The v4 rule as the prior: each arm gets +0.25 when the rule picks it; late night tilts small.
    static func prior(for arm: Int) -> [Double] {
        var mean = [0.5, 0, 0, 0, 0, 0]
        if let index = arms.firstIndex(of: arm) { mean[1 + index] = ruleBonus }
        if arm == arms.first { mean[4] = 0.05 }
        if arm == arms.last { mean[4] = -0.05 }
        return mean
    }

    static func models(from observations: [Observation]) -> [Int: BayesianLinearModel] {
        var models = Dictionary(uniqueKeysWithValues: arms.map {
            ($0, BayesianLinearModel(priorMean: prior(for: $0), priorSD: priorSD, noiseSD: noiseSD))
        })
        for o in observations where o.x.count == featureNames.count {
            models[CoachBlockSizeLadder.nearestSize(o.arm)]?.update(x: o.x, y: o.reward)
        }
        return models
    }

    /// Thompson sampling: the arm with the highest sampled value.
    static func choose<G: RandomNumberGenerator>(context: Context, models: [Int: BayesianLinearModel], using rng: inout G) -> Int {
        let x = context.vector
        return arms.max { lhs, rhs in
            sampledValue(models[lhs], x, &rng) < sampledValue(models[rhs], x, &rng)
        } ?? context.ruleMinutes
    }

    /// Greedy pick by posterior mean (for display, so the suggestion doesn't flicker).
    static func best(context: Context, models: [Int: BayesianLinearModel]) -> Int {
        let x = context.vector
        return arms.max { (models[$0]?.predict(x).mean ?? 0) < (models[$1]?.predict(x).mean ?? 0) } ?? context.ruleMinutes
    }

    private static func sampledValue<G: RandomNumberGenerator>(_ model: BayesianLinearModel?, _ x: [Double], _ rng: inout G) -> Double {
        guard let model else { return -.infinity }
        return zip(model.sample(using: &rng), x).reduce(0) { $0 + $1.0 * $1.1 }
    }
}

// MARK: - Measured lift (§3.5)

/// Inverse-propensity estimate of how much a prompt changes the chance of starting within 10 min.
/// Unbiased because each decision was randomised with a known probability.
enum CoachLiftEstimate {
    static let minimumDecisions = 20
    static let minimumPerArm = 5

    struct Decision: Sendable, Equatable {
        let treated: Bool
        let propensity: Double
        let started: Bool
    }

    struct Result: Sendable, Equatable {
        let withPrompt: Double
        let withoutPrompt: Double
        let decisions: Int
        var lift: Double { withPrompt - withoutPrompt }
    }

    static func estimate(_ decisions: [Decision]) -> Result? {
        let usable = decisions.filter { $0.propensity > 0 && $0.propensity < 1 }
        let treated = usable.filter(\.treated).count
        guard usable.count >= minimumDecisions, treated >= minimumPerArm, usable.count - treated >= minimumPerArm else { return nil }
        // Self-normalised (Hájek) weights: stable with few decisions.
        var tNum = 0.0, tDen = 0.0, cNum = 0.0, cDen = 0.0
        for d in usable {
            if d.treated {
                tNum += (d.started ? 1 : 0) / d.propensity
                tDen += 1 / d.propensity
            } else {
                cNum += (d.started ? 1 : 0) / (1 - d.propensity)
                cDen += 1 / (1 - d.propensity)
            }
        }
        return Result(withPrompt: tNum / tDen, withoutPrompt: cNum / cDen, decisions: usable.count)
    }
}
