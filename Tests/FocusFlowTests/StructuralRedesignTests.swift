import XCTest
import SwiftUI
import SwiftData
@testable import FocusFlow

/// Structural redesign 2026-10-30: one daily-goal model, Insights' one range, derailer actions,
/// the sleep rule, the Sync rows, block titles, the global-shortcut wording and keyboard shortcuts.
final class StructuralRedesignTests: XCTestCase {
    private var container: ModelContainer?

    override func tearDown() {
        container = nil
        super.tearDown()
    }

    // MARK: Daily goal

    func testDailyGoalFollowsTheCountedProjectsTargetsByDefault() {
        let goal = DailyGoal.resolve(scope: .project(key: "project:a", name: "Learning"), targetMinutes: [240], fixedSeconds: 7200, stretchSeconds: 9000, followsTargets: true)
        XCTAssertEqual(goal.seconds, 4 * 3600, "Learning's 4h target, not the fixed 2h")
        XCTAssertEqual(goal.source, .projectTargets)
        XCTAssertEqual(goal.stretchSeconds, 4 * 3600 + 1800, "Stretch keeps its 30m above the goal")
        XCTAssertEqual(goal.label, "★ Learning")
    }

    func testDailyGoalUsesTheFixedNumberWhenOffOrWithoutTargets() {
        let off = DailyGoal.resolve(scope: .ownWork(keys: []), targetMinutes: [60, 90], fixedSeconds: 7200, stretchSeconds: 9000, followsTargets: false)
        XCTAssertEqual(off.seconds, 7200)
        XCTAssertEqual(off.source, .fixed)
        XCTAssertEqual(off.targetSeconds, 150 * 60, "The sum is still known, to show beside the fixed number")

        let none = DailyGoal.resolve(scope: .allFocus, targetMinutes: [], fixedSeconds: 5400, stretchSeconds: 5400, followsTargets: true)
        XCTAssertEqual(none.seconds, 5400)
        XCTAssertEqual(none.source, .fixed)
        XCTAssertNil(none.targetSeconds)
        XCTAssertEqual(none.stretchSeconds, 5400)
    }

    @MainActor
    func testDailyGoalCountsOnlyTheScopedProjectsTargets() throws {
        let context = try makeContext()
        let learning = Project(name: "Learning")
        learning.area = .learning
        learning.priorityRank = 1
        learning.dailyTargetMinutes = 240
        let office = Project(name: "Office")
        office.area = .work
        office.dailyTargetMinutes = 480
        let side = Project(name: "Side")
        side.area = .personal
        side.dailyTargetMinutes = 60
        [learning, office, side].forEach { context.insert($0) }
        let settings = AppSettings()
        context.insert(settings)

        let ranked = GoalDataBuilder.dailyGoal(projects: [learning, office, side], settings: settings)
        XCTAssertEqual(ranked.scope.label, "★ Learning")
        XCTAssertEqual(ranked.seconds, 240 * 60, "Only the ★ #1 project's target")

        learning.priorityRank = nil
        let own = GoalDataBuilder.dailyGoal(projects: [learning, office, side], settings: settings)
        XCTAssertEqual(own.scope.label, "Own work")
        XCTAssertEqual(own.seconds, 300 * 60, "Learning + Side; the office target never fills the personal goal")

        settings.dailyGoalFollowsTargets = false
        XCTAssertEqual(GoalDataBuilder.dailyGoal(projects: [learning, office, side], settings: settings).seconds, settings.dailyFocusGoal)
    }

    @MainActor
    func testCompanionSnapshotUsesTheResolvedGoalPerDay() throws {
        let context = try makeContext()
        let office = Project(name: "Office")
        office.dailyTargetMinutes = 300
        office.targetWeekdaysOnly = true
        context.insert(office)
        let settings = AppSettings()
        context.insert(settings)
        let calendar = Calendar.current
        let wednesday = calendar.nextDate(after: Date(), matching: DateComponents(hour: 12, weekday: 4), matchingPolicy: .nextTime)!
        let saturday = calendar.nextDate(after: wednesday, matching: DateComponents(hour: 12, weekday: 7), matchingPolicy: .nextTime)!

        let snapshot = CompanionSnapshot(sessions: [], settings: settings, projects: [office], now: wednesday)
        XCTAssertEqual(snapshot.goal, 300 * 60)
        XCTAssertEqual(snapshot.goal(on: wednesday), 300 * 60)
        XCTAssertEqual(snapshot.goal(on: saturday), settings.dailyFocusGoal, "A weekday-only target leaves the fixed goal at the weekend")
    }

