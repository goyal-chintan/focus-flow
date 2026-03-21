import EventKit

/// Single shared EKEventStore for the entire app.
/// Apple's documentation explicitly requires ONE store per app — creating
/// multiple stores is expensive and can cause crashes when permissions change.
@MainActor
final class EventStoreManager {
    static let shared = EventStoreManager()
    let store = EKEventStore()
    private init() {}
}
