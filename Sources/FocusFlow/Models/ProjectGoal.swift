import Foundation
import SwiftData

/// A goal with a deadline, measured by key results (priorities-goals design §3.2).
/// "Apply for jobs by 28 Nov": 60 LeetCode, 10 SQL, 3 referrals, applied.
@Model
final class ProjectGoal {
    var id: UUID
    var title: String
    var projectID: UUID?
    var why: String?
    var startDate: Date
    var deadline: Date
    var statusRaw: String
    /// This month's main goal (Dan Koe's "boss fight").
    var isBossFight: Bool
    var order: Int
    var createdAt: Date
    var completedAt: Date?
    @Relationship(deleteRule: .cascade, inverse: \GoalKeyResult.goal)
    var keyResults: [GoalKeyResult]

    init(title: String, projectID: UUID?, startDate: Date = Date(), deadline: Date, isBossFight: Bool = false, order: Int = 0) {
        self.id = UUID()
        self.title = title
        self.projectID = projectID
        self.startDate = startDate
        self.deadline = deadline
        self.statusRaw = GoalStatus.active.rawValue
        self.isBossFight = isBossFight
        self.order = order
        self.createdAt = Date()
        self.keyResults = []
    }

    var status: GoalStatus {
        get { GoalStatus(rawValue: statusRaw) ?? .active }
        set {
            statusRaw = newValue.rawValue
            completedAt = newValue == .active ? nil : (completedAt ?? Date())
        }
    }

    var sortedKeyResults: [GoalKeyResult] { keyResults.sorted { $0.order < $1.order } }
}

enum GoalStatus: String, CaseIterable, Codable, Sendable {
    case active
    case done
    case dropped
}

/// One measurable result: a count ("60 questions") or a checkbox ("Applied").
@Model
final class GoalKeyResult {
    var id: UUID
    var title: String
    var kindRaw: String
    /// Count target (1 for a checkbox).
    var target: Double
    /// "questions", "referrals". Nil for a checkbox.
    var unit: String?
    var order: Int
    var goal: ProjectGoal?
    @Relationship(deleteRule: .cascade, inverse: \GoalProgressEntry.keyResult)
    var entries: [GoalProgressEntry]

    init(title: String, kind: GoalKeyResultKind, target: Double, unit: String? = nil, order: Int = 0) {
        self.id = UUID()
        self.title = title
        self.kindRaw = kind.rawValue
        self.target = kind == .checkbox ? 1 : max(1, target)
        self.unit = unit
        self.order = order
        self.entries = []
    }

    var kind: GoalKeyResultKind { GoalKeyResultKind(rawValue: kindRaw) ?? .count }

    /// Sum of logged progress (never below 0).
    var done: Double { max(0, entries.reduce(0) { $0 + $1.amount }) }
}

enum GoalKeyResultKind: String, CaseIterable, Codable, Sendable {
    case count
    case checkbox
}

/// One logged step of progress. Progress is the sum of entries, so it has a history.
@Model
final class GoalProgressEntry {
    var id: UUID
    var amount: Double
    var at: Date
    var note: String?
    /// The focus block it came from, when logged at the end of a session.
    var sessionID: UUID?
    var keyResult: GoalKeyResult?

    init(amount: Double, at: Date = Date(), note: String? = nil, sessionID: UUID? = nil) {
        self.id = UUID()
        self.amount = amount
        self.at = at
        self.note = note
        self.sessionID = sessionID
    }
}
