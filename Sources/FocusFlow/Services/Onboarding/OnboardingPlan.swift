import Foundation
import SwiftData

/// The welcome tour (onboarding design: docs/plans/2026-10-28-onboarding-design.md).
/// Five steps, one decision each. Nothing is written until the last step.
enum OnboardingStep: Int, CaseIterable, Comparable, Sendable {
    case welcome
    case priority
    case goal
    case coach
    case start

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    var next: OnboardingStep? { OnboardingStep(rawValue: rawValue + 1) }
    var previous: OnboardingStep? { OnboardingStep(rawValue: rawValue - 1) }
}

/// What to do about the tour at launch.
enum OnboardingLaunch: Equatable, Sendable {
    case show
    /// An existing store (sessions, no completion date): mark it done without showing anything.
    case markDone
    case none

    static func decide(completedAt: Date?, hasSessions: Bool) -> OnboardingLaunch {
        guard completedAt == nil else { return .none }
        return hasSessions ? .markDone : .show
    }
}

/// A one-tap starting point for the #1 project.
struct OnboardingProjectPreset: Identifiable, Hashable, Sendable {
    let name: String
    let area: ProjectArea
    let color: String
    let icon: String
    var id: String { name }

    static let all: [OnboardingProjectPreset] = [
        .init(name: "Interview prep", area: .learning, color: "purple", icon: "graduationcap.fill"),
        .init(name: "Side project", area: .personal, color: "orange", icon: "hammer.fill"),
        .init(name: "Writing", area: .personal, color: "teal", icon: "pencil.line"),
        .init(name: "Deep work", area: .work, color: "blue", icon: "briefcase.fill"),
    ]
}

/// A one-tap starting point for the goal's countable result.
struct OnboardingResultPreset: Identifiable, Hashable, Sendable {
    let title: String
    let target: Int
    var id: String { title }

    static func suggestions(for area: ProjectArea) -> [OnboardingResultPreset] {
        switch area {
        case .learning: [.init(title: "Practice problems", target: 60), .init(title: "Mock interviews", target: 6), .init(title: "Lessons", target: 20)]
        case .personal: [.init(title: "Features shipped", target: 10), .init(title: "Posts written", target: 8), .init(title: "Workouts", target: 16)]
        case .work: [.init(title: "Docs written", target: 4), .init(title: "Tickets closed", target: 30), .init(title: "Design reviews", target: 4)]
        case .other: [.init(title: "Sessions", target: 20), .init(title: "Pages", target: 100)]
        }
    }
}

/// The tour's answers. `commit` writes them in one go.
struct OnboardingDraft: Equatable {
    static let dailyMinuteOptions = [30, 60, 90, 120, 150]
    static let deadlineOptions: [(days: Int, label: String)] = [(14, "2 weeks"), (30, "1 month"), (90, "3 months")]
    static let colors = ["blue", "indigo", "purple", "pink", "red", "orange", "yellow", "green", "teal", "mint"]

    /// An existing project picked as #1 (nil = make a new one).
    var existingProjectID: UUID?
    var projectName = ""
    var area: ProjectArea = .learning
    var color = "purple"
    var icon = "graduationcap.fill"
    var dailyMinutes = 60

    var addsGoal = true
    var resultTitle = ""
    var resultTarget = 30
    var deadlineDays = 30

    var coachStyle: CoachStyle = .challenger
    var notchEnabled = true

    init() {}

    /// Pre-fills from the store when the tour runs again: the current #1 (or only) project and the saved choices.
    init(projects: [Project], settings: AppSettings?) {
        if let settings {
            coachStyle = settings.coachStyle
            notchEnabled = settings.notchCompanionEnabled ?? true
        }
        let ranked = projects.filter { !$0.archived && $0.priorityRank != nil }.min { ($0.priorityRank ?? .max) < ($1.priorityRank ?? .max) }
        if let top = ranked ?? (projects.count == 1 ? projects.first : nil) {
            select(top)
        }
    }

    var trimmedName: String { projectName.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedResult: String { resultTitle.trimmingCharacters(in: .whitespacesAndNewlines) }
    var hasGoal: Bool { addsGoal && !trimmedResult.isEmpty && resultTarget > 0 }

    mutating func select(_ project: Project) {
        existingProjectID = project.id
        projectName = project.name
        color = project.color
        icon = project.icon ?? project.area.symbol
        area = project.areaRaw == nil ? .personal : project.area
        if let minutes = project.dailyTargetMinutes, minutes > 0 { dailyMinutes = minutes }
    }

    mutating func startNewProject() {
        existingProjectID = nil
        projectName = ""
    }

    mutating func apply(_ preset: OnboardingProjectPreset) {
        existingProjectID = nil
        projectName = preset.name
        area = preset.area
        color = preset.color
        icon = preset.icon
    }

    mutating func apply(_ preset: OnboardingResultPreset) {
        resultTitle = preset.title
        resultTarget = preset.target
    }

    /// A kind change keeps a custom icon but swaps a kind's default one.
    mutating func setArea(_ newArea: ProjectArea) {
        if ProjectArea.allCases.contains(where: { $0.symbol == icon }) { icon = newArea.symbol }
        area = newArea
    }

    func canContinue(from step: OnboardingStep) -> Bool {
        switch step {
        case .priority: !trimmedName.isEmpty
        // "Skip goal" is the way past without one.
        case .goal: !trimmedResult.isEmpty && resultTarget > 0
        default: true
        }
    }

    // MARK: Previews

    var perDay: Double { Double(resultTarget) / Double(max(1, deadlineDays)) }

    /// Whole steps a day, rounded up the way `DailyLevers` rounds (3.0000001 stays 3).
    var dailyQuota: Int { max(1, Int((perDay - 0.01).rounded(.up))) }

    func deadline(from now: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: deadlineDays, to: calendar.startOfDay(for: now)) ?? now
    }

