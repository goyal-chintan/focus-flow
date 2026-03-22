import Foundation
import SwiftData

/// SwiftData-backed implementation of ``FocusCoachPersisting``.
/// Persists coach interruptions and intervention attempts across app launches,
/// enabling the weekly insights builder and personalization loop to access historical data.
@MainActor
final class SwiftDataCoachStore: @preconcurrency FocusCoachPersisting {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func saveInterruption(_ interruption: CoachInterruption) {
        modelContext.insert(interruption)
        try? modelContext.save()
    }

    func saveInterventionAttempt(_ attempt: InterventionAttempt) {
        modelContext.insert(attempt)
        try? modelContext.save()
    }

    var interruptions: [CoachInterruption] {
        let descriptor = FetchDescriptor<CoachInterruption>(
            sortBy: [SortDescriptor(\.detectedAt, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    var attempts: [InterventionAttempt] {
        let descriptor = FetchDescriptor<InterventionAttempt>(
            sortBy: [SortDescriptor(\.deliveredAt, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }
}
