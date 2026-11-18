import XCTest
import SwiftData
@testable import FocusFlow

/// Data safety: a store written by an older build opens with today's schema, every row intact.
/// Coach v8 added ActivityHour, DayLabel and AppRoleRuleRecord (additive); v8 phases 3–5 keep their
/// records in defaults and change no model.
@MainActor
final class StoreUpgradeTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("ff-upgrade-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// The schema before coach v8 (the 2026-11-06 pre-v8-p1 backup's models).
    private static let preV8: [any PersistentModel.Type] = [
        Project.self, FocusSession.self, AppSettings.self, TimeSplit.self, BlockProfile.self, AppUsageRecord.self, AppUsageEntry.self,
        TaskIntent.self, CoachInterruption.self, InterventionAttempt.self, BreakLearningEvent.self, IdleDistractionItem.self,
        WeeklyPriority.self, PlannedBlock.self, ProjectGoal.self, GoalKeyResult.self, GoalProgressEntry.self, DailyTask.self,
        BlockStartEvent.self,
    ]

    func testAPreV8StoreOpensWithTodaysSchemaAndKeepsEveryRow() throws {
        let url = directory.appendingPathComponent("FocusFlow.store")
        let projectID: UUID
        do {
            let old = Schema(Self.preV8)
            let container = try ModelContainer(for: old, configurations: ModelConfiguration(schema: old, url: url))
            let context = container.mainContext
            let settings = AppSettings(); settings.dailyFocusGoal = 10_800
            context.insert(settings)
            let learning = Project(name: "Learning"); learning.area = .personal; learning.dailyTargetMinutes = 150
            context.insert(learning)
            projectID = learning.id
            for i in 0..<5 {
                let s = FocusSession(type: .focus, duration: 1500, project: learning)
                s.startedAt = Date().addingTimeInterval(-Double(i) * 86_400); s.endedAt = s.startedAt.addingTimeInterval(1500); s.completed = true
                context.insert(s)
            }
            context.insert(AppUsageEntry(date: Calendar.current.startOfDay(for: Date()), appName: "Slack", bundleIdentifier: "com.tinyspeck.slackmacgap",
                                         duringFocusSeconds: 0, outsideFocusSeconds: 3600))
            context.insert(PlannedBlock(startAt: Date().addingTimeInterval(3600), minutes: 25, title: nil, priorityID: nil, projectID: learning.id))
            try context.save()
        }

        try StoreMigrator.migrateStoreIfNeeded(at: url)
        let container = try ModelContainer(for: FocusFlowSchema.schema, configurations: ModelConfiguration(schema: FocusFlowSchema.schema, url: url))
        let context = container.mainContext
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<FocusSession>()), 5)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<AppUsageEntry>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PlannedBlock>()), 1)
        let project = try XCTUnwrap(try context.fetch(FetchDescriptor<Project>()).first)
        XCTAssertEqual(project.id, projectID)
        XCTAssertEqual(project.dailyTargetMinutes, 150)
        XCTAssertEqual(project.area, .personal)
        XCTAssertEqual(try context.fetch(FetchDescriptor<AppSettings>()).first?.dailyFocusGoal, 10_800)

        // The new models work in the upgraded store.
        context.insert(DayLabel(day: Calendar.current.startOfDay(for: Date()), type: .leave, source: .user))
        context.insert(ActivityHour(hourStart: Date(), key: "call", label: "Call", projectID: nil, inBlock: false, seconds: 600))
        context.insert(AppRoleRuleRecord(key: "com.tinyspeck.slackmacgap", displayName: "Slack", scope: .project(projectID), role: .pull))
        try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<DayLabel>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<AppRoleRuleRecord>()), 1)
    }

    func testTheAppOpensItsStoreWithTheSharedSchema() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repoRoot = testsDirectory.deletingLastPathComponent().deletingLastPathComponent()
        let app = try String(contentsOf: repoRoot.appendingPathComponent("Sources/FocusFlow/FocusFlowApp.swift"), encoding: .utf8)
        XCTAssertTrue(app.contains("let schema = FocusFlowSchema.schema"), "The upgrade test proves nothing if the app opens a different list")
        XCTAssertEqual(FocusFlowSchema.models.count, Self.preV8.count + 3)
    }

    /// Coach v8 phases 3–4 keep their records in defaults; a reset of those keys loses no store data.
    func testCoachRecordsLiveInDefaultsNotTheStore() {
        let defaults = cleanDefaults("upgrade")
        DayTargetStore(defaults: defaults).set(180, for: .leave)
        WeeklyReviewStore(defaults: defaults).markOffered(Date())
        XCTAssertEqual(DayTargetStore(defaults: defaults).minutes(for: .leave), 180)
        XCTAssertTrue(defaults.dictionaryRepresentation().keys.contains(DayTargetStore.key(.leave)))
        XCTAssertTrue(defaults.dictionaryRepresentation().keys.contains(WeeklyReviewStore.offeredKey))
    }
}
