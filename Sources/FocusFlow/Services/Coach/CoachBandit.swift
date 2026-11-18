import Foundation

// MARK: - Context

/// Bandit context bucket (Coach v2 design §3 [3]):
/// availability tier · idle length · frontmost class · sessions today.
struct CoachContextKey: Hashable, Sendable {
    enum Idle: String, Sendable, CaseIterable {
        case under10 = "0-10"
        case short = "10-30"
        case medium = "30-90"
        case long = "90+"

        init(idleSeconds: Int) {
            let minutes = idleSeconds / 60
            switch minutes {
            case ..<10: self = .under10
            case 10..<30: self = .short
            case 30..<90: self = .medium
            default: self = .long
            }
        }
    }

    enum Front: String, Sendable, CaseIterable {
        case work
        case neutral
        case derailer

        init(category: AppUsageEntry.AppCategory) {
            switch category {
            case .productive: self = .work
            case .neutral: self = .neutral
            case .distracting: self = .derailer
            }
        }
    }

    let availability: CoachAvailabilityModel.Tier
    let idle: Idle
    let front: Front
    let hasSessionToday: Bool
    /// Rescue loop only: the drift level the rescue was made at (`lvl:`).
    let driftLevel: DriftLevel?
    /// Rescue loop only: panel, pause screen or menu bar only (`surf:`).
    let rescueSurface: CoachRescueSurface?

    /// e.g. "avail:high|idle:30-90|front:work|today:0", plus "|lvl:2|surf:panel" for rescues.
    var rawValue: String {
        var key = "avail:\(availability.rawValue)|idle:\(idle.rawValue)|front:\(front.rawValue)|today:\(hasSessionToday ? "1+" : "0")"
        if let driftLevel { key += "|lvl:\(driftLevel.rawValue)" }
        if let rescueSurface { key += "|surf:\(rescueSurface.rawValue)" }
        return key
    }

    init(
        availability: CoachAvailabilityModel.Tier,
        idle: Idle,
        front: Front,
        hasSessionToday: Bool,
        driftLevel: DriftLevel? = nil,
        rescueSurface: CoachRescueSurface? = nil
    ) {
        self.availability = availability
        self.idle = idle
        self.front = front
        self.hasSessionToday = hasSessionToday
        self.driftLevel = driftLevel
        self.rescueSurface = rescueSurface
    }

    /// The same context for a rescue on `surface`.
    func rescue(level: DriftLevel, surface: CoachRescueSurface) -> CoachContextKey {
        CoachContextKey(
            availability: availability, idle: idle, front: front, hasSessionToday: hasSessionToday,
            driftLevel: level, rescueSurface: surface
        )
    }

    init?(rawValue: String) {
        var values: [String: String] = [:]
        for part in rawValue.split(separator: "|") {
            let pair = part.split(separator: ":", maxSplits: 1).map(String.init)
            guard pair.count == 2 else { return nil }
            values[pair[0]] = pair[1]
        }
        guard let availability = values["avail"].flatMap(CoachAvailabilityModel.Tier.init(rawValue:)),
              let idle = values["idle"].flatMap(Idle.init(rawValue:)),
              let front = values["front"].flatMap(Front.init(rawValue:)),
              let today = values["today"] else { return nil }
        self.init(
            availability: availability,
            idle: idle,
            front: front,
            hasSessionToday: today != "0",
            driftLevel: values["lvl"].flatMap(Int.init).flatMap(DriftLevel.init(rawValue:)),
            rescueSurface: values["surf"].flatMap(CoachRescueSurface.init(rawValue:))
        )
    }
}

// MARK: - Arms

/// A surface × style arm. `silent` has no style.
struct CoachArm: Hashable, Sendable, Codable {
    let surface: CoachSurface
    let style: CoachStyle?

    static let silent = CoachArm(surface: .silent, style: nil)

    var key: String {
        guard let style else { return surface.rawValue }
        return "\(surface.rawValue):\(style.rawValue)"
    }

    static func arms(for surfaces: [CoachSurface]) -> [CoachArm] {
        var arms: [CoachArm] = []
        for surface in surfaces {
            if surface == .silent {
                arms.append(.silent)
            } else {
                arms.append(contentsOf: CoachStyle.allCases.map { CoachArm(surface: surface, style: $0) })
            }
        }
        return arms
    }
}

// MARK: - Evidence

/// One resolved prompt, read back from an `InterventionAttempt` row.
struct CoachRewardRecord: Sendable, Equatable {
    let contextKey: String
    let arm: CoachArm
    let reward: Double

