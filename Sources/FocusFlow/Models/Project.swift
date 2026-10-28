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

    // Priorities (docs/plans/2026-10-28-priorities-goals-design.md §3.1). Optional: nullable columns,
    // no migration. Nil means "not set" everywhere.
    /// 1 is the top priority. Unranked projects sort after ranked ones.
    var priorityRank: Int?
    /// `ProjectArea` raw value: personal, learning, work, other.
    var areaRaw: String?
    /// Focus minutes per day this project should get.
    var dailyTargetMinutes: Int?
    /// The target applies Monday to Friday only (an office project).
    var targetWeekdaysOnly: Bool?
    /// One line on why it matters.
    var purpose: String?

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

    var area: ProjectArea {
        get { areaRaw.flatMap(ProjectArea.init(rawValue:)) ?? .other }
        set { areaRaw = newValue.rawValue }
    }

    /// The daily target for `date` (nil on weekends for a weekdays-only project, or when unset).
    func dailyTarget(on date: Date, calendar: Calendar = .current) -> Int? {
        guard let minutes = dailyTargetMinutes, minutes > 0 else { return nil }
        // Monday to Friday, explicitly: some locales (e.g. en_IN) count only Sunday as weekend.
        if targetWeekdaysOnly == true, [1, 7].contains(calendar.component(.weekday, from: date)) { return nil }
        return minutes
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

/// What kind of time a project is. Personal and learning time is "your own work" in the honest
/// breakdown; work is the job.
enum ProjectArea: String, CaseIterable, Codable, Sendable, Identifiable {
    case personal
    case learning
    case work
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .personal: "Personal"
        case .learning: "Learning"
        case .work: "Work"
        case .other: "Other"
        }
    }

    var symbol: String {
        switch self {
        case .personal: "person.fill"
        case .learning: "graduationcap.fill"
        case .work: "briefcase.fill"
        case .other: "circle.dashed"
        }
    }

    /// Counts as "your own work".
    var isOwnWork: Bool { self == .personal || self == .learning }
}
