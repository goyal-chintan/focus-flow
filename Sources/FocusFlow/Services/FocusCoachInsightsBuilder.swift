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
        var taskType: String?
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
        let resolvedAt: Date?
    }

    struct AppUsageSnapshot: Sendable {
        let appName: String
        let duringFocusSeconds: Int
        let category: String
    }

    struct TaskIntentSnapshot: Sendable {
        let sessionId: UUID?
        let taskType: FocusCoachTaskType
    }

    func build(
        sessions: [SessionSnapshot],
        interruptions: [InterruptionSnapshot],
        attempts: [AttemptSnapshot],
        appUsage: [AppUsageSnapshot],
        taskIntents: [TaskIntentSnapshot] = [],
        previousWeekSessions: [SessionSnapshot] = []
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

        // Recovery speed: average time between intervention delivery and resolution
        let resolvedAttempts = attempts.compactMap { attempt -> Double? in
            guard let resolved = attempt.resolvedAt else { return nil }
            return resolved.timeIntervalSince(attempt.deliveredAt)
        }
        let recoverySpeed = resolvedAttempts.isEmpty ? 0 : resolvedAttempts.reduce(0, +) / Double(resolvedAttempts.count)

        // Legitimate interruption ratio
        let legitimateCount = interruptions.filter(\.isLegitimate).count
        let legitimateRatio = interruptions.isEmpty ? 0 : Double(legitimateCount) / Double(interruptions.count)

        // Best session length by task type: find the avg duration of completed sessions per type
        var sessionsByType: [FocusCoachTaskType: [Int]] = [:]
        let intentMap = Dictionary(grouping: taskIntents) { $0.sessionId }
        for session in focusSessions where session.completed {
            let taskType: FocusCoachTaskType
            if let sid = intentMap.first(where: { $0.key == session.id })?.value.first?.taskType {
                taskType = sid
            } else if let rawType = session.taskType, let t = FocusCoachTaskType(rawValue: rawType) {
                taskType = t
            } else {
                taskType = .deepWork
            }
            sessionsByType[taskType, default: []].append(Int(session.duration / 60))
        }
        let bestSessionLengthByTaskType = sessionsByType.mapValues { durations in
            durations.reduce(0, +) / max(1, durations.count)
        }

        // Week-over-week trend: compare completion rate vs previous week
        let prevFocusSessions = previousWeekSessions.filter { $0.type == "focus" }
        let weekOverWeekTrend: Double?
        if !prevFocusSessions.isEmpty {
            let prevCompleted = prevFocusSessions.filter(\.completed).count
            let prevRate = Double(prevCompleted) / Double(prevFocusSessions.count)
            weekOverWeekTrend = completionRate - prevRate
        } else {
            weekOverWeekTrend = nil
        }

        return FocusCoachWeeklyReport(
            avgStartLatencySeconds: avgStartLatency,
            avgSessionMinutes: avgMinutes,
            completionRate: completionRate,
            interventionWinRate: winRate,
            totalSessions: focusSessions.count,
            totalInterruptions: interruptions.count,
            topTriggers: topTriggers,
            bestSessionLengthByTaskType: bestSessionLengthByTaskType,
            recoverySpeedSeconds: recoverySpeed,
            legitimateInterruptionRatio: legitimateRatio,
            weekOverWeekTrend: weekOverWeekTrend
        )
    }

    // MARK: - Intervention Effectiveness

    /// Per-intervention-kind effectiveness breakdown for insights UI
    struct InterventionEffectiveness: Sendable {
        let kind: FocusCoachInterventionKind
        let totalCount: Int
        let improvedCount: Int
        let winRate: Double
    }

    func interventionEffectiveness(attempts: [AttemptSnapshot]) -> [InterventionEffectiveness] {
        var grouped: [FocusCoachInterventionKind: (total: Int, improved: Int)] = [:]
        for attempt in attempts {
            guard let outcome = attempt.outcome else { continue }
            let kind = attempt.kind
            var entry = grouped[kind, default: (total: 0, improved: 0)]
            entry.total += 1
            if outcome == .improved { entry.improved += 1 }
            grouped[kind] = entry
        }
        return grouped.map { kind, stats in
            InterventionEffectiveness(
                kind: kind,
                totalCount: stats.total,
                improvedCount: stats.improved,
                winRate: stats.total > 0 ? Double(stats.improved) / Double(stats.total) : 0
            )
        }.sorted { $0.totalCount > $1.totalCount }
    }
}