    init(contextKey: String, arm: CoachArm, reward: Double) {
        self.contextKey = contextKey
        self.arm = arm
        self.reward = reward
    }

    init?(attempt: InterventionAttempt) {
        // A panel nobody was there to see teaches nothing (v3 R3).
        guard attempt.outcome != .unseen,
              let contextKey = attempt.contextKey,
              // Planned cues are requested by the user; they say nothing about when to interrupt.
              !CoachPlannedCue.isPlannedContextKey(contextKey),
              let reward = attempt.reward,
              let surface = attempt.surfaceRawValue.flatMap(CoachSurface.init(rawValue:)),
              surface != .silent else { return nil }
        let style = attempt.styleRawValue.flatMap(CoachStyle.init(rawValue:))
        self.init(contextKey: contextKey, arm: CoachArm(surface: surface, style: style), reward: reward)
    }
}

/// Fractional Beta evidence for one arm.
struct CoachArmEvidence: Codable, Sendable, Equatable {
    var successes: Double = 0
    var failures: Double = 0
    var pulls: Int = 0
}

/// Learned evidence per (context, arm), plus a global per-arm aggregate.
///
/// Rewards are on the design's scale (+1 start ≤ 10 min, +0.5 completed, ±0.5 rating, 0 ignored).
/// They map into Beta evidence as `u = clamp(reward / 2, 0, 1)`: success += u, failure += 1 − u.
struct CoachBanditModel: Codable, Sendable, Equatable {
    static let maxReward = 2.0
    /// Share of the global (all-context) evidence an arm borrows, so sparse contexts learn faster.
    static let globalPoolingWeight = 0.3

    private(set) var contextual: [String: CoachArmEvidence] = [:]
    private(set) var global: [String: CoachArmEvidence] = [:]

    static func cellKey(context: String, arm: CoachArm) -> String { "\(context)#\(arm.key)" }

    static func successFraction(for reward: Double) -> Double {
        min(1, max(0, reward / maxReward))
    }

    mutating func record(context: String, arm: CoachArm, reward: Double) {
        guard arm.surface != .silent else { return }
        let u = Self.successFraction(for: reward)
        let key = Self.cellKey(context: context, arm: arm)
        contextual[key, default: .init()].successes += u
        contextual[key, default: .init()].failures += 1 - u
        contextual[key, default: .init()].pulls += 1
        global[arm.key, default: .init()].successes += u
        global[arm.key, default: .init()].failures += 1 - u
        global[arm.key, default: .init()].pulls += 1
    }

    static func rebuild(from records: [CoachRewardRecord]) -> CoachBanditModel {
        var model = CoachBanditModel()
        for record in records {
            model.record(context: record.contextKey, arm: record.arm, reward: record.reward)
        }
        return model
    }

    func evidence(context: String, arm: CoachArm) -> CoachArmEvidence {
        contextual[Self.cellKey(context: context, arm: arm)] ?? .init()
    }

    func globalEvidence(arm: CoachArm) -> CoachArmEvidence {
        global[arm.key] ?? .init()
    }
}

// MARK: - Policy

/// Thompson sampling over surface × style arms.
struct CoachBanditPolicy: Sendable {
    /// `silent` never learns: a prompt must beat ~5% to be worth showing.
    static let silentPrior = (alpha: 1.0, beta: 19.0)

    /// Prior for an arm. The user's chosen style starts at Beta(3,1), other styles at Beta(1,1).
    /// The panel is the primary idle surface; badges and notifications start a little weaker.
    static func prior(for arm: CoachArm, preferredStyle: CoachStyle) -> (alpha: Double, beta: Double) {
        guard let style = arm.style, arm.surface != .silent else { return silentPrior }
        let base: (alpha: Double, beta: Double) = style == preferredStyle ? (3, 1) : (1, 1)
        switch arm.surface {
        case .strongWindow:
            // The pause screen only reaches the bandit at L3, where it is the designed escalation.
            return (base.alpha + 1, base.beta)
        case .panel, .silent:
            return base
        case .badge:
            return (base.alpha, base.beta + 1)
        case .notification:
            return (base.alpha, base.beta + 0.5)
        }
    }

    static func posterior(
        for arm: CoachArm,
        context: String,
        model: CoachBanditModel,
        preferredStyle: CoachStyle
    ) -> (alpha: Double, beta: Double) {
        let prior = prior(for: arm, preferredStyle: preferredStyle)
        guard arm.surface != .silent else { return prior }
        let local = model.evidence(context: context, arm: arm)
        let all = model.globalEvidence(arm: arm)
        let w = CoachBanditModel.globalPoolingWeight
        let pooledSuccesses = max(0, all.successes - local.successes) * w
        let pooledFailures = max(0, all.failures - local.failures) * w
        return (
            prior.alpha + local.successes + pooledSuccesses,
            prior.beta + local.failures + pooledFailures
        )
    }

