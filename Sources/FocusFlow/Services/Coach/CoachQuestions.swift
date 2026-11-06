import Foundation

// Coach v6 §3.4: when the coach is unsure, it asks one short question with one-tap answers, and
// the answer changes what it does now. At most one question a day, never during a block, a share
// or quiet hours, and only with someone at the desk.

struct CoachQuestionChoice: Equatable, Sendable, Identifiable {
    let id: String
    let title: String
}

enum CoachQuestion: Equatable, Sendable {
    /// The declared own-work windows miss when blocks actually start (`CoachWindowFit`).
    case windowFit(CoachWindowFit, declared: [CoachOwnWorkWindow])
    /// A busy project has no area, so the coach can't tell whether it is own work and leaves its
    /// blocks out of everything it learns (ProjectWork: 31 blocks on 6 Nov 2026).
    case projectArea(projectID: UUID, name: String, blocks: Int)
    /// Coach v7 §3.1: blocks keep running past the usual length while you focus.
    case naturalLength(minutes: Int, regular: Int)
    /// Coach v8 §3.1: a quiet weekday. Leave, holiday, or a quiet workday?
    case dayType(day: Date, inferred: DayType, reason: String)

    var id: String {
        switch self {
        case .windowFit: "window_fit"
        case .projectArea(let id, _, _): "project_area.\(id.uuidString)"
        case .naturalLength: "natural_length"
        case .dayType(let day, _, _): "day_type.\(Int(day.timeIntervalSince1970))"
        }
    }

    var hook: String {
        switch self {
        case .windowFit:
            "Should I watch the hours you actually work?"
        case .projectArea(_, let name, _):
            "Is \(name) your own work, or your day job?"
        case .naturalLength(let minutes, _):
            "Your blocks run about \(minutes) min. Make \(minutes) your usual?"
        case .dayType:
            "No Slack or calls today. On leave?"
        }
    }

    var detail: String {
        switch self {
        case .windowFit(let fit, _):
            // Two lines in the panel: compact hours, then the miss.
            "You start around \(fit.observedShortLabel). Your set windows caught \(fit.covered) of \(fit.starts) starts."
        case .projectArea(_, let name, let blocks):
            "\(name) has \(blocks) blocks in 4 weeks but no area, so I leave them out of your goal and what I learn."
        case .naturalLength(_, let regular):
            "Most of your recent \(regular)m blocks ran 8+ min over while you focused. A block that ends where you planned beats a \(regular) you always stretch."
        case .dayType:
            "It sets today's own-work target: 3h on leave, 1h 30m on a workday."
        }
    }

    var choices: [CoachQuestionChoice] {
        switch self {
        case .windowFit:
            [
                CoachQuestionChoice(id: WindowFitAnswer.useObserved.rawValue, title: "Use these hours"),
                CoachQuestionChoice(id: WindowFitAnswer.addObserved.rawValue, title: "Add them to mine"),
                CoachQuestionChoice(id: WindowFitAnswer.keepMine.rawValue, title: "Keep my windows"),
            ]
        case .projectArea:
            [
                CoachQuestionChoice(id: ProjectArea.personal.rawValue, title: "My own work"),
                CoachQuestionChoice(id: ProjectArea.learning.rawValue, title: "Learning"),
                CoachQuestionChoice(id: ProjectArea.work.rawValue, title: "Day job"),
            ]
        case .naturalLength(let minutes, let regular):
            [
                CoachQuestionChoice(id: "\(minutes)", title: "Make it \(minutes) min"),
                CoachQuestionChoice(id: "keep", title: "Keep \(regular) min"),
            ]
        case .dayType:
            [
                CoachQuestionChoice(id: DayType.leave.rawValue, title: "Yes, on leave"),
                CoachQuestionChoice(id: DayType.holiday.rawValue, title: "A holiday"),
                CoachQuestionChoice(id: DayType.workday.rawValue, title: "Working, just quiet"),
                CoachQuestionChoice(id: DayType.sick.rawValue, title: "Sick day"),
            ]
        }
    }

    enum WindowFitAnswer: String, Sendable {
        case useObserved = "use"
        case addObserved = "add"
        case keepMine = "keep"
    }

    /// The windows to save for an answer; nil keeps the declared ones as they are.
    static func windows(after answer: WindowFitAnswer, declared: [CoachOwnWorkWindow], fit: CoachWindowFit) -> [CoachOwnWorkWindow]? {
        switch answer {
        case .useObserved: CoachOwnWorkWindows.normalized(fit.observed)
        case .addObserved: CoachOwnWorkWindows.normalized(declared + fit.additions(to: declared))
        case .keepMine: nil
        }
    }
}

/// When a question may be asked. Pure, so the limits are unit-tested.
enum CoachQuestionPolicy {
    /// After "Not now" the same question waits this long.
    static let notNowCooldown: TimeInterval = 3 * 86_400
    /// After "Keep my windows" the window question waits this long.
    static let keepMineCooldown: TimeInterval = 14 * 86_400
    static let maxIdleSeconds: TimeInterval = 60

    struct Input: Sendable {
        var now: Date
        var askedToday: Bool
        var sessionActive: Bool
        var panelShowing: Bool
        var quietHours: Bool
        var screenShare: Bool
        var userIdleSeconds: TimeInterval
        var questionSnoozedUntil: Date?
    }

    static func mayAsk(_ input: Input) -> Bool {
        guard !input.askedToday, !input.sessionActive, !input.panelShowing, !input.quietHours,
              !input.screenShare, input.userIdleSeconds <= maxIdleSeconds else { return false }
        if let until = input.questionSnoozedUntil, until > input.now { return false }
        return true
    }
}

/// Per-question state in defaults: the day of the last question, and each question's snooze.
struct CoachQuestionStore {
    static let askedDayKey = "focusflow.coachQuestion.askedDay"
    static func snoozeKey(_ id: String) -> String { "focusflow.coachQuestion.snoozedUntil.\(id)" }

    let defaults: UserDefaults

    func askedToday(now: Date, calendar: Calendar = .current) -> Bool {
        guard let day = defaults.object(forKey: Self.askedDayKey) as? Date else { return false }
        return calendar.isDate(day, inSameDayAs: now)
    }

    func markAsked(now: Date) { defaults.set(now, forKey: Self.askedDayKey) }

    func snoozedUntil(_ id: String) -> Date? { defaults.object(forKey: Self.snoozeKey(id)) as? Date }

    func snooze(_ id: String, until: Date) { defaults.set(until, forKey: Self.snoozeKey(id)) }
}

extension CoachQuestion {
    /// The busiest active project with no area, once any project is marked Work (only then does
    /// "own work" filter anything). Needs `minBlocks` blocks in the lookback.
    static let minProjectBlocks = 5

    static func unclassifiedProject(_ projects: [(id: UUID, name: String, hasArea: Bool, isWork: Bool, blocks: Int)]) -> CoachQuestion? {
        guard projects.contains(where: \.isWork) else { return nil }
        guard let busiest = projects.filter({ !$0.hasArea && $0.blocks >= minProjectBlocks }).max(by: { $0.blocks < $1.blocks }) else { return nil }
        return .projectArea(projectID: busiest.id, name: busiest.name, blocks: busiest.blocks)
    }
}
