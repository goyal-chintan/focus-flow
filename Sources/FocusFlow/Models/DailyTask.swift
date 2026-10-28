import Foundation
import SwiftData

/// One to-do for one day (daily tasks design: docs/plans/2026-10-28-daily-tasks-design.md).
/// Linked to a key result, ticking it logs `amount` of goal progress; unticking removes that entry.
@Model
final class DailyTask {
    var id: UUID
    var title: String
    /// Start of the day the task is planned for.
    var day: Date
    var order: Int
    var isDone: Bool
    var doneAt: Date?
    var projectID: UUID?
    var keyResultID: UUID?
    /// Progress logged to the key result when ticked (nil = 1).
    var amount: Double?
    /// The `GoalProgressEntry` made on tick, so an untick removes exactly that.
    var progressEntryID: UUID?
    /// The block it was ticked in.
    var sessionID: UUID?
    /// The unfinished task this one was carried over from.
    var carriedFromID: UUID?
    var createdAt: Date

    init(title: String, day: Date, order: Int = 0, projectID: UUID? = nil, keyResultID: UUID? = nil, amount: Double? = nil) {
        self.id = UUID()
        self.title = title
        self.day = day
        self.order = order
        self.isDone = false
        self.projectID = projectID
        self.keyResultID = keyResultID
        self.amount = amount
        self.createdAt = Date()
    }

    var progressAmount: Double { max(1, amount ?? 1) }
}
