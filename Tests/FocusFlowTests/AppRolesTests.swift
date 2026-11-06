import XCTest
import SwiftData
@testable import FocusFlow

/// Coach v8 phase 2: apps judged by context (docs/plans/2026-11-06-coach-v8-life-coach.md §3.3).
final class AppRolesTests: XCTestCase {
    private let learning = UUID(), office = UUID()

    func testDefaultsSlackIsWorkAtTheOfficeAndAPullDuringOwnWork() {
        let book = AppRoleBook()
        XCTAssertEqual(book.role(key: "com.tinyspeck.slackmacgap", name: "Slack", in: .project(office, .work)).role, .tool)
        XCTAssertEqual(book.role(key: "com.tinyspeck.slackmacgap", name: "Slack", in: .project(learning, .own)).role, .pull)
        XCTAssertEqual(book.role(key: "com.tinyspeck.slackmacgap", name: "Slack", in: .free).role, .neutral)
        XCTAssertEqual(book.role(key: "youtube.com", in: .project(learning, .own)).role, .pull)
        XCTAssertEqual(book.role(key: "md.obsidian", name: "Obsidian", in: .project(learning, .own)).role, .neutral)
    }

    func testYourRulesWinProjectThenAreaThenEverywhere() {
        var book = AppRoleBook()
        book.rules = [
            AppRoleRule(key: "youtube.com", scope: .project(learning), role: .tool),
            AppRoleRule(key: "youtube.com", scope: .everywhere, role: .pull),
            AppRoleRule(key: "com.mitchellh.ghostty", scope: .everywhere, role: .pull),
        ]
        XCTAssertEqual(book.role(key: "domain:www.youtube.com", in: .project(learning, .own)).role, .tool, "Tutorials for Learning")
        XCTAssertEqual(book.role(key: "youtube.com", in: .project(office, .work)).role, .pull)
        XCTAssertEqual(book.role(key: "com.mitchellh.ghostty", name: "Ghostty", in: .own).role, .pull, "Your rule beats the built-in work-tool list")
        XCTAssertEqual(book.role(key: "com.mitchellh.ghostty", name: "Ghostty", in: .own).source, .user)
    }

    func testBlocksTeachAToolButNeverOverrideADefaultPull() {
        var book = AppRoleBook()
        let days = Set((0..<9).map { Date(timeIntervalSince1970: Double($0) * 86_400) })
        book.evidence["scaler.com"] = [learning: AppRoleEvidence(minutes: 744, days: days)]
        book.evidence["com.tinyspeck.slackmacgap"] = [learning: AppRoleEvidence(minutes: 90, days: days)]
        let scaler = book.role(key: "domain:scaler.com", in: .project(learning, .own))
        XCTAssertEqual(scaler.role, .tool)
        XCTAssertEqual(scaler.source, .learned)
        XCTAssertEqual(scaler.reason, "12h 24m in its blocks on 9 days")
        XCTAssertEqual(book.role(key: "scaler.com", in: .project(office, .work)).role, .neutral, "Learned for Learning only")
        XCTAssertEqual(book.role(key: "com.tinyspeck.slackmacgap", name: "Slack", in: .project(learning, .own)).role, .pull,
                       "Time in a block is not proof: a default pull needs your answer")
    }

    func testABrowserIsNeverLearned() {
        var book = AppRoleBook()
        let days = Set((0..<9).map { Date(timeIntervalSince1970: Double($0) * 86_400) })
        book.evidence["company.thebrowser.browser"] = [learning: AppRoleEvidence(minutes: 900, days: days)]
        XCTAssertEqual(book.role(key: "company.thebrowser.Browser", name: "Arc", in: .project(learning, .own)).source, .standard)
        XCTAssertTrue(AppsByProjectSection.rows(book: book, records: []).isEmpty)
    }

    func testTheQuestionPicksAPullOpenInOwnWorkBlocks() {
        var book = AppRoleBook()
        let day = Set([Date(timeIntervalSince1970: 0), Date(timeIntervalSince1970: 86_400)])
        book.evidence["com.tinyspeck.slackmacgap"] = [learning: AppRoleEvidence(minutes: 36, days: day)]
        book.evidence["md.obsidian"] = [learning: AppRoleEvidence(minutes: 120, days: day)]
        let pick = AppRoleQuestionPicker.pick(evidence: book.evidence, names: ["com.tinyspeck.slackmacgap": "Slack"], ownProjects: [learning], book: book)
        XCTAssertEqual(pick?.key, "com.tinyspeck.slackmacgap")
        XCTAssertEqual(pick?.days, 2)
        book.rules = [AppRoleRule(key: "com.tinyspeck.slackmacgap", scope: .project(learning), role: .tool)]
        XCTAssertNil(AppRoleQuestionPicker.pick(evidence: book.evidence, names: [:], ownProjects: [learning], book: book), "Answered once")
    }

    func testOutsideABlockContext() {
        XCTAssertEqual(AppContext.outsideBlock(dayType: .workday, hour: 11, inOwnWindow: false), .work)
        XCTAssertEqual(AppContext.outsideBlock(dayType: .workday, hour: 23, inOwnWindow: true), .own)
        XCTAssertEqual(AppContext.outsideBlock(dayType: .leave, hour: 11, inOwnWindow: false), .free, "On leave, Slack is not work")
    }

    func testDriftUsesTheRole() {
        let slack = DriftMonitor.classify(bundleIdentifier: "com.tinyspeck.slackmacgap", appName: "Slack", browserHost: nil, displayName: "Slack",
                                          category: .neutral, pacingPressure: nil, role: .pull)
        XCTAssertEqual(slack, .derailer(name: "Slack"))
        let scaler = DriftMonitor.classify(bundleIdentifier: "company.thebrowser.Browser", appName: "Arc", browserHost: "scaler.com", displayName: "scaler.com",
                                           category: .neutral, pacingPressure: 0.9, role: .tool)
        XCTAssertEqual(scaler, .other, "A tool for your project is not pseudo-work")
    }

