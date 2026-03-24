import Foundation

/// Persists DriftClassificationMemory across app launches using UserDefaults.
/// Provides the canonical interface for recording and querying planned/avoidant confirmations.
@Observable
final class DriftMemoryStore {
    private static let storageKey = "focusflow.driftClassificationMemory"

    private(set) var memory: DriftClassificationMemory
    private let defaults: UserDefaults

    /// Current session start — used for session-scoped allowance queries.
    var sessionStart: Date = Date()

    convenience init() {
        self.init(defaults: .standard)
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(DriftClassificationMemory.self, from: data) {
            self.memory = decoded
        } else {
            self.memory = DriftClassificationMemory()
        }
    }

    // MARK: - Recording

    /// Record that the user confirmed this context was planned work.
    func recordPlanned(projectId: UUID?, workMode: WorkMode?, appOrDomain: String) {
        let key = DriftClassificationMemory.key(projectId: projectId, workMode: workMode, appOrDomain: appOrDomain)
        memory.recordPlanned(key: key)
        persist()
    }

    /// Record that the user confirmed this context was avoidant behaviour.
    func recordAvoidant(projectId: UUID?, workMode: WorkMode?, appOrDomain: String) {
        let key = DriftClassificationMemory.key(projectId: projectId, workMode: workMode, appOrDomain: appOrDomain)
        memory.recordAvoidant(key: key)
        persist()
    }

    // MARK: - Querying

    func sessionScopedAllowance(projectId: UUID?, workMode: WorkMode?, appOrDomain: String) -> Bool {
        let key = DriftClassificationMemory.key(projectId: projectId, workMode: workMode, appOrDomain: appOrDomain)
        return memory.sessionScopedAllowance(key: key, sessionStart: sessionStart)
    }

    func projectScopedAllowance(projectId: UUID?, workMode: WorkMode?, appOrDomain: String) -> Bool {
        let key = DriftClassificationMemory.key(projectId: projectId, workMode: workMode, appOrDomain: appOrDomain)
        return memory.projectScopedAllowance(key: key)
    }

    func projectScopedRisk(projectId: UUID?, workMode: WorkMode?, appOrDomain: String) -> Bool {
        let key = DriftClassificationMemory.key(projectId: projectId, workMode: workMode, appOrDomain: appOrDomain)
        return memory.projectScopedRisk(key: key)
    }

    // MARK: - Session lifecycle

    /// Call when a new focus session starts to reset session-scoped allowances.
    func beginSession() {
        sessionStart = Date()
    }

    // MARK: - Maintenance

    func pruneOldEntries() {
        memory.prune()
        persist()
    }

    // MARK: - Private

    private func persist() {
        if let data = try? JSONEncoder().encode(memory) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }
}