    /// "60 practice problems by 27 Nov".
    func goalTitle(now: Date, calendar: Calendar = .current) -> String {
        let date = deadline(from: now, calendar: calendar).formatted(.dateTime.day().month(.abbreviated))
        return "\(resultTarget) \(trimmedResult.lowercased()) by \(date)"
    }

    /// "2/day for 30 days" or "1 every 3 days for 3 months".
    var paceText: String {
        let span = Self.deadlineOptions.first { $0.days == deadlineDays }?.label ?? "\(deadlineDays) days"
        return "\(PaceFormat.rate(perDay)) for \(span)"
    }

    /// The unit for `count` items: "practice problems", or "practice problem" for one.
    func resultUnit(_ count: Int) -> String {
        let unit = trimmedResult.lowercased()
        guard count == 1, unit.hasSuffix("s"), !unit.hasSuffix("ss") else { return unit }
        if ["sses", "xes", "ches", "shes"].contains(where: unit.hasSuffix) { return String(unit.dropLast(2)) }
        return String(unit.dropLast())
    }

    /// What this coach style would say to you on day one, built from your own answers.
    func coachPreview(_ style: CoachStyle) -> (hook: String, line: String) {
        let name = trimmedName.isEmpty ? "your #1" : trimmedName
        guard hasGoal else {
            switch style {
            case .gentle: return ("Ready for 5 minutes on \(name)?", "Small is fine. Starting is the win.")
            case .data: return ("\(name): 0 of \(dailyMinutes) min today.", "A 15-minute block now puts you at 25%.")
            case .challenger: return ("\(name) won't move itself.", "5 minutes. Now. Then decide.")
            }
        }
        let quota = dailyQuota
        switch style {
        case .gentle:
            return ("Today's step: \(quota) \(resultUnit(quota))?", "Five minutes is enough to begin.")
        case .data:
            return ("\(trimmedResult): 0 of \(resultTarget) · \(PaceFormat.rate(perDay)) · \(deadlineDays)d left.", "One block now keeps you on pace.")
        case .challenger:
            return ("\(deadlineDays) days. \(resultTarget) \(resultUnit(resultTarget)).", "Today's lever: \(quota) \(resultUnit(quota)). Start the first one.")
        }
    }

    // MARK: Commit

    /// Writes the answers: the #1 project (new or existing, rank 1), its goal, the coach style and the notch
    /// choice, and marks the tour done. Uses the same draft types as the forms. Returns the #1 project.
    @MainActor
    @discardableResult
    func commit(projects: [Project], goals: [ProjectGoal], settings: AppSettings, in context: ModelContext, now: Date = Date()) -> Project? {
        var top: Project?
        if !trimmedName.isEmpty {
            let project = existingProjectID.flatMap { id in projects.first { $0.id == id } } ?? {
                let created = Project(name: trimmedName, color: color, icon: icon)
                context.insert(created)
                return created
            }()
            var draft = ProjectDraft(project: project)
            draft.name = trimmedName
            draft.color = color
            draft.icon = icon
            draft.area = area
            draft.rank = 1
            draft.dailyTargetMinutes = dailyMinutes
            draft.weekdaysOnly = area == .work
            draft.apply(to: project, others: projects, in: context)
            top = project

            if hasGoal {
                var goal = GoalDraft(projectID: project.id)
                goal.title = goalTitle(now: now)
                goal.startDate = Calendar.current.startOfDay(for: now)
                goal.deadline = deadline(from: now)
                goal.isBossFight = !goals.contains { $0.status == .active && $0.isBossFight }
                goal.keyResults = [.init(title: trimmedResult, kind: .count, target: Double(resultTarget))]
                goal.apply(in: context, existing: nil)
            }
            // Own work sets the daily goal the ring, notch and coach pace against.
            if area.isOwnWork {
                settings.dailyFocusGoal = TimeInterval(dailyMinutes * 60)
                settings.dailyStretchGoal = max(settings.dailyStretchGoal, settings.dailyFocusGoal)
            }
        }
        settings.coachStyleRawValue = coachStyle.rawValue
        settings.notchCompanionEnabled = notchEnabled
        settings.onboardingCompletedAt = now
        try? context.save()
        return top
    }
}
