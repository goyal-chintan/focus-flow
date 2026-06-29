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

    /// Number of times this session was paused.
    /// Default is 0 so existing stored sessions are unaffected.
    var pauseCount: Int = 0

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
        self.pauseCount = 0
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

    /// Formatted pause summary: "X pause(s) · Ym Zs paused"
    /// Returns nil when the session had no pauses (count = 0 and seconds = 0).
    var pauseLabel: String? {
        guard totalPausedSeconds > 0 || pauseCount > 0 else { return nil }
        let timeStr = totalPausedSeconds.formattedFocusTime
        let countStr = pauseCount == 1 ? "1 pause" : "\(pauseCount) pauses"
        return "\(countStr) · \(timeStr) paused"
    }
}
