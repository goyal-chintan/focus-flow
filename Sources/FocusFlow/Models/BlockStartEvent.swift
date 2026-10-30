import Foundation
import SwiftData

/// One row per focus block start, kept whatever happens to the block's session (coach audit
/// 2026-10-30). Sessions under 5 minutes are deleted from history, and 7 of 17 starts vanished
/// with them, so the coach scored prompts that worked as failures. Coach rewards and
/// prompt→start read these rows; the sessions table stays the history the user sees.
@Model
final class BlockStartEvent {
    var id: UUID
    /// The session the block started as (it may since have been deleted).
    var sessionID: UUID
    var startedAt: Date
    /// The length the block was started at.
    var plannedMinutes: Int
    var projectID: UUID?
    /// Whether the block counted as own work when it started; used when the project is gone.
    var ownWorkAtStart: Bool
    /// Focused seconds, written when the session ends or is deleted. Nil while it runs.
    var focusedSeconds: Double?
    /// The prompt credited with this start (nil: started on your own).
    var promptAttemptID: UUID?

    init(
        sessionID: UUID,
        startedAt: Date,
        plannedMinutes: Int,
        projectID: UUID?,
        ownWorkAtStart: Bool,
        promptAttemptID: UUID? = nil
    ) {
        self.id = UUID()
        self.sessionID = sessionID
        self.startedAt = startedAt
        self.plannedMinutes = plannedMinutes
        self.projectID = projectID
        self.ownWorkAtStart = ownWorkAtStart
        self.promptAttemptID = promptAttemptID
    }
}