    /// Samples every arm's posterior and returns the argmax. Deterministic for a seeded RNG.
    func choose<G: RandomNumberGenerator>(
        context: String,
        surfaces: [CoachSurface],
        preferredStyle: CoachStyle,
        model: CoachBanditModel,
        using rng: inout G
    ) -> CoachArm {
        choose(contextFor: { _ in context }, surfaces: surfaces, preferredStyle: preferredStyle, model: model, using: &rng)
    }

    /// Same, with a context per arm. The rescue loop keys each arm's evidence by its own
    /// surface (`…|lvl:3|surf:pauseScreen`).
    func choose<G: RandomNumberGenerator>(
        contextFor: (CoachArm) -> String,
        surfaces: [CoachSurface],
        preferredStyle: CoachStyle,
        model: CoachBanditModel,
        using rng: inout G
    ) -> CoachArm {
        // The user's chosen style is the only style used (v3 §3.5, R7): the bandit learns
        // where and whether to prompt, not how to talk to someone who asked for Challenger.
        var candidates = CoachArm.arms(for: surfaces).filter { $0.style == nil || $0.style == preferredStyle }
        if !candidates.contains(.silent) { candidates.insert(.silent, at: 0) }
        var best = CoachArm.silent
        var bestSample = -Double.infinity
        for arm in candidates {
            let p = Self.posterior(for: arm, context: contextFor(arm), model: model, preferredStyle: preferredStyle)
            let sample = BetaSampler.sample(alpha: p.alpha, beta: p.beta, using: &rng)
            if sample > bestSample {
                bestSample = sample
                best = arm
            }
        }
        return best
    }
}

// MARK: - Sampling

enum BetaSampler {
    static func sample<G: RandomNumberGenerator>(alpha: Double, beta: Double, using rng: inout G) -> Double {
        let x = gamma(shape: max(alpha, 1e-6), using: &rng)
        let y = gamma(shape: max(beta, 1e-6), using: &rng)
        guard x + y > 0 else { return 0.5 }
        return x / (x + y)
    }

    /// Marsaglia–Tsang. Shapes below 1 use the boost `Γ(a) = Γ(a + 1) · U^(1/a)`.
    static func gamma<G: RandomNumberGenerator>(shape: Double, using rng: inout G) -> Double {
        if shape < 1 {
            let u = Double.random(in: Double.leastNonzeroMagnitude..<1, using: &rng)
            return gamma(shape: shape + 1, using: &rng) * pow(u, 1 / shape)
        }
        let d = shape - 1.0 / 3.0
        let c = 1.0 / sqrt(9 * d)
        while true {
            var x: Double
            var v: Double
            repeat {
                x = normal(using: &rng)
                v = 1 + c * x
            } while v <= 0
            v = v * v * v
            let u = Double.random(in: Double.leastNonzeroMagnitude..<1, using: &rng)
            if u < 1 - 0.0331 * x * x * x * x { return d * v }
            if log(u) < 0.5 * x * x + d * (1 - v + log(v)) { return d * v }
        }
    }

    static func normal<G: RandomNumberGenerator>(using rng: inout G) -> Double {
        let u1 = Double.random(in: Double.leastNonzeroMagnitude..<1, using: &rng)
        let u2 = Double.random(in: 0..<1, using: &rng)
        return sqrt(-2 * log(u1)) * cos(2 * .pi * u2)
    }
}

/// Small deterministic generator for tests and reproducible arm selection.
struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

// MARK: - Persistence

/// Caches the bandit model as JSON in UserDefaults. The source of truth is the
/// `InterventionAttempt` rows: the model is rebuilt from them on launch and after each reward.
struct CoachBanditStore {
    static let storageKey = "focusflow.coachBandit.v1"
    let defaults: UserDefaults

    init(defaults: UserDefaults = AppIsolation.defaults) {
        self.defaults = defaults
    }

    func load() -> CoachBanditModel? {
        guard let data = defaults.data(forKey: Self.storageKey) else { return nil }
        return try? JSONDecoder().decode(CoachBanditModel.self, from: data)
    }

    func save(_ model: CoachBanditModel) {
        guard let data = try? JSONEncoder().encode(model) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
