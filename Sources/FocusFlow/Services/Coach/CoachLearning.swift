import Foundation

// Coach v5 learning engine (docs/plans/2026-10-28-coach-v5-learning-engine-design.md §2–3).
// A conjugate Bayesian linear regression: Gaussian prior on the weights, Gaussian noise, closed-form
// posterior. Small (≤ 16 features), exact, and fast enough to rebuild from the log on every decision.

/// `y = xᵀθ + ε`, `θ ~ N(μ₀, diag(σ₀²))`, `ε ~ N(0, σ²)`.
/// Stores the posterior in information form: precision `A = Λ₀ + Σ w·xxᵀ/σ²`, shift `b = Λ₀μ₀ + Σ w·x·y/σ²`.
struct BayesianLinearModel: Sendable, Equatable {
    let dimension: Int
    let noiseVariance: Double
    /// Row-major d × d posterior precision.
    private(set) var precision: [Double]
    private(set) var shift: [Double]
    /// Number of observations folded in.
    private(set) var count: Int = 0

    init(priorMean: [Double], priorSD: [Double], noiseSD: Double) {
        precondition(priorMean.count == priorSD.count && !priorMean.isEmpty)
        let d = priorMean.count
        dimension = d
        noiseVariance = noiseSD * noiseSD
        var precision = [Double](repeating: 0, count: d * d)
        var shift = [Double](repeating: 0, count: d)
        for i in 0..<d {
            let lambda = 1 / max(priorSD[i] * priorSD[i], 1e-12)
            precision[i * d + i] = lambda
            shift[i] = lambda * priorMean[i]
        }
        self.precision = precision
        self.shift = shift
    }

    init(priorMean: [Double], priorSD: Double, noiseSD: Double) {
        self.init(priorMean: priorMean, priorSD: [Double](repeating: priorSD, count: priorMean.count), noiseSD: noiseSD)
    }

    /// Folds in one observation (`weight` scales its influence).
    mutating func update(x: [Double], y: Double, weight: Double = 1) {
        precondition(x.count == dimension)
        let d = dimension
        let scale = weight / noiseVariance
        for i in 0..<d where x[i] != 0 {
            shift[i] += scale * x[i] * y
            for j in 0..<d where x[j] != 0 {
                precision[i * d + j] += scale * x[i] * x[j]
            }
        }
        count += 1
    }

    /// Posterior mean `A⁻¹b`.
    var mean: [Double] {
        guard let l = Self.cholesky(precision, d: dimension) else { return shift }
        return Self.solve(l, d: dimension, shift)
    }

    /// Posterior covariance `A⁻¹`.
    var covariance: [Double] {
        let d = dimension
        guard let l = Self.cholesky(precision, d: d) else { return [Double](repeating: 0, count: d * d) }
        var result = [Double](repeating: 0, count: d * d)
        for column in 0..<d {
            var e = [Double](repeating: 0, count: d)
            e[column] = 1
            let solved = Self.solve(l, d: d, e)
            for row in 0..<d { result[row * d + column] = solved[row] }
        }
        return result
    }

    /// Predictive mean and variance of `xᵀθ` (the noise-free signal).
    func predict(_ x: [Double]) -> (mean: Double, variance: Double) {
        let d = dimension
        let m = mean
        let cov = covariance
        var mu = 0.0, variance = 0.0
        for i in 0..<d {
            mu += x[i] * m[i]
            guard x[i] != 0 else { continue }
            for j in 0..<d { variance += x[i] * cov[i * d + j] * x[j] }
        }
        return (mu, max(0, variance))
    }

    /// One draw of θ from the posterior: `μ + L⁻ᵀz` with `A = LLᵀ`, `z ~ N(0, I)`.
    func sample<G: RandomNumberGenerator>(using rng: inout G) -> [Double] {
        let d = dimension
        let m = mean
        guard let l = Self.cholesky(precision, d: d) else { return m }
        let z = (0..<d).map { _ in BetaSampler.normal(using: &rng) }
        let v = Self.backSubstituteTransposed(l, d: d, z)
        return zip(m, v).map(+)
    }

    // MARK: Linear algebra (small dense matrices)

    /// Lower-triangular `L` with `A = LLᵀ`, or nil if `A` is not positive definite.
    static func cholesky(_ a: [Double], d: Int) -> [Double]? {
        var l = [Double](repeating: 0, count: d * d)
        for i in 0..<d {
            for j in 0...i {
                var sum = a[i * d + j]
                for k in 0..<j { sum -= l[i * d + k] * l[j * d + k] }
                if i == j {
                    guard sum > 1e-12 else { return nil }
                    l[i * d + i] = sqrt(sum)
                } else {
                    l[i * d + j] = sum / l[j * d + j]
                }
            }
        }
        return l
    }

    /// Solves `LLᵀx = b`.
    static func solve(_ l: [Double], d: Int, _ b: [Double]) -> [Double] {
        var y = [Double](repeating: 0, count: d)
        for i in 0..<d {
            var sum = b[i]
            for k in 0..<i { sum -= l[i * d + k] * y[k] }
            y[i] = sum / l[i * d + i]
        }
        return backSubstituteTransposed(l, d: d, y)
    }

    /// Solves `Lᵀx = y`.
    static func backSubstituteTransposed(_ l: [Double], d: Int, _ y: [Double]) -> [Double] {
        var x = [Double](repeating: 0, count: d)
        for i in stride(from: d - 1, through: 0, by: -1) {
            var sum = y[i]
            for k in (i + 1)..<d { sum -= l[k * d + i] * x[k] }
            x[i] = sum / l[i * d + i]
        }
        return x
    }
}

enum CoachMath {
    /// Standard normal CDF.
    static func normalCDF(_ z: Double) -> Double { 0.5 * erfc(-z / 2.0.squareRoot()) }
}
