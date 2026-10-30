import Foundation
import SwiftData

/// One to-do for one day (daily tasks design: docs/plans/2026-10-28-daily-tasks-design.md).
/// Linked to a key result, ticking it logs `amount` of goal progress; unticking removes it.
/// A linked task with an amount above 1 is *counted* ("Problems solved 1 of 3"): each +1 is its
/// own goal entry, and the task is done when the count reaches the amount (clarity design 2026-10-28).
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
    /// The `GoalProgressEntry` made on tick by builds before counted tasks. Newer entries carry
    /// `GoalProgressEntry.taskID` instead; the first change adopts this one.
    var progressEntryID: UUID?
    /// Progress logged through this task so far (nil until the first change after this column).
    var loggedAmount: Double?
    /// The block it was ticked in.
    var sessionID: UUID?
    /// The unfinished task this one was carried over from.
    var carriedFromID: UUID?
    /// The Apple Reminder (`calendarItemIdentifier`) this task mirrors, when its project syncs a list.
    var reminderID: String?
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

    /// Linked and more than one: shown as a counter with +1, not a single tick.
    var isCounted: Bool { keyResultID != nil && progressAmount > 1 }

    /// How much of `progressAmount` is logged (a done task from before this column counts as full).
    var loggedCount: Double { loggedAmount ?? (isDone ? progressAmount : 0) }
}
