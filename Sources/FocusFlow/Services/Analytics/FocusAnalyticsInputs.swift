import Foundation

// Plain value inputs for the companion analytics engine.
// The engine never touches SwiftData or SwiftUI: views map models to these
// samples (see FocusAnalyticsModelAdapters.swift) and tests build them directly.

/// Identifies the thing a block of time is attributed to (a project, a free-text label, or nothing).
struct AnalyticsProjectKey: Hashable, Sendable, Comparable {
    let id: String
    let name: String
    /// Stored project colour name ("blue", "mint", …). `nil` for unassigned time.
    let colorName: String?

    static let unassigned = AnalyticsProjectKey(id: "none", name: "No project", colorName: nil)

    static func project(id: UUID, name: String, colorName: String) -> AnalyticsProjectKey {
        AnalyticsProjectKey(id: "project:\(id.uuidString)", name: name, colorName: colorName)
    }

    static func label(_ label: String) -> AnalyticsProjectKey {
        AnalyticsProjectKey(id: "label:\(label.lowercased())", name: label, colorName: nil)
    }

    static func < (lhs: AnalyticsProjectKey, rhs: AnalyticsProjectKey) -> Bool {
        lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }

    /// `UUID` of the project when this key represents a stored project.
    var projectUUID: UUID? {
        guard id.hasPrefix("project:") else { return nil }
        return UUID(uuidString: String(id.dropFirst("project:".count)))
    }
}

/// A focus block, reduced to what analytics needs.
struct FocusSample: Hashable, Sendable, Identifiable {
    struct Share: Hashable, Sendable {
        let project: AnalyticsProjectKey
        /// Relative weight; shares are normalised by their sum.
        let weight: Double
    }

    let id: UUID
    let start: Date
    /// Active (pause-excluded) seconds. The block is treated as `start ..< start + activeSeconds`,
    /// the same convention as `FocusSession.effectiveEnd`.
    let activeSeconds: TimeInterval
    let isFocus: Bool
    let completed: Bool
    let project: AnalyticsProjectKey
    /// Split attribution. Empty means 100% to `project`.
    let shares: [Share]
    let priorityID: UUID?
    let outcome: SessionOutcome?
    let intentText: String?

    init(
        id: UUID = UUID(),
        start: Date,
        activeSeconds: TimeInterval,
        isFocus: Bool = true,
        completed: Bool = true,
        project: AnalyticsProjectKey = .unassigned,
        shares: [Share] = [],
        priorityID: UUID? = nil,
        outcome: SessionOutcome? = nil,
        intentText: String? = nil
    ) {
        self.id = id
        self.start = start
        self.activeSeconds = max(0, activeSeconds)
        self.isFocus = isFocus
        self.completed = completed
        self.project = project
        self.shares = shares
        self.priorityID = priorityID
        self.outcome = outcome
        self.intentText = intentText
    }

    var end: Date { start.addingTimeInterval(activeSeconds) }
    var interval: DateInterval { DateInterval(start: start, duration: activeSeconds) }

    /// Seconds of this block that fall inside `interval`.
    func overlap(with interval: DateInterval) -> TimeInterval {
        let lower = max(start, interval.start)
        let upper = min(end, interval.end)
        return max(0, upper.timeIntervalSince(lower))
    }

    /// Normalised (project, fraction) pairs, fractions summing to 1.
    var normalisedShares: [(project: AnalyticsProjectKey, fraction: Double)] {
        let total = shares.reduce(0) { $0 + max(0, $1.weight) }
        guard total > 0 else { return [(project, 1)] }
        return shares.filter { $0.weight > 0 }.map { ($0.project, $0.weight / total) }
    }
}

/// One `AppUsageEntry` row (per app or domain, per day).
struct UsageSample: Hashable, Sendable {
    let day: Date
    let appName: String
    let bundleIdentifier: String
    let duringFocusSeconds: Int
    let outsideFocusSeconds: Int

    init(day: Date, appName: String, bundleIdentifier: String, duringFocusSeconds: Int = 0, outsideFocusSeconds: Int) {
        self.day = day
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.duringFocusSeconds = duringFocusSeconds
        self.outsideFocusSeconds = outsideFocusSeconds
    }
}

/// One coach prompt (`InterventionAttempt`).
struct PromptSample: Hashable, Sendable {
    let deliveredAt: Date
    let styleRawValue: String?
    let surfaceRawValue: String?

    init(deliveredAt: Date, styleRawValue: String? = nil, surfaceRawValue: String? = nil) {
        self.deliveredAt = deliveredAt
        self.styleRawValue = styleRawValue
        self.surfaceRawValue = surfaceRawValue
    }

    var style: CoachStyle? { styleRawValue.flatMap(CoachStyle.init(rawValue:)) }
    var surface: CoachSurface? { surfaceRawValue.flatMap(CoachSurface.init(rawValue:)) }
}

/// One `WeeklyPriority`.
struct PrioritySample: Hashable, Sendable, Identifiable {
    let id: UUID
    let title: String
    let weekStart: Date
    let order: Int
    let isDone: Bool
    let projectID: UUID?

    init(id: UUID = UUID(), title: String, weekStart: Date, order: Int = 0, isDone: Bool = false, projectID: UUID? = nil) {
        self.id = id
        self.title = title
        self.weekStart = weekStart
        self.order = order
        self.isDone = isDone
        self.projectID = projectID
    }
}
