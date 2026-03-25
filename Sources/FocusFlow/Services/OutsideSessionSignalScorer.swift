import Foundation

struct OutsideSessionWorkIntentSignals: Sendable {
    var openedAppRecently: Bool
    var selectedProjectRecently: Bool
    var recentlyAbandonedStart: Bool
    var withinTypicalWorkHours: Bool
    var isWeekday: Bool
    var preMeetingRunwayMinutes: Int?
    var matchesHistoricalMissedStart: Bool
    var productiveContinuity: Bool?
}

struct OutsideSessionDriftSignals: Sendable {
    var frontmostCategory: AppUsageEntry.AppCategory
    var appSwitchesPerMinute: Double
    var contextMismatch: Bool
    var overPlanningLoopDetected: Bool
    var breakOverrunRisk: Bool
    var startFrictionRepeats: Int
    var fatigueRisk: Bool
}

enum OutsideSessionRiskLevel: String, Sendable {
    case low
    case medium
    case high
}

struct OutsideSessionSignalScoreResult: Sendable {
    let score: Double
    let availableSignalCount: Int
    let activeSignals: [String]
    let level: OutsideSessionRiskLevel
}

struct OutsideSessionSignalScorer: Sendable {
    private let workIntentWeights: [(String, Double)] = [
        ("opened_app_recently", 0.18),
        ("selected_project_recently", 0.20),
        ("recently_abandoned_start", 0.15),
        ("within_typical_work_hours", 0.12),
        ("is_weekday", 0.08),
        ("pre_meeting_runway", 0.07),
        ("historical_missed_start", 0.12),
        ("productive_continuity", 0.08)
    ]

    private let driftWeights: [(String, Double)] = [
        ("distracting_context", 0.20),
        ("switch_burst", 0.15),
        ("context_mismatch", 0.20),
        ("over_planning_loop", 0.10),
        ("break_overrun_risk", 0.10),
        ("start_friction_repeats", 0.15),
        ("fatigue_risk", 0.10)
    ]

    func scoreWorkIntent(_ signals: OutsideSessionWorkIntentSignals) -> OutsideSessionSignalScoreResult {
        var numerator: Double = 0
        var denominator: Double = 0
        var activeSignals: [String] = []
        var availableSignalCount = 0

        for (key, weight) in workIntentWeights {
            let value = workIntentSignalValue(for: key, from: signals)
            if let value {
                availableSignalCount += 1
                denominator += weight
                numerator += value * weight
                if value > 0 {
                    activeSignals.append(key)
                }
            }
        }

        let score = denominator > 0 ? clamp(numerator / denominator) : 0
        return OutsideSessionSignalScoreResult(
            score: score,
            availableSignalCount: availableSignalCount,
            activeSignals: activeSignals,
            level: level(for: score)
        )
    }

    func scoreDrift(_ signals: OutsideSessionDriftSignals) -> OutsideSessionSignalScoreResult {
        var numerator: Double = 0
        var denominator: Double = 0
        var activeSignals: [String] = []
        var availableSignalCount = 0

        for (key, weight) in driftWeights {
            let value = driftSignalValue(for: key, from: signals)
            if let value {
                availableSignalCount += 1
                denominator += weight
                numerator += value * weight
                if value > 0 {
                    activeSignals.append(key)
                }
            }
        }

        let score = denominator > 0 ? clamp(numerator / denominator) : 0
        return OutsideSessionSignalScoreResult(
            score: score,
            availableSignalCount: availableSignalCount,
            activeSignals: activeSignals,
            level: level(for: score)
        )
    }

    private func workIntentSignalValue(for key: String, from signals: OutsideSessionWorkIntentSignals) -> Double? {
        switch key {
        case "opened_app_recently":
            return signals.openedAppRecently ? 1 : 0
        case "selected_project_recently":
            return signals.selectedProjectRecently ? 1 : 0
        case "recently_abandoned_start":
            return signals.recentlyAbandonedStart ? 1 : 0
        case "within_typical_work_hours":
            return signals.withinTypicalWorkHours ? 1 : 0
        case "is_weekday":
            return signals.isWeekday ? 1 : 0
        case "pre_meeting_runway":
            guard let minutes = signals.preMeetingRunwayMinutes else { return nil }
            if minutes < 10 || minutes > 40 { return 0 }
            return 1
        case "historical_missed_start":
            return signals.matchesHistoricalMissedStart ? 1 : 0
        case "productive_continuity":
            guard let productive = signals.productiveContinuity else { return nil }
            return productive ? 1 : 0
        default:
            return nil
        }
    }

    private func driftSignalValue(for key: String, from signals: OutsideSessionDriftSignals) -> Double? {
        switch key {
        case "distracting_context":
            switch signals.frontmostCategory {
            case .distracting: return 1
            case .neutral: return 0.5
            case .productive: return 0.2
            }
        case "switch_burst":
            return clamp(signals.appSwitchesPerMinute / 15)
        case "context_mismatch":
            return signals.contextMismatch ? 1 : 0
        case "over_planning_loop":
            return signals.overPlanningLoopDetected ? 1 : 0
        case "break_overrun_risk":
            return signals.breakOverrunRisk ? 1 : 0
        case "start_friction_repeats":
            return clamp(Double(signals.startFrictionRepeats) / 3)
        case "fatigue_risk":
            return signals.fatigueRisk ? 1 : 0
        default:
            return nil
        }
    }

    private func level(for score: Double) -> OutsideSessionRiskLevel {
        if score >= 0.65 { return .high }
        if score >= 0.45 { return .medium }
        return .low
    }

    private func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}
