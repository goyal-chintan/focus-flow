import Foundation
import SwiftData

@Model
final class FocusSession {
    var id: UUID
    var project: Project?
    var customLabel: String?
    var type: SessionType
    var duration: TimeInterval
    var startedAt: Date
    var endedAt: Date?
    var completed: Bool
    var moodRawValue: String?
    var achievement: String?
    var calendarEventId: String?

    /// Total wall-clock seconds spent paused during this session.
    /// Accumulated each time the user resumes or the session ends while paused.
    /// Default is 0 so existing stored sessions are unaffected.
    var totalPausedSeconds: TimeInterval = 0

    @Relationship(deleteRule: .cascade)
    var splits: [TimeSplit]

    var mood: FocusMood? {
        get { moodRawValue.flatMap { FocusMood(rawValue: $0) } }
        set { moodRawValue = newValue?.rawValue }
    }

    init(type: SessionType, duration: TimeInterval, project: Project? = nil, customLabel: String? = nil) {
        self.id = UUID()
        self.project = project
        self.customLabel = customLabel
        self.type = type
        self.duration = duration
        self.startedAt = Date()
        self.endedAt = nil
        self.completed = false
        self.calendarEventId = nil
        self.totalPausedSeconds = 0
        self.splits = []
    }

    var hasSplits: Bool { !splits.isEmpty }

    var label: String {
        project?.name ?? customLabel ?? type.displayName
    }

    /// Active focus time: wall-clock elapsed minus any time spent paused.
    var actualDuration: TimeInterval {
        let end = endedAt ?? Date()
        let wallElapsed = end.timeIntervalSince(startedAt)
        let active = max(0, wallElapsed - totalPausedSeconds)
        return completed ? active : min(active, duration)
    }

    /// The session's effective end time for stats/overlap calculations.
    /// Uses `startedAt + actualDuration` so paused time is correctly excluded
    /// from duration totals, unlike `endedAt` which is the raw wall-clock end.
    var effectiveEnd: Date {
        startedAt.addingTimeInterval(actualDuration)
    }
}
