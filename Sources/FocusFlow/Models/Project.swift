import Foundation
import SwiftData

@Model
final class Project {
    var id: UUID
    var name: String
    var color: String
    var icon: String?
    var archived: Bool
    var createdAt: Date
    var blockProfile: BlockProfile?
    var workMode: WorkMode = WorkMode.deepWork
    var guardianSensitivity: GuardianSensitivity = GuardianSensitivity.normal

    @Relationship(deleteRule: .nullify, inverse: \FocusSession.project)
    var sessions: [FocusSession]

    init(name: String, color: String = "blue", icon: String? = nil) {
        self.id = UUID()
        self.name = name
        self.color = color
        self.icon = icon
        self.archived = false
        self.createdAt = Date()
        self.sessions = []
    }
}
