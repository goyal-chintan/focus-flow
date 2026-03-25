import Foundation
import SwiftData

@MainActor
struct BreakLearningStore {
    let modelContext: ModelContext

    func record(
        projectId: UUID?,
        workMode: WorkMode,
        suggestedMinutes: Int,
        choseSuggested: Bool,
        actualBreakSeconds: Int,
        returnedToFocus: Bool,
        endedEarly: Bool,
        overrunSeconds: Int
    ) {
        let event = BreakLearningEvent(
            projectId: projectId,
            workMode: workMode,
            suggestedMinutes: suggestedMinutes,
            choseSuggested: choseSuggested,
            actualBreakSeconds: actualBreakSeconds,
            returnedToFocus: returnedToFocus,
            endedEarly: endedEarly,
            overrunSeconds: overrunSeconds
        )
        modelContext.insert(event)
        do {
            try modelContext.save()
        } catch {
            print("[BreakLearningStore] Failed to save break learning event: \(error.localizedDescription)")
        }
    }

    func recentEvents(projectId: UUID?, workMode: WorkMode, limit: Int) -> [BreakLearningEvent] {
        var descriptor = FetchDescriptor<BreakLearningEvent>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = max(1, limit)

        guard let all = try? modelContext.fetch(descriptor) else {
            return []
        }

        return all.filter { event in
            event.projectId == projectId && event.workMode == workMode
        }
    }
}
