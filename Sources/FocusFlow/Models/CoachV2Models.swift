import Foundation
import SwiftData

// Shared data contract for Coach v2 and the analytics redesign.
// Design: docs/plans/2026-10-17-coach-v2-learning-motivation-design.md

/// How the coach talks. Picked by the user in Settings → Coach.
enum CoachStyle: String, CaseIterable, Codable, Sendable {
    case gentle
    case data
    case challenger

    var displayName: String {
        switch self {
        case .gentle: "Gentle"
        case .data: "Data"
        case .challenger: "Challenger"
        }
    }
}

/// Where a coach prompt was shown. `silent` is the bandit's "do nothing" arm.
enum CoachSurface: String, CaseIterable, Codable, Sendable {
    case silent
    case badge
    case panel
    case notification
    case strongWindow
}

/// The user's own rating of a finished focus block (pseudo-productivity guard).
enum SessionOutcome: String, CaseIterable, Codable, Sendable {
    case shipped
    case movedForward
    case busywork

    var displayName: String {
        switch self {
        case .shipped: "Shipped"
        case .movedForward: "Moved it forward"
        case .busywork: "Busywork"
        }
    }

    /// Contribution to the coach's learning reward.
    var reward: Double {
        switch self {
        case .shipped, .movedForward: 0.5
        case .busywork: -0.5
        }
    }
}

/// One of the user's 1–3 personal outcomes for a week.
@Model
final class WeeklyPriority {
    var id: UUID
    var title: String
    /// Start of the ISO week (local calendar) this priority belongs to.
    var weekStart: Date
    var order: Int
    var isDone: Bool
    var projectID: UUID?
    var createdAt: Date

    init(title: String, weekStart: Date, order: Int, projectID: UUID? = nil) {
        self.id = UUID()
        self.title = title
        self.weekStart = weekStart
        self.order = order
        self.isDone = false
        self.projectID = projectID
        self.createdAt = Date()
    }

    /// Start of the week containing `date`, using the user's calendar.
    static func weekStart(for date: Date, calendar: Calendar = .current) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }
}
