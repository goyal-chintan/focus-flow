import Foundation

/// Generates learned, project-scoped blocking recommendations.
/// Never recommends global blocks. Evidence thresholds must be met before surfacing.
final class FocusCoachBlockingRecommendationEngine {

    // MARK: - Risk Store (in-memory, persisted via UserDefaults)
    private static let storageKey = "focusflow.projectContextRisks"

    private var risks: [String: ProjectContextRisk] = [:]  // key: projectId|workMode|contextKey
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
        let key = scopedKey(projectId: projectId, workMode: workMode, contextKey: contextKey)
        var risk = risks[key] ?? ProjectContextRisk(
            projectId: projectId,
            workMode: workMode,
            contextKey: normalizedContextKey(contextKey),
            contextDisplayName: displayName
        )
        risk.avoidantDates.append(Date())
        risks[key] = risk
        persist()
    }

    func recordPlanned(projectId: UUID, workMode: WorkMode, contextKey: String, displayName: String) {
        let key = scopedKey(projectId: projectId, workMode: workMode, contextKey: contextKey)
        var risk = risks[key] ?? ProjectContextRisk(
            projectId: projectId,
            workMode: workMode,
            contextKey: normalizedContextKey(contextKey),
            contextDisplayName: displayName
        )
        risk.plannedDates.append(Date())
        risks[key] = risk
        persist()
    }

    func recordMissedStart(projectId: UUID, workMode: WorkMode, contextKey: String, displayName: String) {
        let key = scopedKey(projectId: projectId, workMode: workMode, contextKey: contextKey)
        var risk = risks[key] ?? ProjectContextRisk(
            projectId: projectId,
            workMode: workMode,
            contextKey: normalizedContextKey(contextKey),
            contextDisplayName: displayName
        )
        risk.missedStartCorrelationCount += 1
        risks[key] = risk
        persist()
    }

    func recordBreakOverrunCorrelation(projectId: UUID, workMode: WorkMode, contextKey: String, displayName: String) {
        let key = scopedKey(projectId: projectId, workMode: workMode, contextKey: contextKey)
        var risk = risks[key] ?? ProjectContextRisk(
            projectId: projectId,
            workMode: workMode,
            contextKey: normalizedContextKey(contextKey),
            contextDisplayName: displayName
        )
        risk.breakOverrunCorrelationCount += 1
        risks[key] = risk
        persist()
    }

    // MARK: - Recommendations

    /// Returns a block recommendation if evidence threshold is met, nil otherwise.
    func blockRecommendation(
        for contextKey: String,
        projectId: UUID? = nil,
        workMode: WorkMode? = nil,
        projectName: String? = nil
    ) -> BlockingRecommendation? {
        guard let risk = riskFor(contextKey: contextKey, projectId: projectId, workMode: workMode),
              risk.shouldRecommendBlock else { return nil }
        // Don't re-surface within 24h of last recommendation
        if let last = risk.lastRecommendationTimestamp,
           Date().timeIntervalSince(last) < 24 * 3600 { return nil }
        let displayName = AppUsageEntry.recommendationDisplayLabel(for: risk.contextDisplayName)
        return BlockingRecommendation(
            kind: .block,
            contextKey: contextKey,
            displayName: displayName,
            projectId: risk.projectId,
            workMode: risk.workMode,
            projectName: projectName,
            copyText: recommendationCopy(displayName: displayName, risk: risk, kind: .block, projectName: projectName),
            suggestedActions: [.block, .warnOnly, .notNow]
        )
    }

    /// Returns an allow recommendation if evidence threshold is met, nil otherwise.
    func allowRecommendation(
        for contextKey: String,
        projectId: UUID? = nil,
        workMode: WorkMode? = nil,
        projectName: String? = nil
    ) -> BlockingRecommendation? {
        guard let risk = riskFor(contextKey: contextKey, projectId: projectId, workMode: workMode),
              risk.shouldRecommendAllow else { return nil }
        let displayName = AppUsageEntry.recommendationDisplayLabel(for: risk.contextDisplayName)
        return BlockingRecommendation(
            kind: .allow,
            contextKey: contextKey,
            displayName: displayName,
            projectId: risk.projectId,
            workMode: risk.workMode,
            projectName: projectName,
            copyText: recommendationCopy(displayName: displayName, risk: risk, kind: .allow, projectName: projectName),
            suggestedActions: [.allow]
        )
    }

    func markRecommendationSurfaced(projectId: UUID, workMode: WorkMode, contextKey: String) {
        let key = scopedKey(projectId: projectId, workMode: workMode, contextKey: contextKey)
        guard risks[key] != nil else { return }
        risks[key]?.lastRecommendationTimestamp = Date()
        persist()
    }

    func markRecommendationSurfaced(contextKey: String, projectId: UUID? = nil, workMode: WorkMode? = nil) {
        if let projectId, let workMode {
            markRecommendationSurfaced(projectId: projectId, workMode: workMode, contextKey: contextKey)
            return
        }

        guard let fallbackKey = uniqueFallbackRiskKey(for: normalizedContextKey(contextKey)) else { return }
        risks[fallbackKey]?.lastRecommendationTimestamp = Date()
        persist()
    }

    func hasMissedStartPattern(projectId: UUID?, workMode: WorkMode?, contextKey: String) -> Bool {
        guard let risk = riskFor(contextKey: contextKey, projectId: projectId, workMode: workMode) else {
            return false
        }
        return risk.missedStartCorrelationCount >= 1
    }

    func hasRepeatedPatternEvidence(projectId: UUID?, workMode: WorkMode?, contextKey: String) -> Bool {
        guard let risk = riskFor(contextKey: contextKey, projectId: projectId, workMode: workMode) else {
            return false
        }
        return risk.shouldRecommendBlock
    }

    // MARK: - Risk Lookup

    private func riskFor(contextKey: String, projectId: UUID?, workMode: WorkMode?) -> ProjectContextRisk? {
        let normalized = normalizedContextKey(contextKey)
        if let projectId, let workMode {
            let key = scopedKey(projectId: projectId, workMode: workMode, contextKey: normalized)
            return risks[key]
        }
        guard let fallbackKey = uniqueFallbackRiskKey(for: normalized) else { return nil }
        return risks[fallbackKey]
    }

    private func scopedKey(projectId: UUID, workMode: WorkMode, contextKey: String) -> String {
        "\(projectId.uuidString)|\(workMode.rawValue)|\(normalizedContextKey(contextKey))"
    }

    private func normalizedContextKey(_ contextKey: String) -> String {
        contextKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func uniqueFallbackRiskKey(for normalizedContextKey: String) -> String? {
        var matchingKeys = Set<String>()
        if risks[normalizedContextKey] != nil {
            matchingKeys.insert(normalizedContextKey)
        }
        for (key, risk) in risks where risk.contextKey == normalizedContextKey {
            matchingKeys.insert(key)
        }
        guard matchingKeys.count == 1 else { return nil }
        return matchingKeys.first
    }

    func hasRisk(for contextKey: String, projectId: UUID?, workMode: WorkMode?) -> Bool {
        riskFor(contextKey: contextKey, projectId: projectId, workMode: workMode) != nil
    }

    func projectScopedRisk(for contextKey: String, projectId: UUID?, workMode: WorkMode?) -> ProjectContextRisk? {
        riskFor(contextKey: contextKey, projectId: projectId, workMode: workMode)
    }

    // MARK: - Copy Generation

    private func recommendationCopy(
        displayName: String,
        risk: ProjectContextRisk,
        kind: BlockingRecommendation.Kind,
        projectName: String? = nil
    ) -> String {
        let name = displayName
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
