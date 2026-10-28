import XCTest
import SwiftData
import SwiftUI
@testable import FocusFlow

@MainActor
final class OnboardingTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_793_000_000) // 2026-10-26
    /// A context traps once its container is gone, so the test case holds it.
    private var container: ModelContainer?

    private func makeContext() throws -> (ModelContainer, ModelContext, AppSettings) {
        let schema = Schema([
            Project.self, FocusSession.self, AppSettings.self, TimeSplit.self, BlockProfile.self, AppUsageRecord.self,
            AppUsageEntry.self, TaskIntent.self, CoachInterruption.self, InterventionAttempt.self, BreakLearningEvent.self,
            IdleDistractionItem.self, WeeklyPriority.self, PlannedBlock.self, ProjectGoal.self, GoalKeyResult.self, GoalProgressEntry.self, DailyTask.self,
        ])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        self.container = container
        let context = container.mainContext
        let settings = AppSettings()
        context.insert(settings)
        return (container, context, settings)
    }

    // MARK: Launch

    func testLaunchShowsOnlyForAnEmptyStoreThatNeverFinished() {
        XCTAssertEqual(OnboardingLaunch.decide(completedAt: nil, hasSessions: false), .show)
        XCTAssertEqual(OnboardingLaunch.decide(completedAt: nil, hasSessions: true), .markDone, "Existing users are not shown the tour")
        XCTAssertEqual(OnboardingLaunch.decide(completedAt: now, hasSessions: false), OnboardingLaunch.none)
        XCTAssertEqual(OnboardingLaunch.decide(completedAt: now, hasSessions: true), OnboardingLaunch.none)
    }

    func testStepsRunInOrder() {
        XCTAssertEqual(OnboardingStep.allCases.count, 5)
        XCTAssertEqual(OnboardingStep.welcome.next, .priority)
        XCTAssertNil(OnboardingStep.start.next)
        XCTAssertNil(OnboardingStep.welcome.previous)
    }

    // MARK: Draft

    func testContinueNeedsANameAndAResult() {
        var draft = OnboardingDraft()
        XCTAssertTrue(draft.canContinue(from: .welcome))
        XCTAssertFalse(draft.canContinue(from: .priority))
        draft.projectName = "  "
        XCTAssertFalse(draft.canContinue(from: .priority))
        draft.apply(OnboardingProjectPreset.all[0])
        XCTAssertTrue(draft.canContinue(from: .priority))
        XCTAssertFalse(draft.canContinue(from: .goal))
        draft.apply(OnboardingResultPreset.suggestions(for: .learning)[0])
        XCTAssertTrue(draft.canContinue(from: .goal))
    }

    func testPresetSetsKindColourAndIcon() {
        var draft = OnboardingDraft()
        draft.apply(OnboardingProjectPreset.all.first { $0.name == "Reading" }!)
        XCTAssertEqual(draft.area, .personal)
        XCTAssertEqual(draft.color, "indigo")
        XCTAssertEqual(draft.icon, "book.fill")
        XCTAssertFalse(OnboardingProjectPreset.all.contains { $0.area == .work }, "A #1 preset is never Work: the honest split leaves Work out of own work")
        draft.apply(OnboardingProjectPreset.all.first { $0.name == "Side project" }!)
        draft.setArea(.learning)
        XCTAssertEqual(draft.icon, "hammer.fill", "A preset's own icon is kept")
        draft.icon = ProjectArea.work.symbol
        draft.setArea(.learning)
        XCTAssertEqual(draft.icon, ProjectArea.learning.symbol, "A kind's default icon follows the kind")
    }

    func testPrefillUsesTheRankedProjectAndSavedChoices() throws {
        let (_, context, settings) = try makeContext()
        settings.coachStyleRawValue = CoachStyle.gentle.rawValue
        settings.notchCompanionEnabled = false
        let office = Project(name: "Office", color: "blue")
        let learning = Project(name: "Learning", color: "purple", icon: "book.fill")
        learning.priorityRank = 1
        learning.area = .learning
        learning.dailyTargetMinutes = 120
        context.insert(office)
        context.insert(learning)

        let draft = OnboardingDraft(projects: [office, learning], settings: settings)
        XCTAssertEqual(draft.existingProjectID, learning.id)
        XCTAssertEqual(draft.projectName, "Learning")
        XCTAssertEqual(draft.icon, "book.fill")
        XCTAssertEqual(draft.dailyMinutes, 120)
        XCTAssertEqual(draft.coachStyle, .gentle)
        XCTAssertFalse(draft.notchEnabled)

        let unranked = OnboardingDraft(projects: [office, Project(name: "Other")], settings: nil)
        XCTAssertNil(unranked.existingProjectID, "With several unranked projects nothing is guessed")
    }

    // MARK: Copy

    func testPaceAndQuotaRoundLikeTheLevers() {
        var draft = OnboardingDraft()
        draft.resultTitle = "Practice problems"
        draft.resultTarget = 60
        draft.deadlineDays = 30
        XCTAssertEqual(draft.paceText, "2/day for 1 month")
        XCTAssertEqual(draft.dailyQuota, 2)
        draft.resultTarget = 90
        XCTAssertEqual(draft.dailyQuota, 3, "3.0 stays 3")
        draft.resultTarget = 10
        XCTAssertEqual(draft.paceText, "1 every 3 days for 1 month")
        XCTAssertEqual(draft.dailyQuota, 1)
        XCTAssertEqual(draft.resultUnit(1), "practice problem")
        XCTAssertEqual(draft.resultUnit(2), "practice problems")
        draft.resultTitle = "Classes"
        XCTAssertEqual(draft.resultUnit(1), "class")
        draft.resultTitle = "Lessons"
        XCTAssertEqual(draft.resultUnit(1), "lesson")
        draft.resultTitle = "Progress"
        XCTAssertEqual(draft.resultUnit(1), "progress")
    }

    func testCoachPreviewUsesYourOwnGoal() {
        var draft = OnboardingDraft()
        draft.projectName = "Interview prep"
        draft.resultTitle = "Practice problems"
        draft.resultTarget = 60
        draft.deadlineDays = 30
        XCTAssertEqual(draft.coachPreview(.gentle).hook, "Today's step: 2 practice problems?")
        XCTAssertEqual(draft.coachPreview(.data).hook, "Practice problems: 0 of 60 · 2/day · 30d left.")
        XCTAssertEqual(draft.coachPreview(.challenger).hook, "30 days. 60 practice problems.")
        XCTAssertEqual(draft.coachPreview(.challenger).line, "Today's lever: 2 practice problems. Start the first one.")

        draft.addsGoal = false
        XCTAssertEqual(draft.coachPreview(.gentle).hook, "Ready for 5 minutes on Interview prep?")
        XCTAssertTrue(draft.coachPreview(.data).hook.contains("of 60 min today"))
    }

    // MARK: Commit

    func testCommitCreatesTheNumberOneProjectGoalAndSettings() throws {
        let (_, context, settings) = try makeContext()
        let old = Project(name: "Office", color: "blue")
        old.priorityRank = 1
        context.insert(old)

        var draft = OnboardingDraft()
        draft.apply(OnboardingProjectPreset.all[0]) // Interview prep, learning
        draft.dailyMinutes = 150
        draft.apply(OnboardingResultPreset(title: "Practice problems", target: 60))
        draft.coachStyle = .data
        draft.notchEnabled = false

        let top = try XCTUnwrap(draft.commit(projects: [old], goals: [], settings: settings, in: context, now: now))
        XCTAssertEqual(top.name, "Interview prep")
        XCTAssertEqual(top.priorityRank, 1)
        XCTAssertEqual(top.area, .learning)
        XCTAssertEqual(top.dailyTargetMinutes, 150)
        XCTAssertEqual(top.targetWeekdaysOnly, false)
        XCTAssertEqual(old.priorityRank, 2, "The old #1 moves down")

        let goal = try XCTUnwrap(try context.fetch(FetchDescriptor<ProjectGoal>()).first)
        XCTAssertEqual(goal.projectID, top.id)
        XCTAssertTrue(goal.isBossFight)
        XCTAssertTrue(goal.title.hasPrefix("60 practice problems by "))
        XCTAssertEqual(goal.sortedKeyResults.map(\.title), ["Practice problems"])
        XCTAssertEqual(goal.sortedKeyResults.first?.target, 60)
        XCTAssertEqual(Calendar.current.dateComponents([.day], from: goal.startDate, to: goal.deadline).day, 30)

        XCTAssertEqual(settings.coachStyle, .data)
        XCTAssertFalse(settings.coachPauseScreenEnabled, "The pause screen is Challenger's")
        XCTAssertEqual(settings.notchCompanionEnabled, false)
        let firstTask = try XCTUnwrap(try context.fetch(FetchDescriptor<DailyTask>()).first)
        XCTAssertEqual(firstTask.title, "2 practice problems")
        XCTAssertEqual(firstTask.keyResultID, goal.sortedKeyResults.first?.id)
        XCTAssertEqual(firstTask.amount, 2)
        XCTAssertEqual(settings.onboardingCompletedAt, now)
        XCTAssertEqual(settings.dailyFocusGoal, 150 * 60, "Own work sets the daily goal")
        XCTAssertGreaterThanOrEqual(settings.dailyStretchGoal, settings.dailyFocusGoal)
    }

    func testCommitOnAnExistingProjectKeepsItAndRespectsAnExistingBossFight() throws {
        let (_, context, settings) = try makeContext()
        let office = Project(name: "Office", color: "blue")
        let learning = Project(name: "Learning", color: "purple")
        context.insert(office)
        context.insert(learning)
        let boss = ProjectGoal(title: "Interview-ready", projectID: learning.id, deadline: now.addingTimeInterval(20 * 86_400), isBossFight: true)
        context.insert(boss)
        settings.dailyFocusGoal = 7200

        var draft = OnboardingDraft()
        draft.select(office)
        draft.setArea(.work)
        draft.dailyMinutes = 180
        draft.apply(OnboardingResultPreset(title: "Docs written", target: 4))

        let top = draft.commit(projects: [office, learning], goals: [boss], settings: settings, in: context, now: now)
        XCTAssertEqual(top?.id, office.id)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Project>()), 2, "No new project")
        XCTAssertEqual(office.priorityRank, 1)
        XCTAssertEqual(office.targetWeekdaysOnly, true, "Work targets are weekdays only")
        XCTAssertEqual(settings.dailyFocusGoal, 7200, "Work doesn't change the own-work goal")
        let added = try context.fetch(FetchDescriptor<ProjectGoal>()).first { $0.projectID == office.id }
        XCTAssertEqual(added?.isBossFight, false, "Only one boss fight")
    }

    func testCommitWithoutAGoalOrProjectOnlySavesChoices() throws {
        let (_, context, settings) = try makeContext()
        var draft = OnboardingDraft()
        draft.coachStyle = .gentle
        XCTAssertNil(draft.commit(projects: [], goals: [], settings: settings, in: context, now: now))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Project>()), 0)
        XCTAssertEqual(settings.coachStyle, .gentle)
        XCTAssertEqual(settings.onboardingCompletedAt, now)

        draft.projectName = "Writing"
        draft.resultTitle = "Posts"
        draft.addsGoal = false
        draft.commit(projects: [], goals: [], settings: settings, in: context, now: now)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ProjectGoal>()), 0, "Skip goal writes no goal")
    }

    func testSettingsOffersTheTourAgain() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let settings = try String(contentsOf: root.appendingPathComponent("Sources/FocusFlow/Views/Companion/SettingsView.swift"), encoding: .utf8)
        XCTAssertTrue(settings.contains("Button(\"Show Tour\") { timerVM.openOnboarding?() }"))
        let app = try String(contentsOf: root.appendingPathComponent("Sources/FocusFlow/FocusFlowApp.swift"), encoding: .utf8)
        XCTAssertTrue(app.contains("Window(\"Welcome to FocusFlow\", id: \"onboarding\")"))
        XCTAssertTrue(app.contains("showOnboardingIfNeeded()"))
    }

    // MARK: Captures (layout only; glass renders wrong off-screen)

    func testCaptureOnboardingSteps() throws {
        guard let dir = ProcessInfo.processInfo.environment["FOCUSFLOW_CAPTURE_OUTPUT_DIR"], !dir.isEmpty else {
            throw XCTSkip("Set FOCUSFLOW_CAPTURE_OUTPUT_DIR to capture")
        }
        let output = URL(fileURLWithPath: dir).appendingPathComponent("onboarding", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let (container, context, settings) = try makeContext()
        let existing = Project(name: "Office", color: "blue", icon: "briefcase.fill")
        context.insert(existing)
        try context.save()
        let vm = TimerViewModel()
        vm.configureForEvidence(modelContext: context, settings: settings)

        var filled = OnboardingDraft()
        filled.apply(OnboardingProjectPreset.all[0])
        filled.dailyMinutes = 120
        filled.apply(OnboardingResultPreset(title: "Practice problems", target: 60))

        for dark in [false, true] {
            for step in OnboardingStep.allCases {
                let draft = step == .priority && !dark ? OnboardingDraft() : filled
                let view = OnboardingView(step: step, draft: draft, now: now)
                    .environment(vm)
                    .modelContainer(container)
                    .environment(\.modelContext, context)
                    .environment(\.colorScheme, dark ? .dark : .light)
                let host = NSHostingView(rootView: view)
                host.frame = NSRect(origin: .zero, size: OnboardingView.size)
                let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                host.appearance = appearance
                let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.appearance = appearance
                window.contentView = host
                window.displayIfNeeded()
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
                host.layoutSubtreeIfNeeded()
                let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                appearance?.performAsCurrentDrawingAppearance { host.cacheDisplay(in: host.bounds, to: rep) }
                let name = "\(step.rawValue + 1)_\(String(describing: step))_\(dark ? "dark" : "light").png"
                try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: output.appendingPathComponent(name))
                window.close()
            }
        }
    }
}
