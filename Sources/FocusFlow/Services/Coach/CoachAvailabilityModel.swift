import Foundation

/// Learned focus windows (Coach v2 design §3 [1]).
///
/// 168 hour-of-week buckets. Each bucket keeps a Beta posterior of the user's start rate:
/// `Beta(α0 + starts, β0 + max(0, opportunityHours − starts))`, smoothed ±1 hour so 11:00
/// informs 10:00 and 12:00. The prior is weak (α0 = 1, β0 = 20).
///
/// **Opportunity estimate** (documented approximation). FocusFlow has no hour-level record of
/// when the Mac was awake, only daily `AppUsageEntry` rows. An "active day" is a day with any
/// `AppUsageEntry` row or any focus session. On an active day every hour counts as one
/// opportunity-hour, weighted by a broad awake profile (07:00–01:59 = 1.0, 02:00–06:59 = 0.2),
/// minus the minutes the user was already in a focus session during that hour. Ranking between
/// awake hours is therefore driven by where the user actually starts sessions.
///
/// **Cold start.** With no starts at all every hour is open (no hardcoded schedule; guardrails
/// and the daily cap still apply). With fewer than `minimumStartsForLearning` starts the model
/// falls back to the user's historical start hours (hour of day ±1, any weekday).
struct CoachAvailabilityModel: Sendable, Equatable {
    enum Mode: Sendable, Equatable {
        /// No session history: every hour is a candidate window.
        case noData
        /// Few starts: windows are the user's historical start hours ±1 (any weekday).
        case coldStart(startHours: Set<Int>)
        /// Enough starts: windows come from the 168 posteriors.
        case learned
    }

    enum Tier: String, Sendable, Codable, CaseIterable {
        case high
        case medium
        case low
    }

    struct Session: Sendable, Equatable {
        let start: Date
        let end: Date
    }

    static let bucketCount = 168
    static let priorAlpha = 1.0
    static let priorBeta = 20.0
    static let minimumStartsForLearning = 8
    static let topWindowsPerDay = 4

    let mode: Mode
    let alphas: [Double]
    let betas: [Double]
    let calendar: Calendar
    let totalStarts: Int
    /// Mean posterior start rate over all 168 buckets; a learned window must beat it.
    let meanRate: Double

    // MARK: - Construction

    static let empty = CoachAvailabilityModel(sessions: [], activeDays: [], calendar: .current)

    /// Builds the model from past focus sessions and the days the Mac was in use.
    init(sessions: [Session], activeDays: [Date], calendar: Calendar = .current) {
        self.calendar = calendar
        var starts = [Double](repeating: 0, count: Self.bucketCount)
        for session in sessions {
            starts[Self.bucketIndex(for: session.start, calendar: calendar)] += 1
        }
        let opportunities = Self.opportunityHours(sessions: sessions, activeDays: activeDays, calendar: calendar)
        let smoothedStarts = Self.smooth(starts)
        let smoothedOpportunities = Self.smooth(opportunities)

        var alphas = [Double](repeating: Self.priorAlpha, count: Self.bucketCount)
        var betas = [Double](repeating: Self.priorBeta, count: Self.bucketCount)
        for index in 0..<Self.bucketCount {
            let s = smoothedStarts[index]
            alphas[index] = Self.priorAlpha + s
            betas[index] = Self.priorBeta + max(0, smoothedOpportunities[index] - s)
        }
        self.alphas = alphas
        self.betas = betas
        self.totalStarts = sessions.count
        let rates = zip(alphas, betas).map { $0 / ($0 + $1) }
        self.meanRate = rates.reduce(0, +) / Double(rates.count)

        if sessions.isEmpty {
            mode = .noData
        } else if sessions.count < Self.minimumStartsForLearning {
            mode = .coldStart(startHours: Set(sessions.map { calendar.component(.hour, from: $0.start) }))
        } else {
            mode = .learned
        }
    }

    // MARK: - Queries

    /// Posterior mean start probability for the hour containing `date`.
    func p(_ date: Date) -> Double {
        let index = Self.bucketIndex(for: date, calendar: calendar)
        return alphas[index] / (alphas[index] + betas[index])
    }

    /// The Beta posterior for the hour containing `date`.
    func posterior(_ date: Date) -> (alpha: Double, beta: Double) {
        let index = Self.bucketIndex(for: date, calendar: calendar)
        return (alphas[index], betas[index])
    }

    func isGoodWindow(_ date: Date) -> Bool {
        switch mode {
        case .noData:
            return true
        case .coldStart(let startHours):
            let hour = calendar.component(.hour, from: date)
            return startHours.contains { Self.hourDistance($0, hour) <= 1 }
        case .learned:
            return isLearnedWindow(bucket: Self.bucketIndex(for: date, calendar: calendar))
        }
    }

