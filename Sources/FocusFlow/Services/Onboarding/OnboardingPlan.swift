import Foundation
import SwiftData

/// The welcome tour (onboarding v2: docs/plans/2026-10-31-onboarding-v2-design.md).
/// The coach meets you, then asks for your direction, how to measure it, your rhythm and how to
/// coach you (§3.5). Nothing is written until the last screen.
enum OnboardingStep: Int, CaseIterable, Comparable, Sendable {
    case meet
    case what
    case measure
    case when
    case plan

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

/// A life goal to start from: its kind, colour, what to count, first steps and a "why" hint.
struct OnboardingProjectPreset: Identifiable, Hashable, Sendable {
    let name: String
    let area: ProjectArea
    let color: String
    let icon: String
    let results: [OnboardingResultPreset]
    let firstSteps: [String]
    let whyHint: String
    var id: String { name }

    static let all: [OnboardingProjectPreset] = [
        .init(name: "Land a better job", area: .learning, color: "blue", icon: "briefcase.fill",
              results: [.init(title: "Practice problems", target: 60), .init(title: "Mock interviews", target: 6)],
              firstSteps: ["Solve 2 easy problems", "Update my CV", "Practise one answer out loud"],
              whyHint: "Work I'm proud of, paid what it's worth"),
        .init(name: "Ship my side project", area: .personal, color: "orange", icon: "hammer.fill",
              results: [.init(title: "Features shipped", target: 10), .init(title: "Users", target: 50)],
              firstSteps: ["Fix one small bug", "Ship one tiny feature", "Write the README"],
              whyHint: "Something of my own, out in the world"),
        .init(name: "Learn a new skill", area: .learning, color: "teal", icon: "graduationcap.fill",
              results: [.init(title: "Lessons", target: 20), .init(title: "Projects built", target: 3)],
              firstSteps: ["Finish one lesson", "Build a tiny example", "Take notes on one topic"],
              whyHint: "Better at something I care about"),
        .init(name: "Write every week", area: .personal, color: "pink", icon: "pencil.line",
              results: [.init(title: "Posts written", target: 8), .init(title: "Drafts", target: 12)],
              firstSteps: ["Write the first paragraph", "Outline one post", "Edit yesterday's draft"],
              whyHint: "Think clearly, in public"),
        .init(name: "Read more books", area: .personal, color: "green", icon: "book.fill",
              results: [.init(title: "Books", target: 6), .init(title: "Chapters", target: 40)],
              firstSteps: ["Read 20 pages", "Notes on one chapter"],
              whyHint: "A wider mind, a calmer evening"),
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

/// A time of day people often have free. None starts inside the default quiet hours (00:30–07:00),
/// and none wraps past midnight (own-work windows never do).
struct OnboardingWindowPreset: Identifiable, Hashable, Sendable {
    let title: String
    let symbol: String
    let window: CoachOwnWorkWindow
    var id: Int { window.id }

    static let all: [OnboardingWindowPreset] = [
        .init(title: "Early morning", symbol: "sunrise.fill", window: .init(startMinute: 7 * 60, endMinute: 9 * 60)),
        .init(title: "Lunch break", symbol: "fork.knife", window: .init(startMinute: 12 * 60, endMinute: 13 * 60 + 30)),
        .init(title: "After work", symbol: "figure.walk", window: .init(startMinute: 18 * 60, endMinute: 20 * 60)),
        .init(title: "Evening", symbol: "sunset.fill", window: .init(startMinute: 20 * 60, endMinute: 22 * 60)),
        .init(title: "Late night", symbol: "moon.stars.fill", window: .init(startMinute: 22 * 60, endMinute: 24 * 60)),
    ]

    /// The preset you're in right now (people often install in a free moment), else Evening.
    static func suggested(now: Date, calendar: Calendar = .current) -> OnboardingWindowPreset {
        all.first { $0.window.contains(now, calendar: calendar) } ?? all[3]
    }
}

/// How the tour ends, from the clock and the chosen windows.
enum OnboardingEnding: Equatable, Sendable {
    /// Inside a window, or one starts within `startLead`: start a block now.
    case startNow(CoachOwnWorkWindow)
    /// Otherwise plan a block at the next window's start.
    case planAt(Date)
    /// No windows chosen.
    case none

    static let startLead: TimeInterval = 10 * 60
}

/// The tour's answers. `commit` writes them in one go.
struct OnboardingDraft: Equatable {
    static let dailyMinuteOptions = [30, 60, 90, 120, 180]
    static let deadlineOptions: [(days: Int, label: String)] = [(14, "2 weeks"), (30, "1 month"), (90, "3 months")]
    static let colors = ["blue", "orange", "teal", "green", "pink", "indigo", "red", "yellow", "mint"]

    /// An existing project picked as #1 (nil = make a new one).
    var existingProjectID: UUID?
    var projectName = ""
    var area: ProjectArea = .personal
    var color = "blue"
    var icon = ProjectArea.personal.symbol
    /// Set by a preset, an existing project or the "Counts as" menu; until then the kind follows the name.
    var areaChosen = false
    /// One line for the project's purpose and the coach's "My why".
    var why = ""

    var windows: [CoachOwnWorkWindow]
    var dailyMinutes = 60

    var firstStep = ""
    /// Tracking the goal is the coach's job, so it is on by default; "Decide later" turns it off.
    var tracksNumber = true
    var resultTitle = ""
    var resultTarget = 30
    var deadlineDays = 30

    var coachStyle: CoachStyle = .challenger

    init(now: Date = Date()) {
        windows = [OnboardingWindowPreset.suggested(now: now).window]
    }

    /// Pre-fills from the store when the tour runs again: the current #1 (or only) project and the saved choices.
    init(projects: [Project], settings: AppSettings?, now: Date = Date()) {
        self.init(now: now)
        if let settings {
            coachStyle = settings.coachStyle
            if !settings.coachOwnWorkWindows.isEmpty { windows = settings.coachOwnWorkWindows }
        }
        let ranked = projects.filter { !$0.archived && $0.priorityRank != nil }.min { ($0.priorityRank ?? .max) < ($1.priorityRank ?? .max) }
        if let top = ranked ?? (projects.count == 1 ? projects.first : nil) {
            select(top)
        }
    }

    var trimmedName: String { projectName.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedWhy: String { why.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedFirstStep: String { firstStep.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedResult: String { resultTitle.trimmingCharacters(in: .whitespacesAndNewlines) }
    var hasGoal: Bool { tracksNumber && !trimmedResult.isEmpty && resultTarget > 0 }

    /// The preset this draft was started from, if the name still matches it.
    var preset: OnboardingProjectPreset? { OnboardingProjectPreset.all.first { $0.name == trimmedName } }

    mutating func select(_ project: Project) {
        existingProjectID = project.id
        projectName = project.name
        color = project.color
        icon = project.icon ?? project.area.symbol
        area = project.areaRaw == nil ? .personal : project.area
        areaChosen = true
        why = project.purpose ?? ""
        if let minutes = project.dailyTargetMinutes, minutes > 0 { dailyMinutes = minutes }
    }

    mutating func startNewProject() {
        existingProjectID = nil
        projectName = ""
        why = ""
        areaChosen = false
    }

    mutating func apply(_ preset: OnboardingProjectPreset) {
        existingProjectID = nil
        projectName = preset.name
        area = preset.area
        color = preset.color
        icon = preset.icon
        areaChosen = true
        if let result = preset.results.first { apply(result) }
    }

    mutating func apply(_ preset: OnboardingResultPreset) {
        resultTitle = preset.title
        resultTarget = preset.target
    }

    /// A kind change keeps a custom icon but swaps a kind's default one.
    mutating func setArea(_ newArea: ProjectArea, chosen: Bool = true) {
        if ProjectArea.allCases.contains(where: { $0.symbol == icon }) { icon = newArea.symbol }
        area = newArea
        if chosen { areaChosen = true }
    }

    /// Typing a new name: the kind follows the words until you pick one.
    mutating func nameChanged() {
        guard existingProjectID == nil, !areaChosen else { return }
        setArea(Self.inferArea(from: trimmedName), chosen: false)
    }

    static func inferArea(from name: String) -> ProjectArea {
        let words = name.lowercased()
        // Only your day job counts as Work; a job search ("Land a better job") is your own work.
        let work = ["office", "client", "day job", "my team", "meeting"]
        let learning = ["interview", "leetcode", "study", "course", "learn", "exam", "sql", "prep", "class", "lesson",
                        "language", "dsa", "certif", "job", "career", "skill"]
        if work.contains(where: words.contains) { return .work }
        if learning.contains(where: words.contains) { return .learning }
        return .personal
    }

    /// The first colour no other project uses, so a new #1 stands out.
    static func freshColor(avoiding used: [String]) -> String {
        colors.first { !used.contains($0) } ?? "blue"
    }

    /// The colour the #1 will have once saved: its own, a suggestion's, or the first free one.
    func markColor(avoiding used: [String]) -> String {
        existingProjectID != nil || preset != nil ? color : Self.freshColor(avoiding: used)
    }

    static func symbol(_ style: CoachStyle) -> String {
        switch style {
        case .gentle: "leaf.fill"
        case .data: "chart.bar.fill"
        case .challenger: "flame.fill"
        }
    }

    var whyHint: String {
        if let preset { return preset.whyHint }
        switch area {
        case .learning: return "Ready for a better role by March"
        case .work: return "Known for doing the deep work"
        case .personal, .other: return "Something of my own, finished"
        }
    }

    /// What to count: the goal's own suggestions, else ones for its kind.
    var resultSuggestions: [OnboardingResultPreset] {
        preset?.results ?? OnboardingResultPreset.suggestions(for: area)
    }

    var firstStepSuggestions: [String] {
        if let preset { return preset.firstSteps }
        switch area {
        case .learning: return ["Solve 2 easy problems", "Watch one lesson, take notes"]
        case .work: return ["Outline the doc", "Clear one hard ticket"]
        case .personal, .other: return ["Sketch the plan", "Do the first small piece"]
        }
    }

    // MARK: Windows

    mutating func toggle(_ window: CoachOwnWorkWindow) {
        if windows.contains(window) {
            windows.removeAll { $0 == window }
        } else {
            windows = CoachOwnWorkWindows.normalized(windows + [window])
        }
    }

    /// Adds a custom window; one that overlaps a chosen one replaces it.
    mutating func addCustom(_ window: CoachOwnWorkWindow) {
        let kept = windows.filter { $0.endMinute <= window.startMinute || $0.startMinute >= window.endMinute }
        windows = CoachOwnWorkWindows.normalized(kept + [window])
    }

    var canAddWindow: Bool { windows.count < CoachOwnWorkWindows.maxWindows }

    var windowMinutes: Int { windows.reduce(0) { $0 + $1.durationMinutes } }

    /// More time a day than the chosen windows hold.
    var exceedsWindows: Bool { !windows.isEmpty && dailyMinutes > windowMinutes }

    /// "22:00–00:00": own-work windows end at 24:00, which reads better as midnight.
    static func label(_ window: CoachOwnWorkWindow) -> String {
        window.label.replacingOccurrences(of: "24:00", with: "00:00")
    }

    var windowsLabel: String { windows.map(Self.label).joined(separator: " and ") }

    /// "Every day 22:00–00:00 · 1h → 7h a week on Interview prep".
    var weekLine: String {
        let days = area == .work ? 5 : 7
        let span = area == .work ? "Weekdays" : "Every day"
        let week = FFFormat.duration(TimeInterval(dailyMinutes * days * 60))
        let on = trimmedName.isEmpty ? "" : " on \(trimmedName)"
        return "\(span) \(windowsLabel) · \(FFFormat.duration(TimeInterval(dailyMinutes * 60))) → \(week) a week\(on)"
    }

    // MARK: Ending

    func ending(now: Date, calendar: Calendar = .current) -> OnboardingEnding {
        guard !windows.isEmpty else { return .none }
        for window in windows {
            let interval = window.interval(on: now, calendar: calendar)
            if now >= interval.start.addingTimeInterval(-OnboardingEnding.startLead) && now < interval.end {
                return .startNow(window)
            }
        }
        if let later = windows.map({ $0.interval(on: now, calendar: calendar).start }).filter({ $0 > now }).min() {
            return .planAt(later)
        }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        return .planAt(windows[0].interval(on: tomorrow, calendar: calendar).start)
    }

    /// "tonight at 22:00", "today at 12:00", "tomorrow at 07:00".
    static func when(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let clock = CoachOwnWorkWindow.clock(calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date))
        if calendar.isDate(date, inSameDayAs: now) {
            return calendar.component(.hour, from: date) >= 18 ? "tonight at \(clock)" : "today at \(clock)"
        }
        return "tomorrow at \(clock)"
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

    /// The first step as the coach will name it: what you typed, else today's count for the goal.
    var stepTitle: String? {
        if !trimmedFirstStep.isEmpty { return trimmedFirstStep }
        guard hasGoal else { return nil }
        // A counted task is named for what you count ("Problems solved", counter "0 of 3"),
        // never as a finished state ("3 problems solved").
        return dailyQuota > 1 ? trimmedResult : "\(dailyQuota) \(resultUnit(dailyQuota))"
    }

    func canContinue(from step: OnboardingStep) -> Bool {
        switch step {
        case .what: !trimmedName.isEmpty
        case .when: !windows.isEmpty
        case .meet, .measure, .plan: true
        }
    }

    // MARK: Commit

    /// Writes the answers: the #1 project (new or existing, rank 1, its why and daily time), the
    /// own-work windows, the first step as today's task, the goal when a number is tracked, a planned
    /// block at `planStart`, the coach style, and marks the tour done. Uses the same draft types as
    /// the forms. Returns the #1 project.
    @MainActor
    @discardableResult
    func commit(projects: [Project], goals: [ProjectGoal], settings: AppSettings, in context: ModelContext,
                now: Date = Date(), planStart: Date? = nil, blockMinutes: Int = 25) -> Project? {
        var top: Project?
        let today = Calendar.current.startOfDay(for: now)
        if !trimmedName.isEmpty {
            let existing = existingProjectID.flatMap { id in projects.first { $0.id == id } }
            let newColor = markColor(avoiding: projects.map(\.color))
            let project = existing ?? {
                let created = Project(name: trimmedName, color: newColor, icon: icon)
                context.insert(created)
                return created
            }()
            var draft = ProjectDraft(project: project)
            draft.name = trimmedName
            draft.color = existing == nil ? newColor : color
            draft.icon = icon
            draft.area = area
            draft.rank = 1
            draft.dailyTargetMinutes = dailyMinutes
            draft.weekdaysOnly = area == .work
            draft.purpose = trimmedWhy
            draft.apply(to: project, others: projects, in: context)
            top = project

            var resultID: UUID?
            if hasGoal {
                var goal = GoalDraft(projectID: project.id)
                goal.title = goalTitle(now: now)
                goal.startDate = today
                goal.deadline = deadline(from: now)
                goal.isBossFight = !goals.contains { $0.status == .active && $0.isBossFight }
                goal.keyResults = [.init(title: trimmedResult, target: Double(resultTarget))]
                resultID = goal.apply(in: context, existing: nil).sortedKeyResults.first?.id
            }
            // The first step is today's task; with a goal it is linked, so each +1 moves the goal.
            if let title = stepTitle {
                let todays = ((try? context.fetch(FetchDescriptor<DailyTask>())) ?? []).filter { $0.day == today }
                if !todays.contains(where: { $0.projectID == project.id && $0.title == title }) {
                    let task = DailyTask(title: title, day: today, order: (todays.map(\.order).max() ?? -1) + 1,
                                         projectID: project.id, keyResultID: resultID,
                                         amount: resultID == nil ? nil : Double(dailyQuota))
                    context.insert(task)
                }
            }
            if let planStart {
                let planned = (try? context.fetch(FetchDescriptor<PlannedBlock>())) ?? []
                if !planned.contains(where: { $0.startAt == planStart && $0.status == .planned }) {
                    context.insert(PlannedBlock(startAt: planStart, minutes: blockMinutes, title: project.name, projectID: project.id, createdAt: now))
                }
            }
            // Own work sets the daily goal the ring, notch and coach pace against.
            if area.isOwnWork {
                settings.dailyFocusGoal = TimeInterval(dailyMinutes * 60)
                settings.dailyStretchGoal = max(settings.dailyStretchGoal, settings.dailyFocusGoal)
            }
        }
        if !windows.isEmpty { settings.coachOwnWorkWindows = windows }
        // The why also becomes a "My why" line the coach quotes back (at most 5 lines).
        if !trimmedWhy.isEmpty,
           !settings.coachMyWhyLines.contains(where: { $0.caseInsensitiveCompare(trimmedWhy) == .orderedSame }),
           settings.coachMyWhyLines.count < 5 {
            settings.coachMyWhyText = (settings.coachMyWhyLines + [trimmedWhy]).joined(separator: "\n")
        }
        settings.coachStyleRawValue = coachStyle.rawValue
        // The pause screen is Challenger's; Gentle and Data start with it off (rescue-loop design §3).
        settings.coachPauseScreenEnabled = coachStyle == .challenger
        settings.onboardingCompletedAt = now
        try? context.save()
        return top
    }
}
