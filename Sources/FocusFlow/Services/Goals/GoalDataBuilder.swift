import Foundation
import SwiftData

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

    /// The ★ #1 project: the lowest priority rank among live projects.
    static func topProject(_ projects: [Project]) -> Project? {
        projects.filter { !$0.archived && $0.priorityRank != nil }.min { ($0.priorityRank ?? .max) < ($1.priorityRank ?? .max) }
    }

    /// What the daily goal counts (clarity fixes §4): one definition for the ring, the notch, the
    /// coach's pace and Today. Your ★ #1 project once one is ranked; else own work once a project is
    /// marked Work; else every block. Office time never fills the ring of the project you said matters.
    static func goalScope(_ projects: [Project]) -> GoalScope {
        if let top = topProject(projects) { return .project(key: projectKey(top), name: top.name) }
        if ownWorkConfigured(projects) { return .ownWork(keys: ownWorkKeys(projects)) }
        return .allFocus
    }

    /// The daily goal (one model, structural redesign 2026-10-30): what it counts (`goalScope`) and
    /// its size. With "Use project targets" on (nil = on) the size is the sum of today's targets of
    /// the projects it counts; when it is off, or none of them has a target today, the fixed goal.
    static func dailyGoal(projects: [Project], settings: AppSettings?, on day: Date = Date(), calendar: Calendar = .current) -> DailyGoal {
        let scope = goalScope(projects)
        let live = projects.filter { !$0.archived }
        let counted = scope.keys.map { keys in live.filter { keys.contains(projectKey($0)) } } ?? live
        return DailyGoal.resolve(
            scope: scope,
            targetMinutes: counted.compactMap { $0.dailyTarget(on: day, calendar: calendar) },
            fixedSeconds: settings?.dailyFocusGoal ?? DailyGoal.defaultSeconds,
            stretchSeconds: settings?.dailyStretchGoal ?? DailyGoal.defaultSeconds + DailyGoal.defaultStretchExtra,
            followsTargets: settings?.dailyGoalFollowsTargets ?? true
        )
    }

    /// Samples shrunk to the scope's share (split blocks count by their weight); all of them for `.allFocus`.
    static func scopedSamples(_ samples: [FocusSample], scope: GoalScope) -> [FocusSample] {
        guard let keys = scope.keys else { return samples }
        return limited(samples, to: keys)
    }

    /// Samples shrunk to their own-work share (split blocks count by their own-work weight).
    static func ownWorkSamples(_ samples: [FocusSample], projects: [Project]) -> [FocusSample] {
        limited(samples, to: ownWorkKeys(projects))
    }

    private static func limited(_ samples: [FocusSample], to keys: Set<String>) -> [FocusSample] {
        samples.compactMap { sample in
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
        let projects = (try? goals.first?.modelContext?.fetch(FetchDescriptor<Project>())) ?? []
        return goals.filter { $0.status == .active }.flatMap { goal in
            let boost = priorityBoost(projects.first { $0.id == goal.projectID })
            return goal.sortedKeyResults.filter { $0.kind == .count }.map { kr in
                DailyLevers.KeyResultInput(
                    id: kr.id, title: kr.title, unit: kr.unit,
                    target: kr.target, done: kr.done,
                    doneToday: kr.entries.filter { $0.at >= today }.reduce(0) { $0 + $1.amount },
                    goalTitle: goal.title, projectID: goal.projectID,
                    start: goal.startDate, deadline: goal.deadline, isBossFight: goal.isBossFight,
                    priorityBoost: boost
                )
            }
        }
    }

    /// Each counted number's day (6 Nov 2026): how many you did today and today's aim, by key result.
    static func todayCounts(_ goal: ProjectGoal, now: Date, calendar: Calendar = .current) -> [UUID: TodayCount] {
        Dictionary(uniqueKeysWithValues: leverInputs([goal], now: now, calendar: calendar).map { input in
            (input.id, TodayCount(done: input.doneToday, aim: DailyLevers.todayAim(input, now: now, calendar: calendar)))
        })
    }

    /// Levers favour what you are building for yourself: ★ #1 first, then own work (personal,
    /// learning), so an office goal never takes all three slots from them.
    static func priorityBoost(_ project: Project?) -> Double {
        guard let project else { return 0 }
        if project.priorityRank == 1 { return 10 }
        return project.area.isOwnWork ? 5 : 0
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

/// What the daily goal counts (`GoalDataBuilder.goalScope`).
enum GoalScope: Equatable, Sendable {
    case project(key: String, name: String)
    case ownWork(keys: Set<String>)
    case allFocus

    /// Project keys that count; nil = every block.
    var keys: Set<String>? {
        switch self {
        case .project(let key, _): [key]
        case .ownWork(let keys): keys
        case .allFocus: nil
        }
    }

    var isFiltered: Bool { keys != nil }

    /// The scope beside every goal number: "★ Learning", "Own work", "All focus".
    var label: String {
        switch self {
        case .project(_, let name): "★ \(name)"
        case .ownWork: "Own work"
        case .allFocus: "All focus"
        }
    }

    /// For sentences: "Learning", "your own work", "your focus".
    var phrase: String {
        switch self {
        case .project(_, let name): name
        case .ownWork: "your own work"
        case .allFocus: "your focus"
        }
    }

    /// What the goal counts, in one sentence (Goals tab, Settings no longer claims it).
    var countsSentence: String {
        switch self {
        case .project(_, let name): "Counts \(name), your ★ #1 project. Other projects don't fill it."
        case .ownWork: "Counts your own work: Personal and Learning projects. Work projects don't fill it."
        case .allFocus: "Counts every focus block. Rank a #1 project or mark one Work to narrow it."
        }
    }
}

/// The one daily goal: what it counts and how big it is today (`GoalDataBuilder.dailyGoal`).
struct DailyGoal: Equatable, Sendable {
    enum Source: Equatable, Sendable {
        /// The sum of today's targets of the counted projects.
        case projectTargets
        /// The fixed number set in Goals.
        case fixed
        /// Coach v8 §3.5: your target for today's day type (leave, weekend, holiday, sick).
        case dayType(DayType)
    }

    static let defaultSeconds: TimeInterval = 7200
    static let defaultStretchExtra: TimeInterval = 1800

    let scope: GoalScope
    let seconds: TimeInterval
    let stretchSeconds: TimeInterval
    let source: Source
    /// Today's targets of the counted projects added up; nil when none of them has one today.
    let targetSeconds: TimeInterval?
    let fixedSeconds: TimeInterval
    let followsTargets: Bool

    var label: String { scope.label }

    /// Stretch keeps its distance above the goal, so it moves with the targets.
    static func resolve(
        scope: GoalScope,
        targetMinutes: [Int],
        fixedSeconds: TimeInterval,
        stretchSeconds: TimeInterval,
        followsTargets: Bool
    ) -> DailyGoal {
        let fixed = max(60, fixedSeconds)
        let positive = targetMinutes.filter { $0 > 0 }
        let targets = positive.isEmpty ? nil : TimeInterval(positive.reduce(0, +) * 60)
        let useTargets = followsTargets && targets != nil
        let seconds = useTargets ? targets ?? fixed : fixed
        let extra = max(0, stretchSeconds - fixed)
        return DailyGoal(
            scope: scope,
            seconds: seconds,
            stretchSeconds: seconds + extra,
            source: useTargets ? .projectTargets : .fixed,
            targetSeconds: targets,
            fixedSeconds: fixed,
            followsTargets: followsTargets
        )
    }
}
