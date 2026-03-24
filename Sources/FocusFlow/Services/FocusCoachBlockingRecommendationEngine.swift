import Foundation

/// Generates learned, project-scoped blocking recommendations.
/// Never recommends global blocks. Evidence thresholds must be met before surfacing.
final class FocusCoachBlockingRecommendationEngine {

    // MARK: - Risk Store (in-memory, persisted via UserDefaults)
    private static let storageKey = "focusflow.projectContextRisks"

    private var risks: [String: ProjectContextRisk] = [:]  // key: contextKey
    private let defaults: UserDefaults

    convenience init() {
        self.init(defaults: .standard)
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([String: ProjectContextRisk].self, from: data) {
            self.risks = decoded
        }
    }

    // MARK: - Recording

    func recordAvoidant(projectId: UUID, workMode: WorkMode, contextKey: String, displayName: String) {
        var risk = risks[contextKey] ?? ProjectContextRisk(
            projectId: projectId, workMode: workMode,
            contextKey: contextKey, contextDisplayName: displayName
        )
        risk.avoidantDates.append(Date())
        risks[contextKey] = risk
        persist()
    }

    func recordPlanned(projectId: UUID, workMode: WorkMode, contextKey: String, displayName: String) {
        var risk = risks[contextKey] ?? ProjectContextRisk(
            projectId: projectId, workMode: workMode,
            contextKey: contextKey, contextDisplayName: displayName
        )
        risk.plannedDates.append(Date())
        risks[contextKey] = risk
        persist()
    }

    func recordMissedStart(projectId: UUID, workMode: WorkMode, contextKey: String, displayName: String) {
        var risk = risks[contextKey] ?? ProjectContextRisk(
            projectId: projectId, workMode: workMode,
            contextKey: contextKey, contextDisplayName: displayName
        )
        risk.missedStartCorrelationCount += 1
        risks[contextKey] = risk
        persist()
    }

    func recordBreakOverrunCorrelation(projectId: UUID, workMode: WorkMode, contextKey: String, displayName: String) {
        var risk = risks[contextKey] ?? ProjectContextRisk(
            projectId: projectId, workMode: workMode,
            contextKey: contextKey, contextDisplayName: displayName
        )
        risk.breakOverrunCorrelationCount += 1
        risks[contextKey] = risk
        persist()
    }

    // MARK: - Recommendations

    /// Returns a block recommendation if evidence threshold is met, nil otherwise.
    func blockRecommendation(for contextKey: String, projectName: String? = nil) -> BlockingRecommendation? {
        guard let risk = risks[contextKey], risk.shouldRecommendBlock else { return nil }
        // Don't re-surface within 24h of last recommendation
        if let last = risk.lastRecommendationTimestamp,
           Date().timeIntervalSince(last) < 24 * 3600 { return nil }
        return BlockingRecommendation(
            kind: .block,
            contextKey: contextKey,
            displayName: risk.contextDisplayName,
            projectId: risk.projectId,
            workMode: risk.workMode,
            projectName: projectName,
            copyText: recommendationCopy(for: risk, kind: .block, projectName: projectName),
            suggestedActions: [.block, .warnOnly, .notNow]
        )
    }

    /// Returns an allow recommendation if evidence threshold is met, nil otherwise.
    func allowRecommendation(for contextKey: String, projectName: String? = nil) -> BlockingRecommendation? {
        guard let risk = risks[contextKey], risk.shouldRecommendAllow else { return nil }
        return BlockingRecommendation(
            kind: .allow,
            contextKey: contextKey,
            displayName: risk.contextDisplayName,
            projectId: risk.projectId,
            workMode: risk.workMode,
            projectName: projectName,
            copyText: recommendationCopy(for: risk, kind: .allow, projectName: projectName),
            suggestedActions: [.allow]
        )
    }

    func markRecommendationSurfaced(contextKey: String) {
        risks[contextKey]?.lastRecommendationTimestamp = Date()
        persist()
    }

    // MARK: - Copy Generation

    private func recommendationCopy(for risk: ProjectContextRisk, kind: BlockingRecommendation.Kind, projectName: String? = nil) -> String {
        let name = risk.contextDisplayName
        let project = projectName ?? "your current project"
        let mode = risk.workMode.displayName

        switch kind {
        case .block:
            if risk.missedStartCorrelationCount >= 1 {
                return "\(name) caused a missed start on \(project). Block it for this project?"
            }
            if risk.breakOverrunCorrelationCount >= 3 {
                return "\(name) keeps extending breaks on \(project). Block it during sessions?"
            }
            return "\(name) keeps replacing \(mode) on \(project). Block it for this project?"
        case .allow:
            return "\(name) was confirmed as planned work on \(project) multiple times. Allow it?"
        case .warnOnly, .notNow:
            return ""
        }
    }

    // MARK: - Persistence

    private func persist() {
        if let data = try? JSONEncoder().encode(risks) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }
}

// MARK: - BlockingRecommendation

struct BlockingRecommendation {
    enum Kind {
        case block, allow
        case warnOnly  // "Warn Only" — show a warning instead of blocking
        case notNow    // "Not Now" — dismiss recommendation without action

        var label: String {
            switch self {
            case .block: return "Block"
            case .allow: return "Allow"
            case .warnOnly: return "Warn Only"
            case .notNow: return "Not Now"
            }
        }
    }
    let kind: Kind
    let contextKey: String
    let displayName: String
    let projectId: UUID
    let workMode: WorkMode
    let projectName: String?
    let copyText: String
    /// The three actions always offered for a block recommendation: block, warn only, not now.
    let suggestedActions: [Kind]
}
