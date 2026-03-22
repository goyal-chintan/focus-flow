import Foundation

/// Weekly coach report output — aggregated metrics from session, interruption, and intervention data.
struct FocusCoachWeeklyReport: Sendable {
    let avgStartLatencySeconds: Int
    let avgSessionMinutes: Int
    let completionRate: Double
    let interventionWinRate: Double
    let totalSessions: Int
    let totalInterruptions: Int
    let topTriggers: [TriggerMetric]
    let bestSessionLengthByTaskType: [FocusCoachTaskType: Int]
    let recoverySpeedSeconds: Double
    let legitimateInterruptionRatio: Double
    let weekOverWeekTrend: Double?

    struct TriggerMetric: Sendable {
        let label: String
        let count: Int
        let icon: String
    }

    static let empty = FocusCoachWeeklyReport(
        avgStartLatencySeconds: 0,
        avgSessionMinutes: 0,
        completionRate: 0,
        interventionWinRate: 0,
        totalSessions: 0,
        totalInterruptions: 0,
        topTriggers: [],
        bestSessionLengthByTaskType: [:],
        recoverySpeedSeconds: 0,
        legitimateInterruptionRatio: 0,
        weekOverWeekTrend: nil
    )
}

/// Pure analytics builder. Takes raw data arrays, returns a structured report.
/// No SwiftData dependency — testable with plain arrays.
struct FocusCoachInsightsBuilder: Sendable {

    struct SessionSnapshot: Sendable {
        let id: UUID
        let type: String
        let duration: TimeInterval
        let startedAt: Date
        let endedAt: Date?
        let completed: Bool
    }

    struct InterruptionSnapshot: Sendable {
        let kind: FocusCoachInterruptionKind
        let reason: FocusCoachReason?
        let isLegitimate: Bool
        let detectedAt: Date
    }

    struct AttemptSnapshot: Sendable {
        let kind: FocusCoachInterventionKind
        let outcome: FocusCoachOutcome?
        let riskScore: Double
        let deliveredAt: Date
    }

    struct AppUsageSnapshot: Sendable {
        let appName: String
        let duringFocusSeconds: Int
        let category: String
    }

    func build(
        sessions: [SessionSnapshot],
        interruptions: [InterruptionSnapshot],
        attempts: [AttemptSnapshot],
        appUsage: [AppUsageSnapshot]
    ) -> FocusCoachWeeklyReport {
        let focusSessions = sessions.filter { $0.type == "focus" }

        // Average start latency (time from "plan to start" to actual start — approximated as session start hour consistency)
        let startLatencies = focusSessions.compactMap { session -> Int? in
            guard let endedAt = session.endedAt else { return nil }
            let actualDuration = endedAt.timeIntervalSince(session.startedAt)
            let plannedDuration = session.duration
            let startDelay = max(0, actualDuration - plannedDuration)
            return Int(startDelay)
        }
        let avgStartLatency = startLatencies.isEmpty ? 0 : startLatencies.reduce(0, +) / startLatencies.count

        // Average session length
        let sessionMinutes = focusSessions.map { Int($0.duration / 60) }
        let avgMinutes = sessionMinutes.isEmpty ? 0 : sessionMinutes.reduce(0, +) / sessionMinutes.count

        // Completion rate
        let completedCount = focusSessions.filter(\.completed).count
        let completionRate = focusSessions.isEmpty ? 0 : Double(completedCount) / Double(focusSessions.count)

        // Intervention win rate (improved / total with outcome)
        let withOutcome = attempts.filter { $0.outcome != nil }
        let improvedCount = withOutcome.filter { $0.outcome == .improved }.count
        let winRate = withOutcome.isEmpty ? 0 : Double(improvedCount) / Double(withOutcome.count)

        // Top triggers from app usage during focus
        let distractingApps = appUsage
            .filter { $0.category == "distracting" && $0.duringFocusSeconds > 30 }
            .sorted { $0.duringFocusSeconds > $1.duringFocusSeconds }
            .prefix(5)

        let topTriggers: [FocusCoachWeeklyReport.TriggerMetric]
        if !distractingApps.isEmpty {
            topTriggers = distractingApps.map {
                FocusCoachWeeklyReport.TriggerMetric(
                    label: $0.appName,
                    count: $0.duringFocusSeconds / 60,
                    icon: "app.fill"
                )
            }
        } else {
            // Fallback: use interruption kinds as triggers
            var kindCounts: [FocusCoachInterruptionKind: Int] = [:]
            for interruption in interruptions {
                kindCounts[interruption.kind, default: 0] += 1
            }
            topTriggers = kindCounts.sorted { $0.value > $1.value }.prefix(3).map {
                FocusCoachWeeklyReport.TriggerMetric(
                    label: $0.key.displayName,
                    count: $0.value,
                    icon: "exclamationmark.triangle.fill"
                )
            }
        }

        // Recovery speed (time between intervention delivery and outcome resolution)
        // Approximated as average gap between consecutive attempts
        let recoverySpeed: Double = 0 // Simplified — would need resolvedAt timestamps

        // Legitimate interruption ratio
        let legitimateCount = interruptions.filter(\.isLegitimate).count
        let legitimateRatio = interruptions.isEmpty ? 0 : Double(legitimateCount) / Double(interruptions.count)

        return FocusCoachWeeklyReport(
            avgStartLatencySeconds: avgStartLatency,
            avgSessionMinutes: avgMinutes,
            completionRate: completionRate,
            interventionWinRate: winRate,
            totalSessions: focusSessions.count,
            totalInterruptions: interruptions.count,
            topTriggers: topTriggers,
            bestSessionLengthByTaskType: [:],
            recoverySpeedSeconds: recoverySpeed,
            legitimateInterruptionRatio: legitimateRatio,
            weekOverWeekTrend: nil
        )
    }
}
