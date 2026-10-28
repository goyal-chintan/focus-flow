import XCTest
@testable import FocusFlow

final class ReviewContractsTests: XCTestCase {
    private func sessionCompleteSource() throws -> String {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repoRoot = testsDirectory.deletingLastPathComponent().deletingLastPathComponent()
        let sourceURL = repoRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("FocusFlow")
            .appendingPathComponent("Views")
            .appendingPathComponent("SessionCompleteWindow.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    /// Screen audit 2026-10-28: one stage; a sticky footer with the earned break (a menu offers
    /// 5 min), the next block on the next task, and Done for today.
    func testSessionCompleteFooterOffersEarnedBreakNextBlockAndDoneForToday() throws {
        let source = try sessionCompleteSource()

        XCTAssertFalse(source.contains("enum CompletionStage"), "The block-end window has one stage.")
        XCTAssertFalse(source.contains("title: \"Continue\""), "No Continue to a second stage.")
        XCTAssertTrue(
            source.contains("LiquidActionButton(title: title, icon: \"cup.and.saucer.fill\", role: .primary)"),
            "The earned break stays the visually prioritized action (no skip-break bias)."
        )
        XCTAssertTrue(
            source.contains("saveAndDismiss(action: .takeBreak(duration: timerVM.suggestedEarnedBreakSeconds))"),
            "The break button takes the earned break."
        )
        XCTAssertTrue(
            source.contains("Button(\"Break 5 min\")") && source.contains("saveAndDismiss(action: .takeBreak(duration: 300))"),
            "A menu still offers the plain 5 minute break."
        )
        XCTAssertTrue(
            source.contains("LiquidActionButton(title: startTitle, icon: \"play.fill\", role: .secondary)"),
            "Starting the next block stays a secondary action."
        )
        XCTAssertTrue(source.contains("saveAndDismiss(action: .continueFocusing, prepare: prepareNextStart)"))
        XCTAssertTrue(source.contains("\"Done for today\"") && source.contains("saveAndDismiss(action: .endSession)"))
        XCTAssertTrue(source.contains("timerVM.discardManualStop()"), "A manual stop can still be discarded.")
    }

    func testSessionCompleteClearsActionStateOnAppear() throws {
        let source = try sessionCompleteSource()
        XCTAssertTrue(
            source.contains("hasHandledAction = false"),
            "SessionCompleteWindow should clear hasHandledAction on each appearance."
        )
    }

    /// Block-end logging (screen audit 2026-10-28): no mood, no free-text note; ticks become the
    /// achievement; reminders only with Reminders sync on.
    func testSessionCompleteClearsReflectionDraftsOnAppear() throws {
        let source = try sessionCompleteSource()

        XCTAssertFalse(source.contains("MoodSelector"), "Mood is removed from the block-end window.")
        XCTAssertFalse(source.contains("carryForwardNote"), "The free-text carry-forward note is replaced by Next step tasks.")
        XCTAssertFalse(source.contains("TextEditor("), "Nothing free-text the app then ignores.")
        XCTAssertTrue(source.contains("mood: nil"), "saveReflection no longer receives a mood.")
        XCTAssertTrue(source.contains("achievement: achievement"), "The achievement saved is the ticked tasks.")
        XCTAssertTrue(source.contains("$0.isDone && $0.sessionID == sessionID"), "Achievement = tasks ticked in this block.")
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
        XCTAssertTrue(
            source.contains("onAttachReminder: settings?.remindersIntegrationEnabled == true ? { showReminderPicker = true } : nil"),
            "Attach reminder shows only with Reminders sync on; otherwise no reminders UI at all."
        )
        XCTAssertFalse(source.contains("Enable Reminders sync in Settings"), "No reminders UI when sync is off.")
        XCTAssertTrue(
            source.contains("settings?.remindersIntegrationEnabled == true ? selectedReminderItems.map(\\.id) : []"),
            "Linked reminders are still completed when used."
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
        // The four rows share one `menuRow` helper (priorities-goals redesign), so the pattern appears
        // once there and every row must go through it.
        XCTAssertGreaterThanOrEqual(matches, 1, "Expected the full-row hit target pattern in the project-form dropdown row")
        for section in ["blockProfileSection", "workModeSection", "guardianSensitivitySection", "difficultyBiasSection"] {
            let body = source.components(separatedBy: "private var \(section): some View {").last ?? ""
            XCTAssertTrue(body.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("menuRow("), "\(section) must use the full-width menuRow")
        }
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

        XCTAssertTrue(source.contains(".background(AppLaunchBridge(timerVM: timerVM, modelContext: container.mainContext)"))
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

        // Native bordered Form buttons supply the macOS hit target; no custom 44pt frame.
        XCTAssertTrue(source.contains("Button(\"Open Screen Recording Settings\")"))
    }

    func testFocusFlowBundlesDeclareAppleEventsUsageDescriptionEverywhere() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repoRoot = testsDirectory.deletingLastPathComponent().deletingLastPathComponent()
        let requiredFiles = [
            "Sources/FocusFlow/Info.plist",
            "Scripts/run.sh",
            "Scripts/build-dmg.sh",
            "Scripts/install.sh"
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

        // Native bordered Form buttons supply the macOS hit target; no custom 44pt frame.
        XCTAssertTrue(source.contains("Button(\"Open Automation Settings\")"))
    }

    func testSettingsSceneUsesNativeFormsWithSinglePermissionSurface() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repoRoot = testsDirectory.deletingLastPathComponent().deletingLastPathComponent()
        let sourceURL = repoRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("FocusFlow")
            .appendingPathComponent("Views")
            .appendingPathComponent("Companion")
            .appendingPathComponent("SettingsView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        // Settings is a native Settings scene: one Permissions tab (raw value still
        // "integrations") holds every permission surface, and About lives in the app menu.
        XCTAssertTrue(source.contains("case integrations"))
        XCTAssertTrue(source.contains("case .integrations: \"Permissions\""))
        XCTAssertTrue(source.contains("case .integrations: \"lock.shield\""))
        XCTAssertFalse(source.contains("\"Integrations & Permissions\""))
        XCTAssertTrue(source.contains("permissionsSection"))
        XCTAssertTrue(source.contains(".formStyle(.grouped)"))
        XCTAssertFalse(source.contains("aboutSection"))
        XCTAssertFalse(source.contains("LiquidGlassPanel"))
        XCTAssertFalse(source.contains("ToggleRow"))
    }

    /// The native Settings `TabView` swaps hosting controllers and cannot animate. The scene
    /// now uses its own toolbar tab bar and one container whose page is keyed by the tab.
    func testSettingsTabSwitchUsesSelectionKeyedTransitionContainer() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repoRoot = testsDirectory.deletingLastPathComponent().deletingLastPathComponent()
        let viewsRoot = repoRoot.appendingPathComponent("Sources/FocusFlow/Views")
        let settingsSource = try String(contentsOf: viewsRoot.appendingPathComponent("Companion/SettingsView.swift"), encoding: .utf8)
        let barSource = try String(contentsOf: viewsRoot.appendingPathComponent("Settings/SettingsTabBar.swift"), encoding: .utf8)
        let appSource = try String(contentsOf: repoRoot.appendingPathComponent("Sources/FocusFlow/FocusFlowApp.swift"), encoding: .utf8)

        // No native TabView: the root is the custom container plus a principal toolbar bar.
        XCTAssertFalse(settingsSource.contains("TabView(selection:"))
        XCTAssertFalse(settingsSource.contains(".tabItem"))
        XCTAssertTrue(settingsSource.contains("SettingsTabContainer("))
        XCTAssertTrue(settingsSource.contains("ToolbarItem(placement: .principal)"))
        XCTAssertTrue(settingsSource.contains("SettingsTabBar(selection: shownTab)"))
        XCTAssertTrue(settingsSource.contains(".navigationTitle(shownTab.title)"))
        XCTAssertTrue(settingsSource.contains("SettingsTabShortcuts(selection: $selectedTab)"))
        // settingsRequestedTab goes through the animated selection path.
        XCTAssertTrue(settingsSource.contains("SettingsTab.consumeRequestedTab()"))
        XCTAssertTrue(settingsSource.contains("selectedTab = requested"))

        // The page is keyed by the tab and carries the directional transition; the container
        // animates on the same value and keeps one fixed size.
        XCTAssertTrue(barSource.contains(".id(tab)"))
        XCTAssertTrue(barSource.contains(".transition(SettingsTabMotion.transition(direction: direction, reduceMotion: reduceMotion))"))
        XCTAssertTrue(barSource.contains("value: tab"))
        XCTAssertTrue(barSource.contains(".frame(width: SettingsLayout.width, height: SettingsLayout.height)"))
        // Highlight slides between items; no glass on content.
        XCTAssertTrue(barSource.contains(".matchedGeometryEffect(id: \"settings.tabBar.highlight\""))
        XCTAssertTrue(barSource.contains("value: selection"))
        XCTAssertTrue(barSource.contains(".accessibilityAddTraits(isSelected ? [.isSelected] : [])"))
        XCTAssertFalse(barSource.contains(".glassEffect("))

        // The Settings scene keeps a fixed content size.
        let settingsRange = try XCTUnwrap(appSource.range(of: "Settings {"))
        let settingsScene = String(appSource[settingsRange.lowerBound...].prefix(600))
        XCTAssertTrue(settingsScene.contains(".windowResizability(.contentSize)"))
    }

    func testCoachSettingsHasStartingSectionAndNoKnobsTheLearnerOwns() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repoRoot = testsDirectory.deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(
            contentsOf: repoRoot.appendingPathComponent("Sources/FocusFlow/Views/Settings/CoachSettingsTab.swift"),
            encoding: .utf8
        )

        // Four groups (screen audit): Style, Starting, Limits, During a block.
        for header in ["Text(\"Style\")", "Text(\"Starting\")", "Text(\"Limits\")", "Text(\"During a block\")"] {
            XCTAssertTrue(source.contains(header), header)
        }
        XCTAssertTrue(source.contains("Text(\"Help me start\")"))
        XCTAssertTrue(source.contains("settings.antiProcrastinationEnabled = newValue"))
        XCTAssertTrue(source.contains("settings.coachIdleStarterEnabled = newValue"))
        XCTAssertTrue(source.contains("Toggle(\"Show drift time in the menu bar\", isOn: bind(\\.coachShowDriftInMenuBar))"))
        XCTAssertTrue(source.contains("settings.coachPauseScreenEnabled = newValue"))
        XCTAssertTrue(source.contains("Text(\"Pause screen when I spiral in a focus window\")"))
        XCTAssertTrue(source.contains("Toggle(\"⌃⌥Space starts a block from anywhere\", isOn: bind(\\.coachGlobalHotkeyEnabled))"))
        // What v5 learns or what nothing reads has no knob.
        for removed in ["Picker(\"Starter block\"", "Picker(\"Escalation\"", "DisclosureGroup(\"Advanced\"",
                        "First reminder after", "WeeklyPrioritiesSection(", "coachBringAppToFrontOnStrongPrompt",
                        "coachAutoOpenPopoverOnStrongPrompt"] {
            XCTAssertFalse(source.contains(removed), removed)
        }
        // Offer, don't force: the style change only shows the row.
        XCTAssertTrue(source.contains("Pause screen is on. Turn off for this style?"))
        XCTAssertTrue(source.contains("bind(\\.coachStyle, onSet: styleDidChange)"))
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

    func testStatsWindowUsesResizableMinSizeAndFollowsSystemAppearance() throws {
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

        XCTAssertTrue(statsWindowSource.contains(".windowResizability(.contentMinSize)"))
        XCTAssertTrue(statsWindowSource.contains(".defaultSize(width: 960, height: 640)"))
        XCTAssertTrue(statsWindowSource.contains(".frame(minWidth: 780, minHeight: 540)"))
        XCTAssertFalse(statsWindowSource.contains(".preferredColorScheme(.dark)"), "The companion window follows the system appearance.")
    }

    func testCompanionWindowHasFourDestinationsAndMapsRetiredTabs() {
        XCTAssertEqual(CompanionTab.allCases.map(\.rawValue), ["Today", "Goals", "History", "Insights", "Projects"])
        XCTAssertEqual(CompanionTab.resolve("Calendar"), .history)
        XCTAssertEqual(CompanionTab.resolve("Week"), .history)
        XCTAssertEqual(CompanionTab.resolve("Distractions"), .today)
        XCTAssertEqual(CompanionTab.resolve("Settings"), .today)
        XCTAssertEqual(CompanionTab.resolve("Insights"), .insights)
        XCTAssertNil(CompanionTab.resolve(""))
    }

    func testCompanionScreensUsePlainSurfacesSwiftChartsAndNoUnsourcedClaims() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let companion = testsDirectory.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/FocusFlow/Views/Companion")
        let files = ["CompanionWindowView", "TodayView", "HistoryView", "InsightsView", "ProjectsListView", "CompanionCharts", "CompanionComponents"]
        let sources = try files.map { try String(contentsOf: companion.appendingPathComponent("\($0).swift"), encoding: .utf8) }
        let all = sources.joined(separator: "\n")

        XCTAssertFalse(all.contains("LiquidGlassPanel"), "Content sits on plain sections, not glass panels.")
        XCTAssertFalse(all.contains(".glassEffect("), "No glass on companion content.")
        XCTAssertTrue(all.contains("import Charts"))
        XCTAssertFalse(all.contains("BarChartView("))
        XCTAssertFalse(all.contains("HeatmapView("))
        // User-visible copy only: look inside string literals so identifiers like guardianSensitivity don't count.
        let literals = try NSRegularExpression(pattern: #""[^"\n]*""#)
            .matches(in: all, range: NSRange(all.startIndex..., in: all))
            .compactMap { Range($0.range, in: all).map { String(all[$0]) } }
            .joined(separator: "\n")
        for banned in ["FRAGILE", "25%", "Earned blocks", "Recovered", "Goal runway", "Domain Signals", "Guardian", "Focus Science", "alertness"] {
            XCTAssertFalse(literals.localizedCaseInsensitiveContains(banned), "Companion screens must not show \"\(banned)\".")
        }
        XCTAssertTrue(all.contains("accessibilityReduceMotion"), "Motion must respect Reduce Motion.")
        XCTAssertTrue(all.contains("Rate your sessions after each block to see this"))
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

        // Settings → Distractions is a native grouped Form (2026-10-17 settings polish).
        XCTAssertTrue(source.contains("Suggestions"))
        XCTAssertTrue(source.contains("Distraction rules"))
        XCTAssertTrue(source.contains("Allowed (work)"))
        XCTAssertTrue(source.contains("Add Distraction"))
        XCTAssertTrue(source.contains("Dismiss All"))
        XCTAssertTrue(source.contains("Form {"))
        XCTAssertFalse(source.contains("LiquidActionButton("))
        XCTAssertFalse(source.contains("LiquidGlassPanel"))
        XCTAssertFalse(source.contains("Color.white.opacity("))
    }

    func testDistractionsViewUsesHeaderLevelQuickAddInsteadOfStandaloneAddPanel() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repoRoot = testsDirectory.deletingLastPathComponent().deletingLastPathComponent()
        let sourceURL = repoRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("FocusFlow")
            .appendingPathComponent("Views")
            .appendingPathComponent("Companion")
            .appendingPathComponent("DistractionsView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        // Add lives in the compact summary row at the top of the Form.
        XCTAssertTrue(source.contains("summarySection"))
        XCTAssertTrue(source.contains("Add Rule…"))
        XCTAssertFalse(source.contains("private var addDistractionSection"))
    }

    func testDistractionsQuickAddButtonAvoidsOversizedProminentPillTreatment() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repoRoot = testsDirectory.deletingLastPathComponent().deletingLastPathComponent()
        let sourceURL = repoRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("FocusFlow")
            .appendingPathComponent("Views")
            .appendingPathComponent("Companion")
            .appendingPathComponent("DistractionsView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertFalse(source.contains("Add First Rule"))
        XCTAssertFalse(source.contains(".frame(width: 132)"))
        XCTAssertFalse(source.contains("role: .primary"))
        XCTAssertFalse(source.contains(".glassProminent"))
    }

    func testDistractionsEditorExposesExplicitClearPathsForAppAndWebsiteTargets() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repoRoot = testsDirectory.deletingLastPathComponent().deletingLastPathComponent()
        let sourceURL = repoRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("FocusFlow")
            .appendingPathComponent("Views")
            .appendingPathComponent("Companion")
            .appendingPathComponent("DistractionsView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("Clear selected app"))
        XCTAssertTrue(source.contains("Clear website input"))
    }

    func testDistractionsEditorAvoidsOversizedSheetDefaults() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repoRoot = testsDirectory.deletingLastPathComponent().deletingLastPathComponent()
        let sourceURL = repoRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("FocusFlow")
            .appendingPathComponent("Views")
            .appendingPathComponent("Companion")
            .appendingPathComponent("DistractionsView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertFalse(source.contains(".frame(width: 460)"))
        XCTAssertFalse(source.contains(".frame(minHeight: 620)"))
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

    func testLiquidActionButtonDoesNotAddExtraVerticalBulkToProminentButtons() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repoRoot = testsDirectory.deletingLastPathComponent().deletingLastPathComponent()
        let sourceURL = repoRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("FocusFlow")
            .appendingPathComponent("Views")
            .appendingPathComponent("Components")
            .appendingPathComponent("LiquidActionButton.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("fillsWidth"))
        XCTAssertTrue(source.contains(".padding(.horizontal, LiquidDesignTokens.Padding.controlHorizontal)"))
        XCTAssertFalse(source.contains(".padding(.vertical, LiquidDesignTokens.Padding.controlVertical)"))
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
                .appendingPathComponent("TodayView.swift"),
            encoding: .utf8
        )
        let weeklySource = try String(
            contentsOf: repoRoot
                .appendingPathComponent("Sources")
                .appendingPathComponent("FocusFlow")
                .appendingPathComponent("Views")
                .appendingPathComponent("Companion")
                .appendingPathComponent("HistoryView.swift"),
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
                .appendingPathComponent("TodayView.swift"),
            encoding: .utf8
        )
        let weeklySource = try String(
            contentsOf: repoRoot
                .appendingPathComponent("Sources")
                .appendingPathComponent("FocusFlow")
                .appendingPathComponent("Views")
                .appendingPathComponent("Companion")
                .appendingPathComponent("HistoryView.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(todaySource.contains("AppUsageTracker.shared.currentFrontmostBundleId"))
        XCTAssertFalse(weeklySource.contains("AppUsageTracker.shared.currentFrontmostBundleId"))
        XCTAssertFalse(todaySource.contains("captureAvailability:"))
        XCTAssertFalse(weeklySource.contains("captureAvailability:"))
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

    // MARK: - Idle distraction alert pipeline contracts

    func testDistractionViewShowsWarningWhenDomainCollectionIsOff() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repoRoot = testsDirectory.deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(
            contentsOf: repoRoot
                .appendingPathComponent("Sources")
                .appendingPathComponent("FocusFlow")
                .appendingPathComponent("Views")
                .appendingPathComponent("Companion")
                .appendingPathComponent("DistractionsView.swift"),
            encoding: .utf8
        )

        // When coachCollectRawDomains is off (the default) website distraction rules cannot
        // fire because browser domain tracking is suppressed for privacy. The view must warn
        // the user so they know why their YouTube rule is not triggering alerts.
        XCTAssertTrue(
            source.contains("coachCollectRawDomains") || source.contains("domain tracking"),
            "DistractionsView must surface a warning or guidance when browser domain tracking is off."
        )
    }

    func testIdleDistractionNotificationUsesFrontmostContextualMessageNotGenericSummary() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repoRoot = testsDirectory.deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(
            contentsOf: repoRoot
                .appendingPathComponent("Sources")
                .appendingPathComponent("FocusFlow")
                .appendingPathComponent("ViewModels")
                .appendingPathComponent("TimerViewModel.swift"),
            encoding: .utf8
        )

        // The idle-starter notification body must use the decision.message (which includes
        // the specific app name via contextualMessage) rather than the generic opportunity
        // summary so users know WHY they're being nudged.
        XCTAssertFalse(
            source.contains("body: opportunityContext.summary"),
            "Notification body must not use the generic opportunityContext.summary — use decision.message instead so the specific distraction app is named."
        )
    }

    func testIdlePromptsAreOnScreenAndNeverStealFocus() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repoRoot = testsDirectory.deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(
            contentsOf: repoRoot.appendingPathComponent("Sources/FocusFlow/ViewModels/TimerViewModel.swift"),
            encoding: .utf8
        )
        // Coach v2 (companion redesign §5): the on-screen panel is the primary idle surface and
        // notifications are opt-in. The idle path must not depend on notification permission
        // and must not open the retired coach window or activate the app.
        let idleRange = try XCTUnwrap(source.range(of: "func evaluateIdleStarterIntervention("))
        let deliverEnd = try XCTUnwrap(source.range(of: "private func updateCoachDebugReadout("))
        let idleSource = String(source[idleRange.lowerBound..<deliverEnd.lowerBound])
        XCTAssertTrue(idleSource.contains("coachNotificationsEnabled") || source.contains("settings.coachNotificationsEnabled && NotificationService.shared.authorizationState == .authorized"))
        XCTAssertFalse(idleSource.contains("requestAppActivation"))
        XCTAssertFalse(source.contains("openCoachInterventionWindow"))
        XCTAssertTrue(idleSource.contains("presentCoachPanel("))
    }

    func testCoachPanelIsNonActivatingFloatingAndJoinsAllSpaces() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repoRoot = testsDirectory.deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(
            contentsOf: repoRoot.appendingPathComponent("Sources/FocusFlow/Views/CoachPanel/CoachPanelController.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(source.contains(".nonactivatingPanel"), "The coach panel must not activate FocusFlow.")
        // Typing in the current app continues: the panel is shown with orderFrontRegardless and
        // only becomes key when the user clicks it (then ⏎ = primary, Esc = Not now).
        XCTAssertTrue(source.contains("panel.orderFrontRegardless()"), "Typing in the current app must continue.")
        XCTAssertFalse(source.contains("makeKeyAndOrderFront"), "Showing the panel must not take focus.")
        XCTAssertTrue(source.contains("override var canBecomeMain: Bool { false }"))
        XCTAssertTrue(source.contains("override func cancelOperation"), "Esc = Not now once clicked.")
        XCTAssertTrue(source.contains("panel.level = .floating"))
        XCTAssertTrue(source.contains(".canJoinAllSpaces") && source.contains(".fullScreenAuxiliary"),
                      "The panel must appear above full-screen apps on other Spaces.")
        XCTAssertTrue(source.contains("accessibilityDisplayShouldReduceMotion"), "Reduce Motion: fade only.")
    }

    func testCoachPanelNotNowOffersFifteenMinutesHourAndDoneForToday() throws {
        XCTAssertEqual(
            CoachPanelPresentation(kind: .startNudge, message: CoachMessageComposer.neutralFallback(isInSession: false)).secondaryActions,
            [.snooze15, .snooze60, .doneForToday]
        )
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repoRoot = testsDirectory.deletingLastPathComponent().deletingLastPathComponent()
        let vmSource = try String(
            contentsOf: repoRoot.appendingPathComponent("Sources/FocusFlow/ViewModels/TimerViewModel.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(
            vmSource.contains("func handleSnooze(minutes:"),
            "TimerViewModel must expose handleSnooze(minutes:) for direct duration-based snooze from the view."
        )
    }
}
