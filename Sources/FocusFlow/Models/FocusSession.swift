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
        guard let endedAt else { return Date().timeIntervalSince(startedAt) }
        return endedAt.timeIntervalSince(startedAt)
    }
}
