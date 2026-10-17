import Foundation

// Maps SwiftData models to the engine's value samples. Kept separate so the engine itself
// has no dependency on model objects.

extension AnalyticsProjectKey {
    init(project: Project?, customLabel: String?) {
        if let project {
            self = .project(id: project.id, name: project.name, colorName: project.color)
        } else if let label = customLabel?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty {
            self = .label(label)
        } else {
            self = .unassigned
        }
    }
}

extension FocusSample {
    init(_ session: FocusSession) {
        self.init(
            id: session.id,
            start: session.startedAt,
            activeSeconds: session.actualDuration,
            isFocus: session.type == .focus,
            completed: session.completed,
            project: AnalyticsProjectKey(project: session.project, customLabel: session.customLabel),
            shares: session.splits.map {
                Share(project: AnalyticsProjectKey(project: $0.project, customLabel: $0.customLabel), weight: $0.duration)
            },
            priorityID: session.priorityID,
            outcome: session.outcome,
            intentText: session.intentText
        )
    }
}

extension UsageSample {
    init(_ entry: AppUsageEntry) {
        self.init(
            day: entry.date,
            appName: entry.appName,
            bundleIdentifier: entry.bundleIdentifier,
            duringFocusSeconds: entry.duringFocusSeconds,
            outsideFocusSeconds: entry.outsideFocusSeconds
        )
    }
}

extension PromptSample {
    init(_ attempt: InterventionAttempt) {
        self.init(deliveredAt: attempt.deliveredAt, styleRawValue: attempt.styleRawValue, surfaceRawValue: attempt.surfaceRawValue)
    }
}

extension PrioritySample {
    init(_ priority: WeeklyPriority) {
        self.init(
            id: priority.id,
            title: priority.title,
            weekStart: priority.weekStart,
            order: priority.order,
            isDone: priority.isDone,
            projectID: priority.projectID
        )
    }
}

enum DerailerRuleKeys {
    /// Keys of active distraction rules the user confirmed (major/minor) and ones they marked allowed.
    static func from(_ items: [IdleDistractionItem]) -> (confirmed: Set<String>, allowed: Set<String>) {
        var confirmed = Set<String>()
        var allowed = Set<String>()
        for item in items where item.status == .active {
            let key = item.key.lowercased()
            if item.severity == .allowed { allowed.insert(key) } else { confirmed.insert(key) }
        }
        return (confirmed, allowed)
    }
}
