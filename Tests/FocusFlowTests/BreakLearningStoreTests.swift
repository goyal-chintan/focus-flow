import XCTest
import SwiftData
@testable import FocusFlow

@MainActor
final class BreakLearningStoreTests: XCTestCase {
    func testRecordAndFetchRecentProjectScopedBreakEvents() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let store = BreakLearningStore(modelContext: context)
        let project = Project(name: "Interview Prep")
        context.insert(project)

        store.record(
            projectId: project.id,
            workMode: .deepWork,
            suggestedMinutes: 15,
            choseSuggested: true,
            actualBreakSeconds: 14 * 60,
            returnedToFocus: true,
            endedEarly: false,
            overrunSeconds: 0
        )

        let events = store.recentEvents(projectId: project.id, workMode: .deepWork, limit: 10)
        XCTAssertEqual(events.count, 1)
        XCTAssertTrue(events[0].returnedToFocus)
    }

    private func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([
            Project.self,
            FocusSession.self,
            AppSettings.self,
            TimeSplit.self,
            BlockProfile.self,
            AppUsageRecord.self,
            AppUsageEntry.self,
            TaskIntent.self,
            CoachInterruption.self,
            InterventionAttempt.self,
            BreakLearningEvent.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: config)
    }
}
