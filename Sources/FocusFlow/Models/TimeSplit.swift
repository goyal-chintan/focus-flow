import Foundation
import SwiftData

@Model
final class TimeSplit {
    var id: UUID
    var session: FocusSession?
    var project: Project?
    var customLabel: String?
    var duration: TimeInterval // seconds

    init(project: Project? = nil, customLabel: String? = nil, duration: TimeInterval) {
        self.id = UUID()
        self.project = project
        self.customLabel = customLabel
        self.duration = duration
    }

    var label: String {
        project?.name ?? customLabel ?? "Unlabeled"
    }
}
