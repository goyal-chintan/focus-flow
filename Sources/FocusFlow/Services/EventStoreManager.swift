import EventKit

/// Single shared EKEventStore for the entire app.
/// Apple's documentation explicitly requires ONE store per app — creating
/// multiple stores is expensive and can cause crashes when permissions change.
@MainActor
final class EventStoreManager {
    static let shared = EventStoreManager()
    let store = EKEventStore()
    private var activeOperationName: String?
    private init() {}

    /// Serializes EventKit operations that can crash when overlapped on the shared store.
    /// This intentionally gates async operations (permission/fetch/save pipelines) so
    /// callbacks and internal EventKit queues remain consistent.
    func withExclusiveAccess<T>(
        operation name: String,
        _ work: () async throws -> T
    ) async rethrows -> T {
        while activeOperationName != nil {
            try? await Task.sleep(for: .milliseconds(25))
        }
        activeOperationName = name
        defer { activeOperationName = nil }
        return try await work()
    }
}