    func testConfirmedRuleBeatsTheWorkToolNeedles() {
        let ghostty = UsageSample(day: .distantPast, appName: "Ghostty", bundleIdentifier: "com.mitchellh.ghostty", outsideFocusSeconds: 60)
        XCTAssertFalse(DerailerClassifier.isDerailer(ghostty))
        XCTAssertTrue(DerailerClassifier.isDerailer(ghostty, confirmedKeys: ["com.mitchellh.ghostty"]))
    }
}

@MainActor
final class AppRolesStoreTests: XCTestCase {
    private var container: ModelContainer!
    private var vm: TimerViewModel!

    private static let schema = Schema([
        Project.self, FocusSession.self, AppSettings.self, TimeSplit.self, BlockProfile.self, AppUsageRecord.self, AppUsageEntry.self,
        TaskIntent.self, CoachInterruption.self, InterventionAttempt.self, BreakLearningEvent.self, IdleDistractionItem.self,
        WeeklyPriority.self, PlannedBlock.self, ProjectGoal.self, GoalKeyResult.self, GoalProgressEntry.self, DailyTask.self,
        BlockStartEvent.self, ActivityHour.self, DayLabel.self, AppRoleRuleRecord.self,
    ])

    override func tearDown() async throws {
        AppUsageTracker.shared.stop()
        vm = nil; container = nil
        try await super.tearDown()
    }

    private func makeVM() throws -> TimerViewModel {
        let context = container.mainContext
        let settings = try context.fetch(FetchDescriptor<AppSettings>()).first ?? { let s = AppSettings(); context.insert(s); return s }()
        let vm = TimerViewModel()
        vm.configureForEvidence(modelContext: context, settings: settings)
        return vm
    }

    func testSingleProjectDaysTeachRolesAndScopedRulesStick() throws {
        container = try ModelContainer(for: Self.schema, configurations: ModelConfiguration(schema: Self.schema, isStoredInMemoryOnly: true))
        let context = container.mainContext
        let learning = Project(name: "Learning"); learning.area = .personal
        let office = Project(name: "Office"); office.area = .work
        context.insert(learning); context.insert(office)
        let cal = Calendar.current
        for back in 1...3 {
            let day = cal.startOfDay(for: Date().addingTimeInterval(-Double(back) * 86_400))
            let block = FocusSession(type: .focus, duration: 1500, project: learning)
            block.startedAt = day.addingTimeInterval(10 * 3600); block.endedAt = block.startedAt.addingTimeInterval(1500); block.completed = true
            context.insert(block)
            context.insert(AppUsageEntry(date: day, appName: "scaler.com", bundleIdentifier: "domain:scaler.com", duringFocusSeconds: 1500, outsideFocusSeconds: 0))
        }
        try context.save()
        vm = try makeVM()

        let book = vm.appRoleBook()
        XCTAssertEqual(book.role(key: "scaler.com", in: .project(learning.id, .own)).role, .tool)
        XCTAssertEqual(book.role(key: "scaler.com", in: .project(learning.id, .own)).source, .learned)

        vm.setAppRole(key: "com.tinyspeck.slackmacgap", kind: .app, name: "Slack", scope: .project(learning.id), role: .tool)
        XCTAssertEqual(vm.appRoleBook().role(key: "com.tinyspeck.slackmacgap", name: "Slack", in: .project(learning.id, .own)).role, .tool)
        XCTAssertEqual(vm.appRoleBook().role(key: "com.tinyspeck.slackmacgap", name: "Slack", in: .project(office.id, .work)).role, .tool)
        vm.setAppRole(key: "com.tinyspeck.slackmacgap", kind: .app, name: "Slack", scope: .project(learning.id), role: .pull)
        XCTAssertEqual(try context.fetch(FetchDescriptor<AppRoleRuleRecord>()).count, 1, "Same key and scope: replaced, not added")
        XCTAssertEqual(vm.appRoleBook().role(key: "com.tinyspeck.slackmacgap", name: "Slack", in: .project(learning.id, .own)).role, .pull)
    }

    /// FOCUSFLOW_LIVE_STORE_COPY=<copy>: prints each project's roles for the apps in its blocks.
    func testRolesOnALiveStoreCopy() throws {
        guard let path = ProcessInfo.processInfo.environment["FOCUSFLOW_LIVE_STORE_COPY"] else { throw XCTSkip("Set FOCUSFLOW_LIVE_STORE_COPY") }
        container = try ModelContainer(for: Self.schema, configurations: ModelConfiguration(schema: Self.schema, url: URL(fileURLWithPath: path)))
        vm = try makeVM()
        let book = vm.appRoleBook(), names = vm.appRoleNames()
        let projects = try container.mainContext.fetch(FetchDescriptor<Project>(predicate: #Predicate { !$0.archived }))
        for key in AppsByProjectSection.rows(book: book, records: []) {
            let cells = projects.map { p -> String in
                let d = book.role(key: key, name: names[key] ?? key, in: .project(p.id, AreaGroup.of(p.areaRaw == nil ? nil : p.area)))
                return "\(p.name)=\(d.role.rawValue)/\(d.source.rawValue)"
            }
            print("ROLES \(names[key] ?? key): \(cells.joined(separator: "  "))")
        }
        if let q = vm.appRoleQuestion() { print("ROLES QUESTION \(q.hook) | \(q.detail)") }
    }
}
