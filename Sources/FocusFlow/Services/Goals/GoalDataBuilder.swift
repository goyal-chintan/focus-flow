import Foundation

/// Feeds the pure goal and priority logic (`GoalTracking.swift`) from SwiftData models.
@MainActor
enum GoalDataBuilder {
    static func projectKey(_ project: Project) -> String { "project:\(project.id.uuidString)" }

    /// Projects with their target for the period: the sum of each day's target.
    static func projectInfos(_ projects: [Project], days: [Date], calendar: Calendar = .current) -> [PriorityAllocation.ProjectInfo] {
        projects.filter { !$0.archived }.map { project in
            let minutes = days.compactMap { project.dailyTarget(on: $0, calendar: calendar) }
            return PriorityAllocation.ProjectInfo(
                id: projectKey(project),
                name: project.name,
                colorName: project.color,
                rank: project.priorityRank,
                area: project.area,
                targetSeconds: minutes.isEmpty ? nil : TimeInterval(minutes.reduce(0, +) * 60)
            )
        }
    }

    /// Seconds per project key inside `interval`, with split blocks shared by their weights.
    static func seconds(samples: [FocusSample], in interval: DateInterval) -> [String: TimeInterval] {
        var result: [String: TimeInterval] = [:]
        for sample in samples where sample.isFocus {
            let overlap = sample.overlap(with: interval)
            guard overlap > 0 else { continue }
            for share in sample.normalisedShares {
                result[share.project.id, default: 0] += overlap * share.fraction
            }
        }
        return result
    }

    /// Own work is measured separately once some project is marked Work: office hours must not
    /// fill the personal goal (priorities-goals design §3.3).
    static func ownWorkConfigured(_ projects: [Project]) -> Bool {
        projects.contains { !$0.archived && $0.areaRaw != nil && $0.area == .work }
    }

    static func ownWorkKeys(_ projects: [Project]) -> Set<String> {
        Set(projects.filter { !$0.archived && $0.areaRaw != nil && $0.area.isOwnWork }.map(projectKey))
    }

    /// Samples shrunk to their own-work share (split blocks count by their own-work weight).
    static func ownWorkSamples(_ samples: [FocusSample], projects: [Project]) -> [FocusSample] {
        let keys = ownWorkKeys(projects)
        return samples.compactMap { sample in
            let fraction = sample.normalisedShares.filter { keys.contains($0.project.id) }.reduce(0) { $0 + $1.fraction }
            guard fraction > 0 else { return nil }
            return FocusSample(
                id: sample.id, start: sample.start, activeSeconds: sample.activeSeconds * fraction, isFocus: sample.isFocus,
                completed: sample.completed, project: sample.project, priorityID: sample.priorityID,
                outcome: sample.outcome, intentText: sample.intentText
            )
        }
    }

    static func allocation(samples: [FocusSample], projects: [Project], day: DateInterval, calendar: Calendar = .current) -> PriorityAllocation {
        PriorityAllocation.compute(
            projects: projectInfos(projects, days: [day.start], calendar: calendar),
            seconds: seconds(samples: samples, in: day)
        )
    }

    /// The last `days` days, ending today.
    static func drift(samples: [FocusSample], projects: [Project], now: Date, days: Int = 7, calendar: Calendar = .current) -> DriftReport {
        let today = calendar.startOfDay(for: now)
        let perDay: [(day: Date, allocation: PriorityAllocation)] = (0..<days).reversed().compactMap { offset in
            guard let start = calendar.date(byAdding: .day, value: -offset, to: today),
                  let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
            return (start, allocation(samples: samples, projects: projects, day: DateInterval(start: start, end: end), calendar: calendar))
        }
        return DriftReport.compute(perDay: perDay)
    }

    static func summary(_ goal: ProjectGoal, now: Date) -> GoalPacing.GoalSummary {
        GoalPacing.summary(
            keyResults: goal.sortedKeyResults.map { ($0.target, $0.done) },
            start: goal.startDate, deadline: goal.deadline, now: now
        )
    }

    static func leverInputs(_ goals: [ProjectGoal], now: Date, calendar: Calendar = .current) -> [DailyLevers.KeyResultInput] {
        let today = calendar.startOfDay(for: now)
        return goals.filter { $0.status == .active }.flatMap { goal in
            goal.sortedKeyResults.map { kr in
                DailyLevers.KeyResultInput(
                    id: kr.id, title: kr.title, unit: kr.unit, isCheckbox: kr.kind == .checkbox,
                    target: kr.target, done: kr.done,
                    doneToday: kr.entries.filter { $0.at >= today }.reduce(0) { $0 + $1.amount },
                    goalTitle: goal.title, projectID: goal.projectID,
                    start: goal.startDate, deadline: goal.deadline, isBossFight: goal.isBossFight
                )
            }
        }
    }

    /// The most urgent count result (the top lever's), for goal-aware coach copy.
    static func goalFact(_ goals: [ProjectGoal], now: Date) -> CoachGoalFact? {
        let levers = levers(goals, now: now)
        for lever in levers {
            for goal in goals where goal.status == .active {
                guard let kr = goal.keyResults.first(where: { $0.id == lever.id }), kr.kind == .count else { continue }
                let pace = GoalPacing.pace(target: kr.target, done: kr.done, start: goal.startDate, deadline: goal.deadline, now: now)
                return CoachGoalFact(
                    goalTitle: goal.title, resultTitle: kr.title,
                    done: Int(kr.done.rounded()), target: Int(kr.target.rounded()),
                    behind: max(0, Int((-pace.delta).rounded())),
                    daysLeft: max(0, Int(pace.daysLeft.rounded(.up)))
                )
            }
        }
        return nil
    }

    static func levers(_ goals: [ProjectGoal], now: Date) -> [DailyLever] {
        DailyLevers.levers(leverInputs(goals, now: now), now: now)
    }
}
