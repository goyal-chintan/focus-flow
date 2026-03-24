import Foundation

// MARK: - Suspicious Context Observation
/// A single observation of app foreground state during or near a work session.
/// Emitted by AppUsageTracker; enriched with browser/terminal context where available.
struct SuspiciousContextObservation {
    let id: UUID
    let timestamp: Date
    let bundleIdentifier: String
    let localizedAppName: String
    var browserHost: String?          // e.g. "youtube.com", "reddit.com"
    var browserPageTitle: String?     // e.g. "How Sorting Algorithms Work - YouTube"
    var terminalWorkspace: String?    // git repo root path if detectable
    var editorWorkspace: String?      // editor workspace/project name
    var selectedProjectId: UUID?
    var selectedWorkMode: WorkMode?
    var isInSession: Bool

    init(bundleIdentifier: String, localizedAppName: String, selectedProjectId: UUID? = nil,
         selectedWorkMode: WorkMode? = nil, isInSession: Bool) {
        self.id = UUID()
        self.timestamp = Date()
        self.bundleIdentifier = bundleIdentifier
        self.localizedAppName = localizedAppName
        self.selectedProjectId = selectedProjectId
        self.selectedWorkMode = selectedWorkMode
        self.isInSession = isInSession
    }
}

// MARK: - Context Disposition
/// User-labeled or system-inferred disposition for a SuspiciousContextObservation.
enum ContextDisposition: String, Codable, CaseIterable {
    case plannedWork             = "planned_work"
    case plannedResearch         = "planned_research"
    case requiredContextSwitch   = "required_context_switch"
    case realBreak               = "real_break"
    case legitimateInterruption  = "legitimate_interruption"
    case lowPriorityWork         = "low_priority_work"
    case procrastinating         = "procrastinating"
    case fatigued                = "fatigued"
    case intentionalLeisure      = "intentional_leisure"

    var isAvoidant: Bool {
        switch self {
        case .lowPriorityWork, .procrastinating: return true
        default: return false
        }
    }

    var isLegitimate: Bool {
        switch self {
        case .plannedWork, .plannedResearch, .requiredContextSwitch,
             .realBreak, .legitimateInterruption, .fatigued: return true
        default: return false
        }
    }
}

// MARK: - Drift Classification Memory
/// Keyed by "projectId|workMode|appOrDomain". Learns planned vs avoidant patterns.
struct DriftClassificationMemory: Codable {
    private var plannedDates: [String: [Date]] = [:]
    private var avoidantDates: [String: [Date]] = [:]

    static let projectScopedAllowanceWindow: TimeInterval = 14 * 24 * 3600  // 14 days
    static let projectScopedRiskWindow: TimeInterval      = 7 * 24 * 3600   // 7 days
    static let projectScopedAllowanceCount = 2
    static let projectScopedRiskCount      = 2

    mutating func recordPlanned(key: String) {
        var dates = plannedDates[key] ?? []
        dates.append(Date())
        plannedDates[key] = dates
    }

    mutating func recordAvoidant(key: String) {
        var dates = avoidantDates[key] ?? []
        dates.append(Date())
        avoidantDates[key] = dates
    }

    /// Returns true if user has confirmed this context as planned at least once this session.
    /// Session scope: always granted after 1 confirmation (not persisted across sessions here).
    func sessionScopedAllowance(key: String, sessionStart: Date) -> Bool {
        let dates = plannedDates[key] ?? []
        return dates.contains { $0 >= sessionStart }
    }

    /// Returns true if user confirmed planned 2+ times in last 14 days → project-scoped allowance.
    func projectScopedAllowance(key: String) -> Bool {
        let cutoff = Date().addingTimeInterval(-Self.projectScopedAllowanceWindow)
        let recent = (plannedDates[key] ?? []).filter { $0 >= cutoff }
        return recent.count >= Self.projectScopedAllowanceCount
    }

    /// Returns true if user confirmed avoidant 2+ times in last 7 days → project-scoped risk.
    func projectScopedRisk(key: String) -> Bool {
        let cutoff = Date().addingTimeInterval(-Self.projectScopedRiskWindow)
        let recent = (avoidantDates[key] ?? []).filter { $0 >= cutoff }
        return recent.count >= Self.projectScopedRiskCount
    }

    /// Prune dates older than 30 days to keep storage bounded.
    mutating func prune() {
        let cutoff = Date().addingTimeInterval(-30 * 24 * 3600)
        for key in plannedDates.keys {
            plannedDates[key] = (plannedDates[key] ?? []).filter { $0 >= cutoff }
        }
        for key in avoidantDates.keys {
            avoidantDates[key] = (avoidantDates[key] ?? []).filter { $0 >= cutoff }
        }
    }

    /// Generate memory key from components.
    static func key(projectId: UUID?, workMode: WorkMode?, appOrDomain: String) -> String {
        let p = projectId?.uuidString ?? "none"
        let w = workMode?.rawValue ?? "none"
        return "\(p)|\(w)|\(appOrDomain)"
    }
}

// MARK: - Project Context Risk
/// Tracks avoidant/planned patterns per (project, workMode, app/domain/repo) tuple.
struct ProjectContextRisk: Codable, Identifiable {
    let id: UUID
    var projectId: UUID
    var workMode: WorkMode
    var contextKey: String            // app bundle, domain, or repo path
    var contextDisplayName: String    // human-readable label for recommendations

    var avoidantDates: [Date] = []
    var plannedDates: [Date] = []
    var breakOverrunCorrelationCount: Int = 0
    var missedStartCorrelationCount: Int = 0
    var lastRecommendationTimestamp: Date?

    static let blockRecommendationAvoidantWindow: TimeInterval = 7 * 24 * 3600
    static let blockRecommendationCount = 2

    init(projectId: UUID, workMode: WorkMode, contextKey: String, contextDisplayName: String) {
        self.id = UUID()
        self.projectId = projectId
        self.workMode = workMode
        self.contextKey = contextKey
        self.contextDisplayName = contextDisplayName
    }

    /// True when evidence warrants recommending a project-scoped block.
    var shouldRecommendBlock: Bool {
        let cutoff = Date().addingTimeInterval(-Self.blockRecommendationAvoidantWindow)
        let recentAvoidant = avoidantDates.filter { $0 >= cutoff }.count
        return recentAvoidant >= Self.blockRecommendationCount
            || missedStartCorrelationCount >= 1
            || breakOverrunCorrelationCount >= 3
    }

    /// True when evidence warrants project-scoped allow.
    var shouldRecommendAllow: Bool {
        let cutoff = Date().addingTimeInterval(-DriftClassificationMemory.projectScopedAllowanceWindow)
        let recentPlanned = plannedDates.filter { $0 >= cutoff }.count
        return recentPlanned >= DriftClassificationMemory.projectScopedAllowanceCount
    }
}
