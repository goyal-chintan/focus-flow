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
    @Relationship(deleteRule: .nullify)
    var blockProfiles: [BlockProfile]
    var workMode: WorkMode = WorkMode.deepWork
    var guardianSensitivity: GuardianSensitivity = GuardianSensitivity.normal
    var difficultyBias: DifficultyBias = DifficultyBias.moderate

    @Relationship(deleteRule: .nullify, inverse: \FocusSession.project)
    var sessions: [FocusSession]

    init(name: String, color: String = "blue", icon: String? = nil) {
        self.id = UUID()
        self.name = name
        self.color = color
        self.icon = icon
        self.archived = false
        self.createdAt = Date()
        self.blockProfiles = []
        self.sessions = []
    }

    var effectiveBlockProfiles: [BlockProfile] {
        var seen = Set<UUID>()
        var merged: [BlockProfile] = []

        for profile in blockProfiles {
            if seen.insert(profile.id).inserted {
                merged.append(profile)
            }
        }

        if let blockProfile, seen.insert(blockProfile.id).inserted {
            merged.append(blockProfile)
        }

        return merged
    }

    var mergedBlockedWebsites: Set<String> {
        Set(effectiveBlockProfiles
            .flatMap(\.blockedWebsites)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty })
    }

    var mergedBlockedApps: Set<String> {
        Set(effectiveBlockProfiles
            .flatMap(\.blockedApps)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty })
    }
}