    func testScopeSentenceMatchesWhatTheGoalCounts() {
        XCTAssertTrue(GoalScope.allFocus.countsSentence.hasPrefix("Counts every focus block"), "Never claims personal and learning work when the scope is all focus")
        XCTAssertTrue(GoalScope.ownWork(keys: []).countsSentence.contains("Personal and Learning"))
        XCTAssertTrue(GoalScope.project(key: "k", name: "DSA").countsSentence.contains("DSA"))
    }

    // MARK: Insights range

    func testInsightsRangeIntervalsAndLabels() {
        let calendar = Calendar.current
        let now = calendar.date(bySettingHour: 15, minute: 0, second: 0, of: Date())!
        let interval = InsightsRange.month.interval(now: now, calendar: calendar)
        XCTAssertEqual(calendar.dateComponents([.day], from: interval.start, to: calendar.startOfDay(for: now)).day, 29)
        XCTAssertEqual(interval.end, now)
        XCTAssertEqual(InsightsRange.eightWeeks.weeks, 8)
        XCTAssertEqual(InsightsRange.week.phrase, "in the last 7 days")
        XCTAssertEqual(InsightsRange.allCases.map(\.label), ["7 days", "30 days", "8 weeks"])
    }

    // MARK: Derailers

    func testDerailersCarryTheirRuleTargetAndConfirmedState() {
        let analytics = FocusAnalytics()
        let calendar = analytics.calendar
        let today = calendar.startOfDay(for: Date())
        let usage = [
            UsageSample(day: today, appName: "Safari", bundleIdentifier: "domain:youtube.com", outsideFocusSeconds: 1800),
            UsageSample(day: today, appName: "YouTube", bundleIdentifier: "com.google.youtube", outsideFocusSeconds: 600),
            UsageSample(day: calendar.date(byAdding: .day, value: -10, to: today)!, appName: "Netflix", bundleIdentifier: "com.netflix.Netflix", outsideFocusSeconds: 900),
        ]
        let items = analytics.derailers(usage, lastDays: 7, now: Date(), confirmedKeys: ["com.netflix.netflix"])
        let youtube = items.first { $0.name == "YouTube" }
        XCTAssertEqual(youtube?.thisWeekSeconds, 2400)
        XCTAssertEqual(youtube?.target, DerailerTarget(kind: .website, key: "youtube.com"), "The site, with the most time, takes the rule")
        XCTAssertEqual(youtube?.isConfirmed, false)
        let netflix = items.first { $0.name.lowercased().contains("netflix") }
        XCTAssertEqual(netflix?.thisWeekSeconds, 0)
        XCTAssertEqual(netflix?.lastWeekSeconds, 900, "Counted in the 7 days before")
        XCTAssertEqual(netflix?.isConfirmed, true)
        XCTAssertEqual(netflix?.target?.kind, .app)
    }

    @MainActor
    func testMarkingADerailerWritesOneRuleAndItsWorkAnswerHidesIt() throws {
        let context = try makeContext()
        let target = DerailerTarget(kind: .website, key: "YouTube.com")
        try DistractionRuleWriter.mark(target, name: "YouTube", as: .minor, in: context)
        var items = try context.fetch(FetchDescriptor<IdleDistractionItem>())
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.key, "youtube.com")
        XCTAssertEqual(items.first?.severity, .minor)
        XCTAssertEqual(DerailerRuleKeys.from(items).confirmed, ["youtube.com"])