    func tier(_ date: Date) -> Tier {
        if isGoodWindow(date) { return .high }
        if case .learned = mode, p(date) >= meanRate { return .medium }
        return .low
    }

    /// Start of the next good window that opens strictly after `date` (within 8 days).
    /// A window "opens" at an hour that is good while the previous hour is not.
    /// With no data every hour is open, so there is no meaningful next window: returns nil.
    func nextGoodWindow(after date: Date) -> Date? {
        if case .noData = mode { return nil }
        guard let currentHourStart = calendar.dateInterval(of: .hour, for: date)?.start else { return nil }
        var previousGood = isGoodWindow(currentHourStart)
        for offset in 1...(8 * 24) {
            guard let hourStart = calendar.date(byAdding: .hour, value: offset, to: currentHourStart) else { break }
            let good = isGoodWindow(hourStart)
            if good && !previousGood { return hourStart }
            previousGood = good
        }
        return nil
    }

    /// Minutes of good window left between `now` and the end of today. Nil when there is no
    /// data to say where the windows are.
    func goodWindowMinutesRemainingToday(from now: Date) -> Int? {
        if case .noData = mode { return nil }
        guard let dayEnd = calendar.dateInterval(of: .day, for: now)?.end,
              var hourStart = calendar.dateInterval(of: .hour, for: now)?.start else { return nil }
        var seconds: TimeInterval = 0
        while hourStart < dayEnd {
            guard let hourEnd = calendar.date(byAdding: .hour, value: 1, to: hourStart) else { break }
            if isGoodWindow(hourStart) {
                seconds += max(0, min(hourEnd, dayEnd).timeIntervalSince(max(hourStart, now)))
            }
            hourStart = hourEnd
        }
        return Int(seconds / 60)
    }

    /// The hour of day with the highest posterior for `date`'s weekday (learned mode only).
    func usualStartHour(on date: Date) -> Int? {
        guard case .learned = mode else { return nil }
        let dayBase = (calendar.component(.weekday, from: date) - 1) * 24
        let best = (0..<24).max { rate(dayBase + $0) < rate(dayBase + $1) }
        return best
    }

    // MARK: - Internals

    private func rate(_ bucket: Int) -> Double {
        alphas[bucket] / (alphas[bucket] + betas[bucket])
    }

    private func isLearnedWindow(bucket: Int) -> Bool {
        let dayBase = (bucket / 24) * 24
        let dayRates = (0..<24).map { rate(dayBase + $0) }
        let threshold = dayRates.sorted(by: >)[Self.topWindowsPerDay - 1]
        let value = rate(bucket)
        return value >= threshold && value > meanRate
    }

    /// Bucket index: (weekday − 1) × 24 + hour, weekday 1 = Sunday.
    static func bucketIndex(for date: Date, calendar: Calendar) -> Int {
        let weekday = calendar.component(.weekday, from: date)
        let hour = calendar.component(.hour, from: date)
        return (weekday - 1) * 24 + hour
    }

    static func hourDistance(_ a: Int, _ b: Int) -> Int {
        let d = abs(a - b) % 24
        return min(d, 24 - d)
    }

    /// Weights [0.5, 1, 0.5] over the previous, same and next hour of week (wrapping).
    static func smooth(_ values: [Double]) -> [Double] {
        let n = values.count
        return (0..<n).map { i in
            values[i] + 0.5 * values[(i - 1 + n) % n] + 0.5 * values[(i + 1) % n]
        }
    }

    /// Awake weight of an hour of day for the opportunity estimate.
    static func awakeWeight(hour: Int) -> Double {
        (2...6).contains(hour) ? 0.2 : 1.0
    }

    static func opportunityHours(sessions: [Session], activeDays: [Date], calendar: Calendar) -> [Double] {
        var days = Set(activeDays.map { calendar.startOfDay(for: $0) })
        for session in sessions { days.insert(calendar.startOfDay(for: session.start)) }

        var opportunities = [Double](repeating: 0, count: bucketCount)
        for day in days {
            for hour in 0..<24 {
                guard let hourStart = calendar.date(byAdding: .hour, value: hour, to: day),
                      let hourEnd = calendar.date(byAdding: .hour, value: 1, to: hourStart) else { continue }
                let inSession = sessions.reduce(0.0) { sum, session in
                    let overlap = min(session.end, hourEnd).timeIntervalSince(max(session.start, hourStart))
                    return sum + max(0, overlap)
                }
                let available = max(0, awakeWeight(hour: hour) - inSession / 3600)
                opportunities[bucketIndex(for: hourStart, calendar: calendar)] += available
            }
        }
        return opportunities
    }
}
