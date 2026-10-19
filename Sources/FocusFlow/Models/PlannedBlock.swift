import Foundation
import SwiftData

/// A start time the user committed to (Coach v3 §3.1): an implementation intention.
/// "When it is 22:00, I will start 50 minutes on the draft."
@Model
final class PlannedBlock {
    var id: UUID
    /// Start of the calendar day this block belongs to.
    var day: Date
    /// When the cue shows. Pushing the block moves this forward.
    var startAt: Date
    var minutes: Int
    var title: String?
    var priorityID: UUID?
    var projectID: UUID?
    var statusRawValue: String
    /// How often the user pushed it ("Push 15 min", ✕).
    var pushes: Int
    /// When the cue was last shown.
    var cuedAt: Date?
    /// The session that fulfilled it.
    var sessionID: UUID?
    var createdAt: Date

    var status: PlannedBlockStatus {
        get { PlannedBlockStatus(rawValue: statusRawValue) ?? .planned }
        set { statusRawValue = newValue.rawValue }
    }

    init(
        startAt: Date,
        minutes: Int,
        title: String? = nil,
        priorityID: UUID? = nil,
        projectID: UUID? = nil,
        calendar: Calendar = .current,
        createdAt: Date = Date()
    ) {
        self.id = UUID()
        self.day = calendar.startOfDay(for: startAt)
        self.startAt = startAt
        self.minutes = minutes
        self.title = title
        self.priorityID = priorityID
        self.projectID = projectID
        self.statusRawValue = PlannedBlockStatus.planned.rawValue
        self.pushes = 0
        self.createdAt = createdAt
    }
}

enum PlannedBlockStatus: String, Codable, CaseIterable, Sendable {
    case planned
    /// A focus block started within the start window.
    case started
    /// "Skip today" or "Done for today".
    case skipped
    /// The start window passed, or it was pushed too often.
    case missed
}
