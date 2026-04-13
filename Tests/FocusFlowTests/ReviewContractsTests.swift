import XCTest
@testable import FocusFlow

final class ReviewContractsTests: XCTestCase {
    func testSessionCompleteNextStageShowsPlannedAndSuggestedBreakActions() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repoRoot = testsDirectory.deletingLastPathComponent().deletingLastPathComponent()
        let sourceURL = repoRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("FocusFlow")
            .appendingPathComponent("Views")
            .appendingPathComponent("SessionCompleteWindow.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("title: \"Planned 5m Break\""),
            "SessionCompleteWindow must expose a planned break action in stage 2."
        )
        XCTAssertTrue(
            source.contains("title: \"Suggested Earned Break\""),
            "SessionCompleteWindow must expose a suggested earned break action in stage 2."
        )
        XCTAssertTrue(
            source.contains("gradient: LiquidDesignTokens.Gradient.cycleCompletion(progress: timerVM.cycleProgress)"),
            "SessionCompleteWindow should prioritize reflection/progress completion as the primary CTA."
        )
        XCTAssertTrue(
            source.contains("GradientCTAButton(\n                        title: \"Suggested Earned Break\""),
            "Suggested earned break should be visually prioritized over skip-break actions."
        )
        XCTAssertTrue(
            source.contains("LiquidActionButton(\n                        title: \"Start Next Block\""),
            "Start Next Block should remain a secondary action to avoid skip-break bias."
        )
    }

    func testSessionCompleteResetsToEarnedStageOnAppear() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repoRoot = testsDirectory.deletingLastPathComponent().deletingLastPathComponent()
        let sourceURL = repoRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("FocusFlow")
            .appendingPathComponent("Views")
            .appendingPathComponent("SessionCompleteWindow.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("stage = .earned"),
            "SessionCompleteWindow should reset to earned stage on each appearance."
        )
        XCTAssertTrue(
            source.contains("hasHandledAction = false"),
            "SessionCompleteWindow should clear hasHandledAction on each appearance."
        )
    }

    func testSessionCompleteClearsReflectionDraftsOnAppear() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repoRoot = testsDirectory.deletingLastPathComponent().deletingLastPathComponent()
        let sourceURL = repoRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("FocusFlow")
            .appendingPathComponent("Views")
            .appendingPathComponent("SessionCompleteWindow.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("carryForwardNote = \"\""),
            "SessionCompleteWindow should clear any carry-forward note draft on each appearance."
        )
        XCTAssertTrue(
            source.contains("selectedMood = nil"),
            "SessionCompleteWindow should clear the prior mood selection on each appearance."
        )
        XCTAssertTrue(
            source.contains("showSplits = false"),
            "SessionCompleteWindow should collapse project splits on each appearance."
        )
        XCTAssertTrue(
            source.contains("splits = []"),
            "SessionCompleteWindow should clear split allocations on each appearance."
        )
        XCTAssertTrue(
            source.contains("selectedReminderItems = []"),
            "SessionCompleteWindow should clear reminder selections on each appearance."
        )
        XCTAssertTrue(
            source.contains("capturedReason = nil"),
            "SessionCompleteWindow should clear the prior coach reason confirmation on each appearance."
        )
    }

    func testProjectFormDropdownRowsHaveFullWidthHitTargets() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repoRoot = testsDirectory.deletingLastPathComponent().deletingLastPathComponent()
        let sourceURL = repoRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("FocusFlow")
            .appendingPathComponent("Views")
            .appendingPathComponent("Companion")
            .appendingPathComponent("ProjectFormView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("private var blockProfileSection"))
        XCTAssertTrue(source.contains("private var workModeSection"))
        XCTAssertTrue(source.contains("private var guardianSensitivitySection"))
        XCTAssertTrue(source.contains("private var difficultyBiasSection"))

        // Each dropdown row should provide a full-row hit target, not only text/chevron.
        let hitTargetPattern = try NSRegularExpression(
            pattern: #"\.frame\(maxWidth:\s*\.infinity,\s*alignment:\s*\.leading\)\s*[\r\n\s]*\.contentShape\(Rectangle\(\)\)"#
        )
        let matches = hitTargetPattern.numberOfMatches(
            in: source,
            range: NSRange(source.startIndex..<source.endIndex, in: source)
        )
        XCTAssertGreaterThanOrEqual(matches, 4, "Expected full-row hit target pattern on all project-form dropdown rows")
    }

    func testSettingsPrivacyCopyMatchesDomainCaptureBehavior() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repoRoot = testsDirectory.deletingLastPathComponent().deletingLastPathComponent()
        let sourceURL = repoRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("FocusFlow")
            .appendingPathComponent("Views")
            .appendingPathComponent("Companion")
            .appendingPathComponent("SettingsView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("When off, FocusFlow still tracks frontmost apps and categories. Existing saved domain history stays on this device, but FocusFlow stops collecting and using website domains for new labels and coaching."),
            "SettingsView should explain that disabling detailed domains still keeps app-level tracking active without using domain detail in coaching surfaces."
        )
        XCTAssertFalse(source.contains("saved history. All data stays on this device."))
    }

    func testFocusFlowAppBootstrapsTimerConfigurationBeforePopoverOpen() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repoRoot = testsDirectory.deletingLastPathComponent().deletingLastPathComponent()
        let sourceURL = repoRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("FocusFlow")
            .appendingPathComponent("FocusFlowApp.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains(".background(AppLaunchBridge(timerVM: timerVM, modelContext: container.mainContext))"))
        XCTAssertTrue(source.contains("private struct AppLaunchBridge: View"))
        XCTAssertTrue(source.contains("timerVM.ensureConfigured(modelContext: modelContext)"))
    }

    func testSettingsDomainRecoveryGuidanceCoversDisabledEmptyAndUnavailableStates() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repoRoot = testsDirectory.deletingLastPathComponent().deletingLastPathComponent()
        let sourceURL = repoRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("FocusFlow")
            .appendingPathComponent("Views")
            .appendingPathComponent("Companion")
            .appendingPathComponent("SettingsView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("Detailed domains are off"))
        XCTAssertTrue(source.contains("FocusFlow hasn't captured a valid browser domain yet."))
        XCTAssertTrue(source.contains("FocusFlow reads supported browsers through macOS Automation first"))
        XCTAssertTrue(source.contains("If a browser does not expose a tab URL, Screen Recording lets FocusFlow fall back to browser titles."))
        XCTAssertTrue(source.contains("Screen Recording is off, so FocusFlow can't recover domains from browser title fallback"))
        XCTAssertTrue(source.contains("Safari, Chrome, Arc, Edge, Brave, or Opera"))
    }

    func testSettingsDomainRecoveryCTAUsesAccessibleFullHitTarget() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repoRoot = testsDirectory.deletingLastPathComponent().deletingLastPathComponent()
        let sourceURL = repoRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("FocusFlow")
            .appendingPathComponent("Views")
            .appendingPathComponent("Companion")
            .appendingPathComponent("SettingsView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"settings.domainTracking.openScreenRecordingSettings\")"))
        XCTAssertTrue(source.contains(".accessibilityLabel(\"Open Screen Recording privacy settings\")"))

        let hitTargetPattern = try NSRegularExpression(
            pattern: #"Open Screen Recording Settings[\s\S]*?\.frame\(minHeight:\s*44\)"#
        )
        XCTAssertEqual(
            hitTargetPattern.numberOfMatches(in: source, range: NSRange(source.startIndex..<source.endIndex, in: source)),
            1,
            "Open Screen Recording Settings CTA should keep a 44pt hit target."
        )
    }

    func testFocusFlowBundlesDeclareAppleEventsUsageDescriptionEverywhere() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repoRoot = testsDirectory.deletingLastPathComponent().deletingLastPathComponent()
        let requiredFiles = [
            "Sources/FocusFlow/Info.plist",
            "Scripts/run.sh",
            "Scripts/build-dmg.sh",
            "Scripts/install-and-register-smart.sh"
        ]

        for relativePath in requiredFiles {
            let source = try String(contentsOf: repoRoot.appendingPathComponent(relativePath), encoding: .utf8)
            XCTAssertTrue(
                source.contains("NSAppleEventsUsageDescription"),
                "\(relativePath) must declare NSAppleEventsUsageDescription because browser domain capture sends Apple events."
            )
        }
    }

    func testSettingsDomainRecoveryGuidancePrioritizesAutomationBeforeScreenRecordingFallback() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repoRoot = testsDirectory.deletingLastPathComponent().deletingLastPathComponent()
        let sourceURL = repoRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("FocusFlow")
            .appendingPathComponent("Views")
            .appendingPathComponent("Companion")
            .appendingPathComponent("SettingsView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("FocusFlow reads supported browsers through macOS Automation first"))
        XCTAssertTrue(source.contains("Open Automation Settings"))
        XCTAssertTrue(source.contains("If a browser does not expose a tab URL, Screen Recording lets FocusFlow fall back to browser titles."))
        XCTAssertFalse(source.contains("App activity monitoring does not require a macOS permission prompt."))
        XCTAssertFalse(source.contains("If a browser doesn’t expose a tab URL, turn on Screen Recording so FocusFlow can fall back to browser titles."))
    }

    func testSettingsDomainRecoveryAutomationCTAUsesAccessibleFullHitTarget() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repoRoot = testsDirectory.deletingLastPathComponent().deletingLastPathComponent()
        let sourceURL = repoRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("FocusFlow")
            .appendingPathComponent("Views")
            .appendingPathComponent("Companion")
            .appendingPathComponent("SettingsView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"settings.domainTracking.openAutomationSettings\")"))
        XCTAssertTrue(source.contains(".accessibilityLabel(\"Open Automation privacy settings\")"))

        let hitTargetPattern = try NSRegularExpression(
            pattern: #"Open Automation Settings[\s\S]*?\.frame\(minHeight:\s*44\)"#
        )
        XCTAssertEqual(
            hitTargetPattern.numberOfMatches(in: source, range: NSRange(source.startIndex..<source.endIndex, in: source)),
            1,
            "Open Automation Settings CTA should keep a 44pt hit target."
        )
    }

    func testSettingsViewAddsPermissionHealthSectionAsFinalSurface() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repoRoot = testsDirectory.deletingLastPathComponent().deletingLastPathComponent()
        let sourceURL = repoRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("FocusFlow")
            .appendingPathComponent("Views")
            .appendingPathComponent("Companion")
            .appendingPathComponent("SettingsView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("permissionHealthSection"))
        XCTAssertTrue(source.contains("LiquidSectionHeader(\"Permission & Integration Health\""))
        XCTAssertTrue(source.contains("Notifications"))
        XCTAssertTrue(source.contains("Calendar"))
        XCTAssertTrue(source.contains("Reminders"))
        XCTAssertTrue(source.contains("Browser Automation"))
        XCTAssertTrue(source.contains("Screen Recording"))

        let aboutRange = try XCTUnwrap(source.range(of: "aboutSection"))
        let healthRange = try XCTUnwrap(source.range(of: "permissionHealthSection"))
        XCTAssertLessThan(aboutRange.lowerBound, healthRange.lowerBound)
    }

    func testCompanionWindowUsesProminentDetailSplitViewStyleToAvoidTahoeLayoutLoop() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repoRoot = testsDirectory.deletingLastPathComponent().deletingLastPathComponent()
        let sourceURL = repoRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("FocusFlow")
            .appendingPathComponent("Views")
            .appendingPathComponent("Companion")
            .appendingPathComponent("CompanionWindowView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains(".navigationSplitViewStyle(.prominentDetail)"),
            "CompanionWindowView should use the less aggressive prominent-detail split style so the stats window does not deadlock on macOS Tahoe."
        )
        XCTAssertFalse(
            source.contains(".navigationSplitViewStyle(.balanced)"),
            "CompanionWindowView must not use the balanced split style because it re-enters AppKit layout and freezes the stats window on macOS Tahoe."
        )
    }

    func testStatsWindowUsesContentSizeResizabilityForTahoeLayoutStability() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repoRoot = testsDirectory.deletingLastPathComponent().deletingLastPathComponent()
        let sourceURL = repoRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("FocusFlow")
            .appendingPathComponent("FocusFlowApp.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        let statsWindowRange = try XCTUnwrap(source.range(of: "Window(\"FocusFlow\", id: \"stats\")"))
        let nextWindowRange = try XCTUnwrap(source.range(of: "Window(\"Session Complete\", id: \"session-complete\")"))
        let statsWindowSource = String(source[statsWindowRange.lowerBound..<nextWindowRange.lowerBound])

        XCTAssertTrue(
            statsWindowSource.contains(".windowResizability(.contentSize)"),
            "The stats window scene must opt into content-size resizability so Tahoe applies the companion min size before initial window layout."
        )
    }

    func testCompanionWindowIncludesDistractionsTabAndView() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repoRoot = testsDirectory.deletingLastPathComponent().deletingLastPathComponent()
        let sourceURL = repoRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("FocusFlow")
            .appendingPathComponent("Views")
            .appendingPathComponent("Companion")
            .appendingPathComponent("CompanionWindowView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("case distractions = \"Distractions\""))
        XCTAssertTrue(source.contains("case .distractions:"))
        XCTAssertTrue(source.contains("DistractionsView()"))
    }

    func testDistractionsViewExposesSuggestionsRulesAndManualAdd() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repoRoot = testsDirectory.deletingLastPathComponent().deletingLastPathComponent()
        let sourceURL = repoRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("FocusFlow")
            .appendingPathComponent("Views")
            .appendingPathComponent("Companion")
            .appendingPathComponent("DistractionsView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("Suggestions"))
        XCTAssertTrue(source.contains("Active Rules"))
        XCTAssertTrue(source.contains("Add Distraction"))
        XCTAssertTrue(source.contains("LiquidActionButton("))
        XCTAssertFalse(source.contains("Color.white.opacity("))
        XCTAssertFalse(source.contains("Form {"))
    }

    func testDistractionsViewLoadsInstalledAppsLazilyForEditorFlow() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repoRoot = testsDirectory.deletingLastPathComponent().deletingLastPathComponent()
        let sourceURL = repoRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("FocusFlow")
            .appendingPathComponent("Views")
            .appendingPathComponent("Companion")
            .appendingPathComponent("DistractionsView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("loadInstalledAppsIfNeeded"))
        XCTAssertFalse(source.contains(".onAppear {\n            if installedApps.isEmpty"))
    }

    func testIdleDistractionRuleUpserterReusesAnyActiveMatchAndDismissesSupersededItems() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repoRoot = testsDirectory.deletingLastPathComponent().deletingLastPathComponent()
        let sourceURL = repoRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("FocusFlow")
            .appendingPathComponent("Services")
            .appendingPathComponent("IdleDistractionRuleUpserter.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("existingActiveMatch"))
        XCTAssertFalse(source.contains("$0.source == .manual"))
        XCTAssertTrue(source.contains("existing.status == .pending || existing.status == .active"))
    }

    func testInstalledAppCatalogUsesStandardApplicationDirectories() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repoRoot = testsDirectory.deletingLastPathComponent().deletingLastPathComponent()
        let sourceURL = repoRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("FocusFlow")
            .appendingPathComponent("Services")
            .appendingPathComponent("InstalledAppCatalog.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("urls(for: .applicationDirectory, in: .allDomainsMask)"))
        XCTAssertFalse(source.contains("URL(fileURLWithPath: \"/Applications\")"))
        XCTAssertFalse(source.contains("URL(fileURLWithPath: \"/System/Applications\")"))
    }

    func testSettingsPermissionHealthRowsExposeAccessibleActions() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repoRoot = testsDirectory.deletingLastPathComponent().deletingLastPathComponent()
        let sourceURL = repoRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("FocusFlow")
            .appendingPathComponent("Views")
            .appendingPathComponent("Companion")
            .appendingPathComponent("SettingsView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("settings.permissionHealth.notifications.action"))
        XCTAssertTrue(source.contains("settings.permissionHealth.calendar.action"))
        XCTAssertTrue(source.contains("settings.permissionHealth.reminders.action"))
        XCTAssertTrue(source.contains("settings.permissionHealth.automation.action"))
        XCTAssertTrue(source.contains("settings.permissionHealth.screenRecording.action"))
    }

    func testSettingsViewLoadsPermissionHealthOutsideBodyRenderPath() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repoRoot = testsDirectory.deletingLastPathComponent().deletingLastPathComponent()
        let sourceURL = repoRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("FocusFlow")
            .appendingPathComponent("Views")
            .appendingPathComponent("Companion")
            .appendingPathComponent("SettingsView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("@State private var permissionHealthRows: [PermissionHealthRow] = []"))
        XCTAssertTrue(source.contains("DispatchQueue.global(qos: .utility).async"))
        XCTAssertFalse(
            source.contains("private var permissionHealthRows: [PermissionHealthRow] {"),
            "SettingsView must not synchronously compute permission health rows from body; it freezes the Settings tab while probing browser automation access."
        )
    }

    func testPermissionHealthServiceContractExists() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repoRoot = testsDirectory.deletingLastPathComponent().deletingLastPathComponent()
        let sourceURL = repoRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("FocusFlow")
            .appendingPathComponent("Services")
            .appendingPathComponent("PermissionHealthService.swift")
        let source = (try? String(contentsOf: sourceURL, encoding: .utf8)) ?? ""

        XCTAssertTrue(source.contains("struct PermissionHealthService"))
        XCTAssertTrue(source.contains("enum PermissionHealthStatus"))
        XCTAssertTrue(source.contains("struct PermissionHealthRow"))
        XCTAssertTrue(source.contains("struct BrowserAutomationTargetStatus"))
    }

    func testDomainAnalyticsContractsDoNotExposeDeadUnsupportedRecoveryStates() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repoRoot = testsDirectory.deletingLastPathComponent().deletingLastPathComponent()
        let modelsSource = try String(
            contentsOf: repoRoot
                .appendingPathComponent("Sources")
                .appendingPathComponent("FocusFlow")
                .appendingPathComponent("Models")
                .appendingPathComponent("CompanionAnalyticsModels.swift"),
            encoding: .utf8
        )
        let todaySource = try String(
            contentsOf: repoRoot
                .appendingPathComponent("Sources")
                .appendingPathComponent("FocusFlow")
                .appendingPathComponent("Views")
                .appendingPathComponent("Companion")
                .appendingPathComponent("TodayStatsView.swift"),
            encoding: .utf8
        )
        let weeklySource = try String(
            contentsOf: repoRoot
                .appendingPathComponent("Sources")
                .appendingPathComponent("FocusFlow")
                .appendingPathComponent("Views")
                .appendingPathComponent("Companion")
                .appendingPathComponent("WeeklyStatsView.swift"),
            encoding: .utf8
        )
        let settingsSource = try String(
            contentsOf: repoRoot
                .appendingPathComponent("Sources")
                .appendingPathComponent("FocusFlow")
                .appendingPathComponent("Views")
                .appendingPathComponent("Companion")
                .appendingPathComponent("SettingsView.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(modelsSource.contains("case unsupported"))
        XCTAssertFalse(modelsSource.contains("case captureUnsupported"))
        XCTAssertFalse(modelsSource.contains("case captureUnavailable"))
        XCTAssertFalse(todaySource.contains("case .captureUnsupported"))
        XCTAssertFalse(todaySource.contains("case .captureUnavailable"))
        XCTAssertFalse(weeklySource.contains("case .captureUnsupported"))
        XCTAssertFalse(weeklySource.contains("case .captureUnavailable"))
        XCTAssertFalse(settingsSource.contains("case unsupportedBrowser"))
    }

    func testHistoricalDomainPanelsDoNotDependOnCurrentFrontmostAppState() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repoRoot = testsDirectory.deletingLastPathComponent().deletingLastPathComponent()
        let todaySource = try String(
            contentsOf: repoRoot
                .appendingPathComponent("Sources")
                .appendingPathComponent("FocusFlow")
                .appendingPathComponent("Views")
                .appendingPathComponent("Companion")
                .appendingPathComponent("TodayStatsView.swift"),
            encoding: .utf8
        )
        let weeklySource = try String(
            contentsOf: repoRoot
                .appendingPathComponent("Sources")
                .appendingPathComponent("FocusFlow")
                .appendingPathComponent("Views")
                .appendingPathComponent("Companion")
                .appendingPathComponent("WeeklyStatsView.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(todaySource.contains("AppUsageTracker.shared.currentFrontmostBundleId"))
        XCTAssertFalse(weeklySource.contains("AppUsageTracker.shared.currentFrontmostBundleId"))
        XCTAssertFalse(todaySource.contains("captureAvailability:"))
        XCTAssertFalse(weeklySource.contains("captureAvailability:"))
    }



    func testTodayStatsViewPlacesDomainSignalsAfterSummaryAndBeforeProjects() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repoRoot = testsDirectory.deletingLastPathComponent().deletingLastPathComponent()
        let sourceURL = repoRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("FocusFlow")
            .appendingPathComponent("Views")
            .appendingPathComponent("Companion")
            .appendingPathComponent("TodayStatsView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        let summaryIndex = try XCTUnwrap(source.range(of: "summarySection")?.lowerBound)
        let domainSignalsIndex = try XCTUnwrap(source.range(of: "domainSignalsSection")?.lowerBound)
        let projectsIndex = try XCTUnwrap(source.range(of: "projectsSection")?.lowerBound)

        XCTAssertLessThan(summaryIndex, domainSignalsIndex, "Domain Signals should appear after the summary section.")
        XCTAssertLessThan(domainSignalsIndex, projectsIndex, "Domain Signals should appear before Projects.")
        XCTAssertTrue(source.contains("\"Domain Signals\""))
        XCTAssertTrue(source.contains("CompanionAnalyticsBuilder().build("))
        XCTAssertTrue(source.contains("analyticsReport.today"))
        XCTAssertFalse(source.contains("captureAvailability:"))
        XCTAssertTrue(source.contains("DomainSignalRow("))
        XCTAssertTrue(source.contains("case .trackingDisabled"))
        XCTAssertTrue(source.contains("case .noValidDomainsYet"))
    }

    func testWeeklyStatsViewPlacesDomainPatternsAfterSummaryAndBeforeStreakWithPeriodAwareAnalytics() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repoRoot = testsDirectory.deletingLastPathComponent().deletingLastPathComponent()
        let sourceURL = repoRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("FocusFlow")
            .appendingPathComponent("Views")
            .appendingPathComponent("Companion")
            .appendingPathComponent("WeeklyStatsView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        let summaryIndex = try XCTUnwrap(source.range(of: "summarySection")?.lowerBound)
        let domainPatternsIndex = try XCTUnwrap(source.range(of: "domainPatternsSection")?.lowerBound)
        let streakIndex = try XCTUnwrap(source.range(of: "streakSection")?.lowerBound)

        XCTAssertLessThan(summaryIndex, domainPatternsIndex, "Domain Patterns should appear after the summary section.")
        XCTAssertLessThan(domainPatternsIndex, streakIndex, "Domain Patterns should appear before Streak.")
        XCTAssertTrue(source.contains("\"Domain Patterns\""))
        XCTAssertTrue(source.contains("CompanionAnalyticsBuilder().build("))
        XCTAssertFalse(source.contains("captureAvailability:"))
        XCTAssertTrue(source.contains("selectedPeriod == .week ? \"7 Days\" : \"30 Days\""))
        XCTAssertTrue(source.contains("analyticsReport.trailing7Days.domainRows"))
        XCTAssertTrue(source.contains("analyticsReport.trailing30Days.domainRows"))
        XCTAssertTrue(source.contains("private var periodInterval: DateInterval?"))
        XCTAssertTrue(source.contains("InsightsWindowing.overlappingFocusSessions("))
        XCTAssertTrue(source.contains("DomainSignalRow("))
        XCTAssertTrue(source.contains("case .trackingDisabled"))
        XCTAssertTrue(source.contains("case .noValidDomainsYet"))
    }

    func testDomainSignalRowUsesNonGlassRowsAndExplicitStateLabel() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repoRoot = testsDirectory.deletingLastPathComponent().deletingLastPathComponent()
        let sourceURL = repoRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("FocusFlow")
            .appendingPathComponent("Views")
            .appendingPathComponent("Components")
            .appendingPathComponent("DomainSignalRow.swift")

        guard let source = try? String(contentsOf: sourceURL, encoding: .utf8) else {
            return XCTFail("DomainSignalRow should exist as a shared Today domain row component.")
        }

        XCTAssertTrue(source.contains("Color.white.opacity(0.04)"))
        XCTAssertTrue(source.contains("Label("), "DomainSignalRow should pair icon and text for its state/category indicator.")
        XCTAssertTrue(source.contains(".accessibilityIdentifier("))
        XCTAssertTrue(source.contains(".accessibilityLabel("))
        XCTAssertFalse(source.contains("LiquidGlassPanel"), "Only the section container should use LiquidGlassPanel.")
        XCTAssertFalse(source.contains(".buttonStyle(.glass)"), "Rows should not render as glass controls.")
    }

    func testInsightsViewUsesSharedAnalyticsSnapshotsForGuardianCoachAndAppUsage() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repoRoot = testsDirectory.deletingLastPathComponent().deletingLastPathComponent()
        let sourceURL = repoRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("FocusFlow")
            .appendingPathComponent("Views")
            .appendingPathComponent("Companion")
            .appendingPathComponent("InsightsView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("private var analyticsReport: CompanionAnalyticsReport"),
            "InsightsView should build a shared analytics report instead of recomputing ad hoc windows."
        )
        XCTAssertTrue(
            source.contains("CompanionAnalyticsBuilder().build("),
            "InsightsView should source app usage windows from CompanionAnalyticsBuilder."
        )
        XCTAssertTrue(
            source.contains("analyticsReport.trailing7Days.rows.map"),
            "Coach Report top distractions should use the shared trailing 7-day analytics window."
        )
        XCTAssertTrue(
            source.contains("analyticsReport.today.rows"),
            "Insights app usage should use the shared today snapshot rather than raw entries."
        )
    }

    func testInsightsViewScopesCoachReasonBreakdownToTrailingSevenDaysAndRemovesDeadUsageRecordQuery() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repoRoot = testsDirectory.deletingLastPathComponent().deletingLastPathComponent()
        let sourceURL = repoRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("FocusFlow")
            .appendingPathComponent("Views")
            .appendingPathComponent("Companion")
            .appendingPathComponent("InsightsView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("InsightsWindowing.trailing7DayInterval"),
            "InsightsView should use the shared explicit trailing 7-day helper for coach report inputs."
        )
        XCTAssertTrue(
            source.contains("InsightsWindowing.overlappingFocusSessions"),
            "InsightsView should reuse the shared overlap helper for coach session windowing."
        )
        XCTAssertTrue(
            source.contains("InsightsWindowing.completionRate"),
            "InsightsView should reuse the shared overlap helper for completion-rate math."
        )
        XCTAssertTrue(
            source.contains("coachWindowInterruptions"),
            "Self-reported reasons should come from the coach report window, not all-time interruptions."
        )
        XCTAssertFalse(
            source.contains("@Query(sort: \\AppUsageRecord.date) private var usageRecords: [AppUsageRecord]"),
            "InsightsView should remove the unused usageRecords query after switching to shared analytics snapshots."
        )
    }

    func testInsightsViewScopesHighResistanceScienceTipToCoachWindowTaskIntents() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repoRoot = testsDirectory.deletingLastPathComponent().deletingLastPathComponent()
        let sourceURL = repoRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("FocusFlow")
            .appendingPathComponent("Views")
            .appendingPathComponent("Companion")
            .appendingPathComponent("InsightsView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        let contextualTipsPattern = try NSRegularExpression(
            pattern: #"private var contextualTips: \[ScienceTip\] \{[\s\S]*?let highResistanceIntents = coachWindowTaskIntents\.filter \{ \$0\.expectedResistance >= 4 \}"#
        )

        XCTAssertEqual(
            contextualTipsPattern.numberOfMatches(in: source, range: NSRange(source.startIndex..<source.endIndex, in: source)),
            1,
            "The Focus Science high-resistance tip should use the trailing 7-day coachWindowTaskIntents scope."
        )
    }

    func testInsightsViewSharesStableNowSnapshotAcrossAnalyticsAndCoachWindows() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repoRoot = testsDirectory.deletingLastPathComponent().deletingLastPathComponent()
        let sourceURL = repoRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("FocusFlow")
            .appendingPathComponent("Views")
            .appendingPathComponent("Companion")
            .appendingPathComponent("InsightsView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("private let analyticsSnapshotNow = Date()"),
            "InsightsView should capture one shared now snapshot for the current render."
        )
        XCTAssertTrue(
            source.contains("now: analyticsSnapshotNow"),
            "InsightsView should pass the shared now snapshot into CompanionAnalyticsBuilder."
        )
        XCTAssertTrue(
            source.contains("relativeTo: analyticsSnapshotNow"),
            "Coach report windows should use the same shared now snapshot as analyticsReport."
        )
    }

    func testInsightsViewScopesCompletionMessagingToCoachWindowSessions() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repoRoot = testsDirectory.deletingLastPathComponent().deletingLastPathComponent()
        let sourceURL = repoRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("FocusFlow")
            .appendingPathComponent("Views")
            .appendingPathComponent("Companion")
            .appendingPathComponent("InsightsView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        let behavioralInsightsPattern = try NSRegularExpression(
            pattern: #"private var behavioralInsights: \[BehavioralInsight\] \{[\s\S]*?let coachCompletionSessions = coachWindowSessions[\s\S]*?let completedSessions = coachCompletionSessions\.filter\(\\\.completed\)[\s\S]*?let abandonedSessions = coachCompletionSessions\.filter \{ !\$0\.completed \}"#
        )
        XCTAssertEqual(
            behavioralInsightsPattern.numberOfMatches(in: source, range: NSRange(source.startIndex..<source.endIndex, in: source)),
            1,
            "Focus momentum messaging should use the trailing 7-day coachWindowSessions scope."
        )

        let contextualTipsPattern = try NSRegularExpression(
            pattern: #"private var contextualTips: \[ScienceTip\] \{[\s\S]*?let coachCompletionSessions = coachWindowSessions[\s\S]*?let completionRate = coachCompletionSessions\.isEmpty[\s\S]*?if completionRate < 0\.4 && coachCompletionSessions\.count >= 5"#
        )
        XCTAssertEqual(
            contextualTipsPattern.numberOfMatches(in: source, range: NSRange(source.startIndex..<source.endIndex, in: source)),
            1,
            "Completion challenge coaching should use the trailing 7-day coachWindowSessions scope."
        )
    }

    func testReviewArtifactContractCoversAllCriticalFlows() {
        let expectedFlowIDs: Set<String> = [
            "menu_bar_idle",
            "menu_bar_focusing",
            "menu_bar_paused",
            "menu_bar_overtime",
            "menu_bar_break_overrun",
            "session_complete_focus_complete",
            "session_complete_manual_stop",
            "session_complete_break_complete",
            "session_complete_earned_stage",
            "session_complete_recovery_chips",
            "coach_quick_prompt",
            "coach_strong_window",
            "coach_window_dismiss",
            "settings_calendar_permissions",
            "settings_reminders_permissions",
            "today_stats_view",
            "weekly_stats_view",
            "insights_view_domains",
            "distractions_view",
            "settings_domain_tracking",
            "break_complete_reason_sheet_hidden",
            "break_complete_reason_sheet_visible"
        ]

        let actualFlowIDs = Set(ReviewArtifactContract.requiredFlowIDs)
        XCTAssertEqual(actualFlowIDs, expectedFlowIDs)
    }

    func testReviewArtifactContractBuildsLightAndDarkArtifactPaths() {
        let runID = "sample-run"
        let light = ReviewArtifactContract.requiredArtifactPaths(runID: runID, appearance: .light)
        let dark = ReviewArtifactContract.requiredArtifactPaths(runID: runID, appearance: .dark)

        XCTAssertEqual(light.count, ReviewArtifactContract.requiredFlowIDs.count)
        XCTAssertEqual(dark.count, ReviewArtifactContract.requiredFlowIDs.count)
        XCTAssertTrue(light.allSatisfy { $0.contains("/light/") })
        XCTAssertTrue(dark.allSatisfy { $0.contains("/dark/") })
    }

    func testFlowFixtureSeedContractIncludesCanonicalJourneys() {
        let expectedJourneyIDs: Set<String> = [
            "focus_start_pause_resume_stop",
            "completion_take_break_continue_end",
            "idle_escalation_to_strong_prompt",
            "calendar_event_write_and_update",
            "reminder_create_edit_complete_delete"
        ]

        let actualJourneyIDs = Set(FlowFixtureSeedContract.canonicalFlowIDs)
        XCTAssertEqual(actualJourneyIDs, expectedJourneyIDs)
        XCTAssertEqual(
            Set(FlowFixtureSeedContract.requiredSeedKeys),
            Set(["projects", "sessions", "reminders", "appUsageEntries", "coachRiskLevels"])
        )
    }

    func testAccessibilityContractListsCriticalControlsWithLabels() {
        let controls = AccessibilityContract.criticalControls
        XCTAssertFalse(controls.isEmpty)
        XCTAssertTrue(controls.allSatisfy { !$0.id.isEmpty })
        XCTAssertTrue(controls.allSatisfy { !$0.label.isEmpty })
        XCTAssertTrue(
            controls.contains(
                AccessibilityControlRequirement(
                    id: "settings.domainTracking.openScreenRecordingSettings",
                    label: "Open Screen Recording privacy settings",
                    sourceFile: "Sources/FocusFlow/Views/Companion/SettingsView.swift"
                )
            )
        )
        XCTAssertTrue(
            controls.contains(
                AccessibilityControlRequirement(
                    id: "settings.domainTracking.openAutomationSettings",
                    label: "Open Automation privacy settings",
                    sourceFile: "Sources/FocusFlow/Views/Companion/SettingsView.swift"
                )
            )
        )
        XCTAssertTrue(
            controls.contains(
                AccessibilityControlRequirement(
                    id: "settings.permissionHealth.notifications.action",
                    label: "Review notification permission",
                    sourceFile: "Sources/FocusFlow/Views/Companion/SettingsView.swift"
                )
            )
        )
        XCTAssertTrue(
            controls.contains(
                AccessibilityControlRequirement(
                    id: "settings.permissionHealth.calendar.action",
                    label: "Review Calendar permission",
                    sourceFile: "Sources/FocusFlow/Views/Companion/SettingsView.swift"
                )
            )
        )
        XCTAssertTrue(
            controls.contains(
                AccessibilityControlRequirement(
                    id: "settings.permissionHealth.reminders.action",
                    label: "Review Reminders permission",
                    sourceFile: "Sources/FocusFlow/Views/Companion/SettingsView.swift"
                )
            )
        )
        XCTAssertTrue(
            controls.contains(
                AccessibilityControlRequirement(
                    id: "settings.permissionHealth.automation.action",
                    label: "Review browser Automation permission",
                    sourceFile: "Sources/FocusFlow/Views/Companion/SettingsView.swift"
                )
            )
        )
        XCTAssertTrue(
            controls.contains(
                AccessibilityControlRequirement(
                    id: "settings.permissionHealth.screenRecording.action",
                    label: "Review Screen Recording permission",
                    sourceFile: "Sources/FocusFlow/Views/Companion/SettingsView.swift"
                )
            )
        )
    }

    func testMotionGeometryContractDefinesTransitionAndBaselineCoverage() {
        XCTAssertFalse(MotionGeometryContract.transitionIntents.isEmpty)
        XCTAssertFalse(MotionGeometryContract.geometryBaselines.isEmpty)
        XCTAssertTrue(MotionGeometryContract.transitionIntents.keys.contains("SessionComplete.coachReasonDisclosure"))
        XCTAssertTrue(MotionGeometryContract.geometryBaselines.keys.contains("SessionComplete.breakPane"))
    }
}
