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
    }

    var label: String {
        project?.name ?? customLabel ?? type.displayName
    }

    var actualDuration: TimeInterval {
        let end = endedAt ?? Date()
        let elapsed = end.timeIntervalSince(startedAt)
        return min(elapsed, duration)
    }
}