        try DistractionRuleWriter.mark(target, name: "YouTube", as: .allowed, in: context)
        items = try context.fetch(FetchDescriptor<IdleDistractionItem>()).filter { $0.status == .active }
        XCTAssertEqual(items.count, 1, "The same rule changes; no duplicate")
        XCTAssertEqual(DerailerRuleKeys.from(items).allowed, ["youtube.com"])
        let sample = UsageSample(day: Date(), appName: "Safari", bundleIdentifier: "domain:youtube.com", outsideFocusSeconds: 600)
        XCTAssertFalse(DerailerClassifier.isDerailer(sample, allowedKeys: DerailerRuleKeys.from(items).allowed))
    }

    @MainActor
    func testPendingSuggestionsNeedEvidenceAndSortByIt() throws {
        let context = try makeContext()
        func item(_ key: String, evidence: Int, status: IdleDistractionStatus = .pending) -> IdleDistractionItem {
            let item = IdleDistractionItem(key: key, displayName: key, targetKind: .website, severity: .minor, source: .suggested, status: status, evidenceCount: evidence, createdAt: Date(), updatedAt: Date())
            context.insert(item)
            return item
        }
        let threshold = IdleDistractionCatalog.suggestionEvidenceThreshold
        let items = [item("a.com", evidence: threshold), item("b.com", evidence: threshold + 3), item("c.com", evidence: max(0, threshold - 1)), item("d.com", evidence: 9, status: .active)]
        XCTAssertEqual(DistractionSuggestionsList.pending(items).map(\.key), ["b.com", "a.com"])
    }

    // MARK: Settings

    func testSleepRuleReadsAsOneSentence() {
        XCTAssertEqual(SleepRuleRow.sentence(resumeMinutes: 2, endMinutes: 60), "A block pauses while your Mac sleeps, resumes if you're back within 2 min, and ends after 1h asleep.")
        XCTAssertEqual(SleepRuleRow.sentence(resumeMinutes: 0, endMinutes: 30), "A block pauses while your Mac sleeps and ends after 30m asleep.")
        XCTAssertEqual(SleepRuleRow.options([0, 1, 2], including: 3), [0, 1, 2, 3], "A stored value from an earlier build stays selectable")
        XCTAssertEqual(SleepRuleRow.options([0, 1, 2], including: 2), [0, 1, 2])
    }

    func testSettingsTabsAreRegrouped() {
        XCTAssertEqual(SettingsTab.allCases.map(\.title), ["General", "Focus", "Coach", "Distractions", "Permissions & Sync"])
        XCTAssertEqual(SettingsTab(rawValue: "timer"), .timer, "Stored selections from earlier builds still resolve")
        XCTAssertEqual(SettingsTab(rawValue: "integrations")?.title, "Permissions & Sync")
    }

    func testGlobalShortcutIsWordedTheSameEverywhere() throws {
        XCTAssertEqual(CoachStarterBlock.hotkeyHint, "⌃⌥Space starts a short block on your next step, from anywhere")
        let sources = try ["Views/Companion/SettingsView.swift", "Views/Onboarding/OnboardingView.swift", "Views/Settings/CoachSettingsTab.swift"].map(source)
        for text in sources {
            XCTAssertFalse(text.contains("starts a block from anywhere"), "Old Settings wording")
            XCTAssertFalse(text.contains("min anytime"), "Old footer wording")
        }
        XCTAssertTrue(sources[0].contains("CoachStarterBlock.hotkeyAction"))
        XCTAssertTrue(sources[1].contains("CoachStarterBlock.hotkeyAction"))
        XCTAssertFalse(sources[2].contains("coachGlobalHotkeyEnabled"), "The shortcut moved to General")
    }

    // MARK: Projects and keyboard

    func testBlockTitlesPreferIntentThenTaskOverTheProjectName() {
        XCTAssertEqual(SessionRow.title(intent: " Draft intro ", taskTitle: "Chapter 2", achievement: nil, fallback: "Writing"), "Draft intro")
        XCTAssertEqual(SessionRow.title(intent: "", taskTitle: "Chapter 2", achievement: "Shipped", fallback: "Writing"), "Chapter 2")
        XCTAssertEqual(SessionRow.title(intent: nil, taskTitle: nil, achievement: nil, fallback: "Focus block"), "Focus block")
    }

    func testCompanionShortcutsFollowSidebarOrder() {
        XCTAssertEqual(CompanionTab.allCases.map { String($0.shortcutKey.character) }, ["1", "2", "3", "4", "5"])
        XCTAssertEqual(CompanionTab.pages, [.today, .goals, .history, .insights], "Projects are listed by name, not as a page")
        XCTAssertEqual(CompanionDestination.project(UUID()).tab, .projects)
    }

    func testPopoverShortcuts() {
        XCTAssertEqual(PopoverShortcut.start.key, .return)
        XCTAssertEqual(PopoverShortcut.start.modifiers, .command)
        XCTAssertEqual(PopoverShortcut.pause.key, KeyEquivalent("p"))
        XCTAssertEqual(PopoverShortcut.finish.key, KeyEquivalent("."))
    }

    // MARK: Helpers

    @MainActor
    private func makeContext() throws -> ModelContext {
        let schema = Schema([Project.self, FocusSession.self, TimeSplit.self, BlockProfile.self, AppSettings.self, IdleDistractionItem.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        self.container = container
        return container.mainContext
    }

    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent("Sources/FocusFlow").appendingPathComponent(relative), encoding: .utf8)
    }
}
