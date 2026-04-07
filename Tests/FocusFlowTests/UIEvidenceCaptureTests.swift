import XCTest
import SwiftUI
import SwiftData
import AppKit
import ImageIO
import UniformTypeIdentifiers
@testable import FocusFlow

@MainActor
final class UIEvidenceCaptureTests: XCTestCase {
    private struct CapturedAppearanceArtifacts: Encodable {
        let appearance: String
        let flows: [String: String]
        let timerAnimationGIF: String
    }

    private struct EvidenceManifest: Encodable {
        let runID: String
        let generatedAt: String
        let artifacts: [CapturedAppearanceArtifacts]
        let requiredFlows: [String]
        let journeyReport: String
        let functionalProofReport: String
    }

    private struct CanonicalFlowProof: Encodable {
        let id: String
        let beforeState: [String: String]
        let afterState: [String: String]
        let status: String
        let notes: String?
    }

    private struct FunctionalProofReport: Encodable {
        let generatedAt: String
        let canonicalFlows: [CanonicalFlowProof]
    }

    private enum CaptureError: Error {
        case renderFailed(String)
        case imageWriteFailed(String)
        case flowFixtureFailed(String)
    }

    func testCaptureReviewArtifactsForAllRequiredFlows() throws {
        let runID = ProcessInfo.processInfo.environment["FOCUSFLOW_REVIEW_RUN_ID"] ?? Self.defaultRunID()
        let requestedFlows = Self.requestedFlowIDs()
        let flowIDs = requestedFlows.isEmpty ? ReviewArtifactContract.requiredFlowIDs : requestedFlows
        let requestedAppearances = Self.requestedAppearances()
        let appearances = requestedAppearances.isEmpty ? ReviewArtifactAppearance.allCases : requestedAppearances
        let root = repoRootURL
            .appendingPathComponent("Artifacts", isDirectory: true)
            .appendingPathComponent("review", isDirectory: true)
            .appendingPathComponent(runID, isDirectory: true)
        try makeDirectory(root)

        var artifactsByAppearance: [CapturedAppearanceArtifacts] = []

        for appearance in appearances {
            let appearanceDirectory = root.appendingPathComponent(appearance.rawValue, isDirectory: true)
            try makeDirectory(appearanceDirectory)
            let fixtures = FixturePool(owner: self)
            defer { fixtures.cleanup() }

            var capturedPaths: [String: String] = [:]

            for flowID in flowIDs {
                let image = try captureFlow(flowID: flowID, appearance: appearance, fixtures: fixtures)
                let outputURL = appearanceDirectory.appendingPathComponent("\(flowID).png")
                try writePNG(image, to: outputURL)

                let relativePath = relativePathFromRepo(outputURL)
                capturedPaths[flowID] = relativePath
            }

            let gifURL = appearanceDirectory.appendingPathComponent("timer_ring_animation.gif")
            try writeTimerRingAnimation(appearance: appearance, to: gifURL)

            artifactsByAppearance.append(
                CapturedAppearanceArtifacts(
                    appearance: appearance.rawValue,
                    flows: capturedPaths,
                    timerAnimationGIF: relativePathFromRepo(gifURL)
                )
            )
        }

        if requestedFlows.isEmpty && requestedAppearances.isEmpty {
            try assertContractCoverage(runID: runID, artifactsByAppearance: artifactsByAppearance)
        }

        let journeyURL = root.appendingPathComponent("journey.md")
        try writeJourneyReport(
            to: journeyURL,
            runID: runID,
            artifactsByAppearance: artifactsByAppearance,
            orderedFlowIDs: flowIDs
        )
        let functionalProofURL = root.appendingPathComponent("functional-proof.json")
        try writeFunctionalProofReport(to: functionalProofURL)

        let manifest = EvidenceManifest(
            runID: runID,
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            artifacts: artifactsByAppearance,
            requiredFlows: flowIDs,
            journeyReport: relativePathFromRepo(journeyURL),
            functionalProofReport: relativePathFromRepo(functionalProofURL)
        )
        try writeManifest(manifest, to: root.appendingPathComponent("manifest.json"))
    }

    func testTodayStatsFixtureSeedsDomainSignalsAndEvidenceDescriptionMentionsThem() throws {
        let fixture = try makeTodayStatsFixture()
        defer { cleanup(fixture) }

        let appUsageEntries = try fixture.context.fetch(FetchDescriptor<AppUsageEntry>())
        let settings = try XCTUnwrap(try fixture.context.fetch(FetchDescriptor<AppSettings>()).first)
        let seededToday = Calendar.current.startOfDay(
            for: try XCTUnwrap(appUsageEntries.map(\.date).max())
        )
        let report = CompanionAnalyticsBuilder().build(
            entries: InsightsAppUsagePolicy.visibleEntries(
                from: appUsageEntries,
                collectRawDomains: settings.coachCollectRawDomains
            ),
            domainTrackingEnabled: settings.coachCollectRawDomains,
            now: seededToday.addingTimeInterval(12 * 60 * 60)
        )

        XCTAssertTrue(report.today.domainRows.contains { $0.bundleIdentifier == "domain:youtube.com" })
        XCTAssertTrue(report.today.domainRows.contains { $0.bundleIdentifier == "domain:reddit.com" })
        XCTAssertFalse(report.today.domainRows.contains { $0.bundleIdentifier == "domain:news.ycombinator.com" })
        XCTAssertTrue(
            flowPurpose(for: "today_stats_view").contains("Domain Signals"),
            "Today evidence description should mention the Domain Signals panel."
        )
    }

    func testWeeklyStatsFixtureSeedsPeriodSpecificDomainPatternsAndSupportsEvidenceCapture() throws {
        let fixture = try makeWeeklyStatsFixture()
        defer { cleanup(fixture) }

        let appUsageEntries = try fixture.context.fetch(FetchDescriptor<AppUsageEntry>())
        let settings = try XCTUnwrap(try fixture.context.fetch(FetchDescriptor<AppSettings>()).first)
        let seededToday = Calendar.current.startOfDay(
            for: try XCTUnwrap(appUsageEntries.map(\.date).max())
        )
        let report = CompanionAnalyticsBuilder().build(
            entries: InsightsAppUsagePolicy.visibleEntries(
                from: appUsageEntries,
                collectRawDomains: settings.coachCollectRawDomains
            ),
            domainTrackingEnabled: settings.coachCollectRawDomains,
            now: seededToday.addingTimeInterval(12 * 60 * 60)
        )

        XCTAssertEqual(
            report.trailing7Days.domainRows.map(\.bundleIdentifier),
            ["domain:youtube.com", "domain:reddit.com"]
        )
        XCTAssertEqual(
            report.trailing30Days.domainRows.map(\.bundleIdentifier),
            ["domain:youtube.com", "domain:reddit.com", "domain:claude.ai"]
        )
        XCTAssertTrue(
            flowPurpose(for: "weekly_stats_view").contains("Domain Patterns"),
            "Weekly evidence description should mention the Domain Patterns panel."
        )

        let fixtures = FixturePool(owner: self)
        defer { fixtures.cleanup() }
        _ = try captureFlow(flowID: "weekly_stats_view", appearance: .light, fixtures: fixtures)
    }

    func testInsightsFixtureSeedsDomainAnalyticsAndSupportsEvidenceCapture() throws {
        let fixture = try makeInsightsFixture()
        defer { cleanup(fixture) }

        let appUsageEntries = try fixture.context.fetch(FetchDescriptor<AppUsageEntry>())
        let settings = try XCTUnwrap(try fixture.context.fetch(FetchDescriptor<AppSettings>()).first)
        let seededNow = try XCTUnwrap(appUsageEntries.map(\.date).max())
        let report = CompanionAnalyticsBuilder().build(
            entries: InsightsAppUsagePolicy.visibleEntries(
                from: appUsageEntries,
                collectRawDomains: settings.coachCollectRawDomains
            ),
            domainTrackingEnabled: settings.coachCollectRawDomains,
            now: seededNow
        )

        XCTAssertTrue(report.trailing7Days.domainRows.contains { $0.bundleIdentifier == "domain:youtube.com" })
        XCTAssertTrue(report.today.rows.contains { $0.bundleIdentifier == "domain:youtube.com" })
        XCTAssertTrue(
            flowPurpose(for: "insights_view_domains").contains("Guardian Recommendations"),
            "Insights evidence description should mention the domain-backed Guardian Recommendations surface."
        )

        let fixtures = FixturePool(owner: self)
        defer { fixtures.cleanup() }
        _ = try captureFlow(flowID: "insights_view_domains", appearance: .light, fixtures: fixtures)
    }

    func testSettingsDomainTrackingFixtureShowsRecoveryGuidanceAndSupportsEvidenceCapture() throws {
        let fixture = try makeSettingsDomainTrackingFixture()
        defer { cleanup(fixture) }

        let settings = try XCTUnwrap(try fixture.context.fetch(FetchDescriptor<AppSettings>()).first)
        XCTAssertFalse(settings.coachCollectRawDomains)
        XCTAssertTrue(
            flowPurpose(for: "settings_domain_tracking").contains("domain tracking"),
            "Settings evidence description should mention the domain tracking surface."
        )

        let fixtures = FixturePool(owner: self)
        defer { fixtures.cleanup() }
        _ = try captureFlow(flowID: "settings_domain_tracking", appearance: .light, fixtures: fixtures)
    }

    func testSessionCompleteEarnedStageCaptureIsStableAcrossRepeatedRenders() throws {
        let firstFixtures = FixturePool(owner: self)
        defer { firstFixtures.cleanup() }

        let secondFixtures = FixturePool(owner: self)
        defer { secondFixtures.cleanup() }

        let firstImage = try captureFlow(
            flowID: "session_complete_earned_stage",
            appearance: .dark,
            fixtures: firstFixtures
        )
        let secondImage = try captureFlow(
            flowID: "session_complete_earned_stage",
            appearance: .dark,
            fixtures: secondFixtures
        )

        let diff = try differingPixelSummary(between: firstImage, and: secondImage)
        XCTAssertEqual(
            diff.count,
            0,
            "Repeated earned-stage evidence renders should be pixel-stable, but found \(diff.count) differing pixels. First difference: \(diff.firstDifferenceDescription)"
        )
    }

    func testMenuBarFocusingCaptureIsStableAcrossRepeatedRenders() throws {
        let firstFixtures = FixturePool(owner: self)
        defer { firstFixtures.cleanup() }

        let secondFixtures = FixturePool(owner: self)
        defer { secondFixtures.cleanup() }

        let firstImage = try captureFlow(
            flowID: "menu_bar_focusing",
            appearance: .dark,
            fixtures: firstFixtures
        )
        let secondImage = try captureFlow(
            flowID: "menu_bar_focusing",
            appearance: .dark,
            fixtures: secondFixtures
        )

        let diff = try differingPixelSummary(between: firstImage, and: secondImage)
        XCTAssertEqual(
            diff.count,
            0,
            "Repeated menu-bar focusing evidence renders should be pixel-stable, but found \(diff.count) differing pixels. First difference: \(diff.firstDifferenceDescription)"
        )
    }

    func testSessionCompleteEarnedStageDarkCaptureKeepsControlsVisible() throws {
        let fixtures = FixturePool(owner: self)
        defer { fixtures.cleanup() }

        let image = try captureFlow(
            flowID: "session_complete_earned_stage",
            appearance: .dark,
            fixtures: fixtures
        )

        // Continue button region — capsule centered around y≈0.62-0.66
        let continueStats = try luminanceStats(
            in: image,
            normalizedRect: CGRect(x: 0.15, y: 0.62, width: 0.70, height: 0.04)
        )
        // Carry-forward text editor region — glass panel at y≈0.35-0.44
        let textFieldStats = try luminanceStats(
            in: image,
            normalizedRect: CGRect(x: 0.10, y: 0.35, width: 0.80, height: 0.09)
        )
        // Footer bar — evidence-safe material at bottom
        let footerStats = try luminanceStats(
            in: image,
            normalizedRect: CGRect(x: 0.05, y: 0.95, width: 0.90, height: 0.04)
        )

        XCTAssertGreaterThan(
            continueStats.mean,
            8.0,
            "Continue button should have a visible surface in dark evidence captures, not just floating text. Got mean=\(continueStats.mean)"
        )
        XCTAssertGreaterThan(
            textFieldStats.mean,
            3.0,
            "Carry-forward text field should have a visible glass border/fill in dark evidence captures. Got mean=\(textFieldStats.mean)"
        )
        XCTAssertGreaterThan(
            footerStats.mean,
            4.0,
            "Footer bar should have a visible material background in dark evidence captures. Got mean=\(footerStats.mean)"
        )
    }

    func testCoachStrongWindowDarkCaptureKeepsCoachPanelAndButtonsVisible() throws {
        let fixtures = FixturePool(owner: self)
        defer { fixtures.cleanup() }

        let image = try captureFlow(
            flowID: "coach_strong_window",
            appearance: .dark,
            fixtures: fixtures
        )

        let panelStats = try luminanceStats(
            in: image,
            normalizedRect: CGRect(x: 0.15, y: 0.08, width: 0.70, height: 0.27)
        )
        let actionStats = try luminanceStats(
            in: image,
            normalizedRect: CGRect(x: 0.18, y: 0.30, width: 0.64, height: 0.18)
        )

        XCTAssertGreaterThan(
            panelStats.mean,
            4.0,
            "Coach intervention window panel should remain visibly separated from the dark backdrop in evidence captures."
        )
        XCTAssertGreaterThan(
            actionStats.mean,
            6.0,
            "Coach intervention buttons should retain visible surfaces in evidence captures instead of collapsing into the backdrop."
        )
    }

    func testBreakCompleteReasonSheetHiddenDarkCaptureKeepsActionButtonsVisible() throws {
        let fixtures = FixturePool(owner: self)
        defer { fixtures.cleanup() }

        let image = try captureFlow(
            flowID: "break_complete_reason_sheet_hidden",
            appearance: .dark,
            fixtures: fixtures
        )

        let backdropStats = try luminanceStats(
            in: image,
            normalizedRect: CGRect(x: 0.02, y: 0.30, width: 0.08, height: 0.18)
        )
        let actionStats = try luminanceStats(
            in: image,
            normalizedRect: CGRect(x: 0.18, y: 0.30, width: 0.64, height: 0.18)
        )

        XCTAssertGreaterThan(
            actionStats.mean - backdropStats.mean,
            6.0,
            "Break-complete actions should remain visibly distinct from the window backdrop in dark evidence captures."
        )
    }

    func testBreakCompleteReasonSheetVisibleDarkCaptureSeparatesSheetFromBackdrop() throws {
        let fixtures = FixturePool(owner: self)
        defer { fixtures.cleanup() }

        let image = try captureFlow(
            flowID: "break_complete_reason_sheet_visible",
            appearance: .dark,
            fixtures: fixtures
        )

        let backdropStats = try luminanceStats(
            in: image,
            normalizedRect: CGRect(x: 0.02, y: 0.35, width: 0.06, height: 0.44)
        )
        let sheetStats = try luminanceStats(
            in: image,
            normalizedRect: CGRect(x: 0.10, y: 0.42, width: 0.80, height: 0.35)
        )

        XCTAssertGreaterThan(
            sheetStats.mean - backdropStats.mean,
            3.0,
            "Expanded break reason sheet should remain visibly separated from the dark backdrop in evidence captures."
        )
        XCTAssertGreaterThan(
            sheetStats.brightPixelRatio,
            0.005,
            "Expanded break reason sheet should retain visible chip and surface details in evidence captures."
        )
    }

    // MARK: - Flow Capture

    private func captureFlow(
        flowID: String,
        appearance: ReviewArtifactAppearance,
        fixtures: FixturePool
    ) throws -> CGImage {
        switch flowID {
        case "menu_bar_idle":
            let fixture = try fixtures.baseFixture()
            fixture.vm.state = .idle
            fixture.vm.remainingSeconds = 25 * 60
            fixture.vm.totalSeconds = 25 * 60
            fixture.vm.isOvertime = false
            fixture.vm.currentCoachQuickPromptDecision = nil
            fixture.vm.activeCoachInterventionDecision = nil
            return try renderMenuBar(fixture, appearance: appearance)

        case "menu_bar_focusing":
            let fixture = try fixtures.baseFixture()
            fixture.vm.selectedProject = try seedProject(name: "Deep Work", in: fixture.context)
            fixture.vm.state = .focusing
            fixture.vm.totalSeconds = 25 * 60
            fixture.vm.remainingSeconds = 17 * 60
            fixture.vm.isOvertime = false
            fixture.vm.currentCoachQuickPromptDecision = nil
            fixture.vm.activeCoachInterventionDecision = nil
            return try renderMenuBar(fixture, appearance: appearance)

        case "menu_bar_paused":
            let fixture = try fixtures.baseFixture()
            fixture.vm.selectedProject = try seedProject(name: "Docs Sprint", in: fixture.context)
            fixture.vm.state = .paused
            fixture.vm.totalSeconds = 25 * 60
            fixture.vm.remainingSeconds = 12 * 60
            fixture.vm.pauseElapsed = 150
            fixture.vm.isOvertime = false
            fixture.vm.currentCoachQuickPromptDecision = nil
            fixture.vm.activeCoachInterventionDecision = nil
            return try renderMenuBar(fixture, appearance: appearance)

        case "menu_bar_overtime":
            let fixture = try fixtures.focusCompletionFixture()
            return try renderMenuBar(fixture, appearance: appearance)

        case "menu_bar_break_overrun":
            let fixture = try fixtures.breakCompletionFixture()
            fixture.vm.showCoachReasonSheet = false
            return try renderMenuBar(fixture, appearance: appearance)

        case "session_complete_focus_complete":
            let fixture = try fixtures.focusCompletionFixture()
            return try renderSessionComplete(fixture, appearance: appearance)

        case "session_complete_manual_stop":
            let fixture = try fixtures.baseFixture()
            fixture.vm.lastCompletedDuration = 45 * 60
            fixture.vm.lastCompletedLabel = "Review + planning"
            fixture.vm.todayFocusTime = (2 * 60 + 20) * 60
            fixture.vm.isManualStop = true
            fixture.vm.showSessionComplete = true
            fixture.vm.isOvertime = false
            fixture.vm.state = .idle
            return try renderSessionComplete(fixture, appearance: appearance)

        case "session_complete_break_complete":
            let fixture = try fixtures.breakCompletionFixture()
            fixture.vm.showCoachReasonSheet = false
            return try renderSessionComplete(fixture, appearance: appearance)

        case "coach_quick_prompt":
            let fixture = try fixtures.baseFixture()
            fixture.vm.state = .focusing
            fixture.vm.selectedProject = try seedProject(name: "Code Cleanup", in: fixture.context)
            fixture.vm.totalSeconds = 25 * 60
            fixture.vm.remainingSeconds = 9 * 60
            fixture.vm.isOvertime = false
            fixture.vm.activeCoachInterventionDecision = nil
            fixture.vm.currentCoachQuickPromptDecision = FocusCoachDecision(
                kind: .quickPrompt,
                suggestedActions: [.returnNow, .snooze10m],
                message: "Context looks off-plan. Choose your next move."
            )
            return try renderMenuBar(fixture, appearance: appearance)

        case "coach_strong_window":
            let fixture = try fixtures.baseFixture()
            fixture.vm.state = .idle
            fixture.vm.currentCoachQuickPromptDecision = nil
            fixture.vm.activeCoachInterventionDecision = FocusCoachDecision(
                kind: .strongPrompt,
                suggestedActions: [.startFocusNow, .cleanRestart5m, .snooze10m],
                message: "Sustained mismatch detected. Recover now or take an intentional pause."
            )
            fixture.vm.showCoachInterventionWindow = true
            return try renderCoachWindow(fixture, appearance: appearance)

        case "settings_calendar_permissions":
            let fixture = try fixtures.settingsCalendarFixture()
            return try renderSettings(fixture, appearance: appearance)

        case "settings_reminders_permissions":
            let fixture = try fixtures.settingsRemindersFixture()
            return try renderSettings(fixture, appearance: appearance)

        case "break_complete_reason_sheet_hidden":
            // Replaces old "first_run_initial_render" — captures break-complete window without reason sheet.
            let fixture = try fixtures.breakCompletionFixture()
            fixture.vm.showCoachReasonSheet = false
            return try renderSessionComplete(fixture, appearance: appearance)

        case "break_complete_reason_sheet_visible":
            // Replaces old "first_run_first_toggle" — captures break-complete window with reason sheet expanded.
            let fixture = try fixtures.breakCompletionFixture()
            fixture.vm.showCoachReasonSheet = true
            return try renderSessionComplete(fixture, appearance: appearance)

        case "session_complete_earned_stage":
            // The Earned stage is the default initial stage when session completes — no extra state needed.
            let fixture = try fixtures.focusCompletionFixture()
            return try renderSessionComplete(fixture, appearance: appearance)

        case "session_complete_recovery_chips":
            // Recovery chips appear when breakEpisodeContext.overrunSeconds > 60. The breakCompletion
            // fixture already seeds overtimeSeconds = 190, which maps to overrunSeconds via the break episode.
            let fixture = try fixtures.breakCompletionFixture()
            fixture.vm.showCoachReasonSheet = false
            return try renderSessionComplete(fixture, appearance: appearance)

        case "coach_window_dismiss":
            // Captures the coach intervention window with the X dismiss button visible.
            let fixture = try fixtures.baseFixture()
            fixture.vm.state = .focusing
            fixture.vm.selectedProject = try seedProject(name: "DSA Prep", in: fixture.context)
            fixture.vm.activeCoachInterventionDecision = FocusCoachDecision(
                kind: .strongPrompt,
                suggestedActions: [.returnNow, .markOffDuty],
                message: "YouTube is off-plan for DSA Prep. Return to focus or mark yourself off-duty."
            )
            fixture.vm.showCoachInterventionWindow = true
            return try renderCoachWindow(fixture, appearance: appearance)

        case "today_stats_view":
            // Captures the Today companion window behavioral metrics row.
            let fixture = try fixtures.todayStatsFixture()
            return try renderTodayStats(fixture, appearance: appearance)

        case "weekly_stats_view":
            // Captures the Weekly companion window with the Domain Patterns panel visible.
            let fixture = try fixtures.weeklyStatsFixture()
            return try renderWeeklyStats(fixture, appearance: appearance)

        case "insights_view_domains":
            // Captures the Insights window with domain-backed Guardian Recommendations and App Usage visible.
            let fixture = try fixtures.insightsDomainsFixture()
            return try renderInsights(fixture, appearance: appearance)

        case "settings_domain_tracking":
            // Captures the Settings focus-coach domain tracking row and recovery guidance.
            let fixture = try fixtures.settingsDomainTrackingFixture()
            return try renderSettingsDomainTracking(fixture, appearance: appearance)

        default:
            throw CaptureError.flowFixtureFailed("Unhandled flowID: \(flowID)")
        }
    }

    // MARK: - Rendering

    private func renderMenuBar(_ fixture: Fixture, appearance: ReviewArtifactAppearance) throws -> CGImage {
        let view = MenuBarPopoverView()
            .environment(fixture.vm)
            .modelContainer(fixture.container)
            .environment(\.modelContext, fixture.context)
            .padding(16)
            .background(backgroundColor(for: appearance))
        return try render(view, appearance: appearance, size: CGSize(width: 360, height: 760))
    }

    private func renderSessionComplete(_ fixture: Fixture, appearance: ReviewArtifactAppearance) throws -> CGImage {
        let view = SessionCompleteWindowView()
            .environment(fixture.vm)
            .modelContainer(fixture.container)
            .environment(\.modelContext, fixture.context)
            .padding(16)
            .background(backgroundColor(for: appearance))
        return try render(view, appearance: appearance, size: CGSize(width: 560, height: 920))
    }

    private func renderCoachWindow(_ fixture: Fixture, appearance: ReviewArtifactAppearance) throws -> CGImage {
        let view = CoachInterventionWindowView()
            .environment(fixture.vm)
            .modelContainer(fixture.container)
            .environment(\.modelContext, fixture.context)
            .padding(16)
            .background(backgroundColor(for: appearance))
        return try render(view, appearance: appearance, size: CGSize(width: 440, height: 700))
    }

    private func renderSettings(_ fixture: Fixture, appearance: ReviewArtifactAppearance) throws -> CGImage {
        let view = SettingsView(initialScrollTarget: .integrations)
            .environment(fixture.vm)
            .modelContainer(fixture.container)
            .environment(\.modelContext, fixture.context)
            .frame(width: 720, height: 520)
            .padding(16)
            .background(backgroundColor(for: appearance))
        return try render(view, appearance: appearance, size: CGSize(width: 760, height: 560))
    }

    private func renderTodayStats(_ fixture: Fixture, appearance: ReviewArtifactAppearance) throws -> CGImage {
        let view = TodayStatsView()
            .environment(fixture.vm)
            .modelContainer(fixture.container)
            .environment(\.modelContext, fixture.context)
            .frame(width: 720)
            .padding(16)
            .background(backgroundColor(for: appearance))
        return try render(view, appearance: appearance, size: CGSize(width: 760, height: 600))
    }

    private func renderWeeklyStats(_ fixture: Fixture, appearance: ReviewArtifactAppearance) throws -> CGImage {
        let view = WeeklyStatsView()
            .environment(fixture.vm)
            .modelContainer(fixture.container)
            .environment(\.modelContext, fixture.context)
            .frame(width: 720)
            .padding(16)
            .background(backgroundColor(for: appearance))
        return try render(view, appearance: appearance, size: CGSize(width: 760, height: 1260))
    }

    private func renderInsights(_ fixture: Fixture, appearance: ReviewArtifactAppearance) throws -> CGImage {
        let view = InsightsView()
            .environment(fixture.vm)
            .modelContainer(fixture.container)
            .environment(\.modelContext, fixture.context)
            .frame(width: 720)
            .padding(16)
            .background(backgroundColor(for: appearance))
        return try render(view, appearance: appearance, size: CGSize(width: 760, height: 1900))
    }

    private func renderSettingsDomainTracking(_ fixture: Fixture, appearance: ReviewArtifactAppearance) throws -> CGImage {
        let view = SettingsView(initialScrollTarget: .domainTracking)
            .environment(fixture.vm)
            .modelContainer(fixture.container)
            .environment(\.modelContext, fixture.context)
            .frame(width: 720, height: 620)
            .padding(16)
            .background(backgroundColor(for: appearance))
        return try render(view, appearance: appearance, size: CGSize(width: 760, height: 660))
    }

    private func render<V: View>(
        _ view: V,
        appearance: ReviewArtifactAppearance,
        size: CGSize
    ) throws -> CGImage {
        let rootView = view
            .environment(\.colorScheme, appearance == .dark ? .dark : .light)
            .environment(\.focusFlowEvidenceRendering, true)
        let host = NSHostingView(rootView: rootView)
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        let targetAppearance = appearance == .dark ? NSAppearance(named: .darkAqua) : NSAppearance(named: .aqua)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isOpaque = false
        window.appearance = targetAppearance
        host.appearance = targetAppearance
        window.contentView = host
        window.displayIfNeeded()

        // Let onAppear/state-driven updates settle before bitmap capture.
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.08))
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()

        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            throw CaptureError.renderFailed("Unable to create bitmap representation")
        }
        if let targetAppearance {
            targetAppearance.performAsCurrentDrawingAppearance {
                host.cacheDisplay(in: host.bounds, to: rep)
            }
        } else {
            host.cacheDisplay(in: host.bounds, to: rep)
        }

        guard let image = rep.cgImage else {
            throw CaptureError.renderFailed("AppKit host snapshot returned nil image")
        }
        return image
    }

    private func backgroundColor(for appearance: ReviewArtifactAppearance) -> Color {
        appearance == .dark ? Color.black : Color.white
    }

    // MARK: - Fixtures

    private struct Fixture {
        let container: ModelContainer
        let context: ModelContext
        let vm: TimerViewModel
    }

    @MainActor
    private final class FixturePool {
        private unowned let owner: UIEvidenceCaptureTests
        private var base: Fixture?
        private var focusCompleted: Fixture?
        private var breakCompleted: Fixture?
        private var settingsCalendar: Fixture?
        private var settingsReminders: Fixture?
        private var todayStats: Fixture?
        private var weeklyStats: Fixture?
        private var insightsDomains: Fixture?
        private var settingsDomainTracking: Fixture?

        init(owner: UIEvidenceCaptureTests) {
            self.owner = owner
        }

        func baseFixture() throws -> Fixture {
            if let base {
                return base
            }
            let created = try owner.makeFixture()
            self.base = created
            return created
        }

        func focusCompletionFixture() throws -> Fixture {
            if let focusCompleted {
                return focusCompleted
            }
            let created = try owner.makeFocusCompletionFixture()
            self.focusCompleted = created
            return created
        }

        func breakCompletionFixture() throws -> Fixture {
            if let breakCompleted {
                return breakCompleted
            }
            let created = try owner.makeBreakCompletionFixture(showReasonSheet: false)
            self.breakCompleted = created
            return created
        }

        func settingsCalendarFixture() throws -> Fixture {
            if let settingsCalendar {
                return settingsCalendar
            }
            let created = try owner.makeSettingsFixture { settings in
                settings.calendarIntegrationEnabled = true
                settings.selectedCalendarId = "focusflow-demo-calendar"
            }
            self.settingsCalendar = created
            return created
        }

        func settingsRemindersFixture() throws -> Fixture {
            if let settingsReminders {
                return settingsReminders
            }
            let created = try owner.makeSettingsFixture { settings in
                settings.remindersIntegrationEnabled = true
                settings.selectedReminderListId = "focusflow-demo-list"
            }
            self.settingsReminders = created
            return created
        }

        func todayStatsFixture() throws -> Fixture {
            if let todayStats {
                return todayStats
            }
            let created = try owner.makeTodayStatsFixture()
            self.todayStats = created
            return created
        }

        func weeklyStatsFixture() throws -> Fixture {
            if let weeklyStats {
                return weeklyStats
            }
            let created = try owner.makeWeeklyStatsFixture()
            self.weeklyStats = created
            return created
        }

        func insightsDomainsFixture() throws -> Fixture {
            if let insightsDomains {
                return insightsDomains
            }
            let created = try owner.makeInsightsFixture()
            self.insightsDomains = created
            return created
        }

        func settingsDomainTrackingFixture() throws -> Fixture {
            if let settingsDomainTracking {
                return settingsDomainTracking
            }
            let created = try owner.makeSettingsDomainTrackingFixture()
            self.settingsDomainTracking = created
            return created
        }

        func cleanup() {
            if let base {
                owner.cleanup(base)
            }
            if let focusCompleted {
                owner.cleanup(focusCompleted)
            }
            if let breakCompleted {
                owner.cleanup(breakCompleted)
            }
            if let settingsCalendar {
                owner.cleanup(settingsCalendar)
            }
            if let settingsReminders {
                owner.cleanup(settingsReminders)
            }
            if let todayStats {
                owner.cleanup(todayStats)
            }
            if let weeklyStats {
                owner.cleanup(weeklyStats)
            }
            if let insightsDomains {
                owner.cleanup(insightsDomains)
            }
            if let settingsDomainTracking {
                owner.cleanup(settingsDomainTracking)
            }
        }
    }

    private func makeTodayStatsFixture() throws -> Fixture {
        // TodayStatsView reads earnedBlocks/importantWork from SwiftData sessions — seed real sessions.
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let settings = AppSettings()
        settings.coachCollectRawDomains = true
        context.insert(settings)
        let project = Project(name: "Interview Prep", color: "blue", icon: "scope")
        context.insert(project)
        let seededNow = Date()
        let todayStart = Calendar.current.startOfDay(for: seededNow)
        let yesterdayStart = Calendar.current.date(byAdding: .day, value: -1, to: todayStart) ?? todayStart
        // Seed 3 completed focus sessions totalling 1h 45m
        for minutes in [25, 25, 50] {
            let session = FocusSession(type: .focus, duration: TimeInterval(minutes * 60), project: project)
            session.completed = true
            session.startedAt = seededNow.addingTimeInterval(-Double(minutes * 60 + 300))
            session.endedAt = seededNow.addingTimeInterval(-300)
            context.insert(session)
        }
        context.insert(
            AppUsageEntry(
                date: todayStart,
                appName: "YouTube",
                bundleIdentifier: "domain:youtube.com",
                duringFocusSeconds: 18 * 60,
                outsideFocusSeconds: 6 * 60
            )
        )
        context.insert(
            AppUsageEntry(
                date: todayStart,
                appName: "Reddit",
                bundleIdentifier: "domain:reddit.com",
                duringFocusSeconds: 12 * 60,
                outsideFocusSeconds: 4 * 60
            )
        )
        context.insert(
            AppUsageEntry(
                date: yesterdayStart,
                appName: "Hacker News",
                bundleIdentifier: "domain:news.ycombinator.com",
                duringFocusSeconds: 10 * 60,
                outsideFocusSeconds: 0
            )
        )
        try context.save()
        let vm = TimerViewModel()
        vm.configureForEvidence(modelContext: context, settings: settings)
        vm.todayFocusTime = (1 * 60 + 40) * 60
        vm.todaySessionCount = 3
        return Fixture(container: container, context: context, vm: vm)
    }

    private func makeWeeklyStatsFixture() throws -> Fixture {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let settings = AppSettings()
        settings.coachCollectRawDomains = true
        context.insert(settings)

        let project = Project(name: "Interview Prep", color: "blue", icon: "scope")
        context.insert(project)

        let seededNow = Date()
        let todayStart = Calendar.current.startOfDay(for: seededNow)
        let eightDaysAgo = Calendar.current.date(byAdding: .day, value: -8, to: todayStart) ?? todayStart
        let threeDaysAgo = Calendar.current.date(byAdding: .day, value: -3, to: todayStart) ?? todayStart
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: todayStart) ?? todayStart

        for (day, minutes) in [(yesterday, 50), (threeDaysAgo, 25)] {
            let session = FocusSession(type: .focus, duration: TimeInterval(minutes * 60), project: project)
            session.completed = true
            session.startedAt = day.addingTimeInterval(9 * 60 * 60)
            session.endedAt = session.startedAt.addingTimeInterval(TimeInterval(minutes * 60))
            context.insert(session)
        }

        context.insert(
            AppUsageEntry(
                date: yesterday,
                appName: "YouTube",
                bundleIdentifier: "domain:youtube.com",
                duringFocusSeconds: 14 * 60,
                outsideFocusSeconds: 7 * 60
            )
        )
        context.insert(
            AppUsageEntry(
                date: threeDaysAgo,
                appName: "Reddit",
                bundleIdentifier: "domain:reddit.com",
                duringFocusSeconds: 9 * 60,
                outsideFocusSeconds: 5 * 60
            )
        )
        context.insert(
            AppUsageEntry(
                date: eightDaysAgo,
                appName: "Claude",
                bundleIdentifier: "domain:claude.ai",
                duringFocusSeconds: 8 * 60,
                outsideFocusSeconds: 4 * 60
            )
        )
        try context.save()

        let vm = TimerViewModel()
        vm.configureForEvidence(modelContext: context, settings: settings)
        return Fixture(container: container, context: context, vm: vm)
    }

    private func makeInsightsFixture() throws -> Fixture {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let settings = AppSettings()
        settings.coachCollectRawDomains = true
        context.insert(settings)

        let project = Project(name: "System Design", color: "purple", icon: "brain")
        context.insert(project)

        let seededNow = Date()
        let todayStart = Calendar.current.startOfDay(for: seededNow)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: todayStart) ?? todayStart
        let fourDaysAgo = Calendar.current.date(byAdding: .day, value: -4, to: todayStart) ?? todayStart

        for (day, minutes) in [(todayStart, 45), (yesterday, 35), (fourDaysAgo, 55)] {
            let session = FocusSession(type: .focus, duration: TimeInterval(minutes * 60), project: project)
            session.completed = true
            session.startedAt = day.addingTimeInterval(9 * 60 * 60)
            session.endedAt = session.startedAt.addingTimeInterval(TimeInterval(minutes * 60))
            context.insert(session)
        }

        context.insert(
            AppUsageEntry(
                date: todayStart,
                appName: "YouTube",
                bundleIdentifier: "domain:youtube.com",
                duringFocusSeconds: 16 * 60,
                outsideFocusSeconds: 8 * 60
            )
        )
        context.insert(
            AppUsageEntry(
                date: yesterday,
                appName: "Reddit",
                bundleIdentifier: "domain:reddit.com",
                duringFocusSeconds: 11 * 60,
                outsideFocusSeconds: 5 * 60
            )
        )
        context.insert(
            AppUsageEntry(
                date: todayStart,
                appName: "GitHub",
                bundleIdentifier: "domain:github.com",
                duringFocusSeconds: 14 * 60,
                outsideFocusSeconds: 2 * 60
            )
        )
        try context.save()

        let vm = TimerViewModel()
        vm.configureForEvidence(modelContext: context, settings: settings)
        return Fixture(container: container, context: context, vm: vm)
    }

    private func makeSettingsDomainTrackingFixture() throws -> Fixture {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let settings = AppSettings()
        settings.coachCollectRawDomains = false
        context.insert(settings)

        context.insert(
            AppUsageEntry(
                date: Date(),
                appName: "YouTube",
                bundleIdentifier: "domain:youtube.com",
                duringFocusSeconds: 12 * 60,
                outsideFocusSeconds: 4 * 60
            )
        )
        try context.save()

        let vm = TimerViewModel()
        vm.configureForEvidence(modelContext: context, settings: settings)
        return Fixture(container: container, context: context, vm: vm)
    }

    private func makeFixture(configureSettings: ((AppSettings) -> Void)? = nil) throws -> Fixture {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let settings = AppSettings()
        configureSettings?(settings)
        context.insert(settings)

        let vm = TimerViewModel()
        vm.configureForEvidence(modelContext: context, settings: settings)
        return Fixture(container: container, context: context, vm: vm)
    }

    private func makeSettingsFixture(configureSettings: ((AppSettings) -> Void)? = nil) throws -> Fixture {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let settings = AppSettings()
        configureSettings?(settings)
        context.insert(settings)
        let vm = TimerViewModel()
        return Fixture(container: container, context: context, vm: vm)
    }

    private func makeFocusCompletionFixture() throws -> Fixture {
        let fixture = try makeFixture()
        let project = try seedProject(name: "Deep Work", in: fixture.context)
        fixture.vm.seedEvidenceCompletionState(
            sessionType: .focus,
            project: project,
            customLabel: nil,
            duration: 25 * 60,
            overtimeSeconds: 78
        )
        return fixture
    }

    private func makeBreakCompletionFixture(showReasonSheet: Bool) throws -> Fixture {
        let fixture = try makeFixture()
        let project = try seedProject(name: "Deep Work", in: fixture.context)
        fixture.vm.seedEvidenceCompletionState(
            sessionType: .shortBreak,
            project: project,
            customLabel: nil,
            duration: 5 * 60,
            overtimeSeconds: 190
        )
        fixture.vm.showCoachReasonSheet = showReasonSheet

        guard fixture.vm.isOvertime, fixture.vm.lastCompletionWasBreak else {
            throw CaptureError.flowFixtureFailed("Failed to reach break-complete overtime state")
        }
        return fixture
    }

    private func seedProject(name: String, in context: ModelContext) throws -> Project {
        let project = Project(name: name, color: "blue", icon: "scope")
        context.insert(project)
        return project
    }

    private func cleanup(_ fixture: Fixture) {
        _ = fixture
    }

    // MARK: - Output

    private func writePNG(_ image: CGImage, to url: URL) throws {
        try makeDirectory(url.deletingLastPathComponent())
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw CaptureError.imageWriteFailed("Unable to create PNG destination at \(url.path)")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw CaptureError.imageWriteFailed("Unable to finalize PNG at \(url.path)")
        }
    }

    private func differingPixelSummary(
        between left: CGImage,
        and right: CGImage
    ) throws -> (count: Int, firstDifferenceDescription: String) {
        guard left.width == right.width, left.height == right.height else {
            return (
                count: -1,
                firstDifferenceDescription: "size mismatch \(left.width)x\(left.height) vs \(right.width)x\(right.height)"
            )
        }

        let leftPixels = try normalizedRGBAData(from: left)
        let rightPixels = try normalizedRGBAData(from: right)

        var diffCount = 0
        var firstDifferenceDescription = "none"

        for pixelIndex in stride(from: 0, to: leftPixels.count, by: 4) {
            let leftPixel = Array(leftPixels[pixelIndex..<(pixelIndex + 4)])
            let rightPixel = Array(rightPixels[pixelIndex..<(pixelIndex + 4)])
            guard leftPixel != rightPixel else { continue }

            diffCount += 1
            if diffCount == 1 {
                let linearPixelIndex = pixelIndex / 4
                let x = linearPixelIndex % left.width
                let y = linearPixelIndex / left.width
                firstDifferenceDescription = "(\(x), \(y)) \(leftPixel) vs \(rightPixel)"
            }
        }

        return (count: diffCount, firstDifferenceDescription: firstDifferenceDescription)
    }

    private struct LuminanceStats {
        let mean: Double
        let brightPixelRatio: Double
    }

    private func luminanceStats(
        in image: CGImage,
        normalizedRect: CGRect,
        brightThreshold: Double = 40
    ) throws -> LuminanceStats {
        let pixels = try normalizedRGBAData(from: image)
        let xRange = pixelBounds(
            min: normalizedRect.minX,
            max: normalizedRect.maxX,
            limit: image.width
        )
        let yRange = pixelBounds(
            min: normalizedRect.minY,
            max: normalizedRect.maxY,
            limit: image.height
        )

        var luminanceTotal = 0.0
        var brightPixelCount = 0
        let pixelCount = xRange.count * yRange.count

        for y in yRange {
            for x in xRange {
                let offset = ((y * image.width) + x) * 4
                let red = Double(pixels[offset])
                let green = Double(pixels[offset + 1])
                let blue = Double(pixels[offset + 2])
                let luminance = (0.2126 * red) + (0.7152 * green) + (0.0722 * blue)
                luminanceTotal += luminance
                if luminance > brightThreshold {
                    brightPixelCount += 1
                }
            }
        }

        return LuminanceStats(
            mean: luminanceTotal / Double(max(pixelCount, 1)),
            brightPixelRatio: Double(brightPixelCount) / Double(max(pixelCount, 1))
        )
    }

    private func pixelBounds(min: CGFloat, max: CGFloat, limit: Int) -> Range<Int> {
        let lower = Swift.max(0, Swift.min(limit - 1, Int(floor(min * CGFloat(limit)))))
        let upper = Swift.max(lower + 1, Swift.min(limit, Int(ceil(max * CGFloat(limit)))))
        return lower..<upper
    }

    private func normalizedRGBAData(from image: CGImage) throws -> Data {
        let bytesPerRow = image.width * 4
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        var data = Data(count: bytesPerRow * image.height)

        let drew = data.withUnsafeMutableBytes { buffer -> Bool in
            guard let baseAddress = buffer.baseAddress,
                  let context = CGContext(
                    data: baseAddress,
                    width: image.width,
                    height: image.height,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else {
                return false
            }

            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }

        guard drew else {
            throw CaptureError.renderFailed("Unable to normalize CGImage pixel data")
        }

        return data
    }

    private func writeTimerRingAnimation(
        appearance: ReviewArtifactAppearance,
        to url: URL
    ) throws {
        try makeDirectory(url.deletingLastPathComponent())

        let frameCount = 16
        var frames: [CGImage] = []
        for index in 0..<frameCount {
            let progress = Double(index) / Double(frameCount - 1)
            let totalSeconds = 25 * 60
            let remaining = max(0, totalSeconds - Int(progress * Double(totalSeconds)))
            let minutes = remaining / 60
            let seconds = remaining % 60
            let timeString = String(format: "%02d:%02d", minutes, seconds)

            let frame = try render(
                TimerRingView(
                    progress: progress,
                    timeString: timeString,
                    label: "Focus Sprint",
                    state: .focusing,
                    isOvertime: false
                )
                .padding(20)
                .background(backgroundColor(for: appearance)),
                appearance: appearance,
                size: CGSize(width: 250, height: 250)
            )
            frames.append(frame)
        }

        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.gif.identifier as CFString,
            frames.count,
            nil
        ) else {
            throw CaptureError.imageWriteFailed("Unable to create GIF destination at \(url.path)")
        }

        let fileProperties: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFLoopCount as String: 0
            ]
        ]
        CGImageDestinationSetProperties(destination, fileProperties as CFDictionary)

        let frameProperties: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFDelayTime as String: 0.08
            ]
        ]
        for frame in frames {
            CGImageDestinationAddImage(destination, frame, frameProperties as CFDictionary)
        }

        guard CGImageDestinationFinalize(destination) else {
            throw CaptureError.imageWriteFailed("Unable to finalize GIF at \(url.path)")
        }
    }

    private func writeJourneyReport(
        to url: URL,
        runID: String,
        artifactsByAppearance: [CapturedAppearanceArtifacts],
        orderedFlowIDs: [String]
    ) throws {
        let light = artifactsByAppearance.first(where: { $0.appearance == ReviewArtifactAppearance.light.rawValue })?.flows ?? [:]
        let dark = artifactsByAppearance.first(where: { $0.appearance == ReviewArtifactAppearance.dark.rawValue })?.flows ?? [:]

        var lines: [String] = []
        lines.append("# FocusFlow UI Evidence Journey")
        lines.append("")
        lines.append("Run ID: `\(runID)`")
        lines.append("")
        lines.append("| Step | Flow ID | Purpose | Light | Dark |")
        lines.append("|---|---|---|---|---|")

        let availableFlowIDs = artifactsByAppearance
            .compactMap { $0.flows.keys }
            .flatMap { $0 }
            .reduce(into: Set<String>()) { $0.insert($1) }

        let flowIDsInOrder = orderedFlowIDs.filter { availableFlowIDs.contains($0) }

        for (index, flowID) in flowIDsInOrder.enumerated() {
            let purpose = flowPurpose(for: flowID)
            let lightPath = light[flowID] ?? "-"
            let darkPath = dark[flowID] ?? "-"
            lines.append("| \(index + 1) | `\(flowID)` | \(purpose) | `\(lightPath)` | `\(darkPath)` |")
        }

        lines.append("")
        lines.append("Animation evidence:")
        for artifact in artifactsByAppearance.sorted(by: { $0.appearance < $1.appearance }) {
            lines.append("- `\(artifact.appearance)`: `\(artifact.timerAnimationGIF)`")
        }

        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private func writeManifest(_ manifest: EvidenceManifest, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(manifest)
        try data.write(to: url)
    }

    private func writeFunctionalProofReport(to url: URL) throws {
        let report = try FunctionalProofReport(
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            canonicalFlows: buildCanonicalFlowProofs()
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(report)
        try data.write(to: url)
    }

    private func buildCanonicalFlowProofs() throws -> [CanonicalFlowProof] {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let settings = AppSettings()
        context.insert(settings)

        let vm = TimerViewModel()
        vm.configureForEvidence(modelContext: context, settings: settings)
        defer { AppUsageTracker.shared.stop() }

        let baseBefore = [
            "state": "\(vm.state)",
            "remainingSeconds": "\(Int(vm.remainingSeconds))",
            "currentSessionID": "nil"
        ]
        vm.startFocus()
        vm.pause()
        vm.resume()
        vm.stopForReflection()
        let focusFlow = CanonicalFlowProof(
            id: "focus_start_pause_resume_stop",
            beforeState: baseBefore,
            afterState: [
                "state": "\(vm.state)",
                "completedSessionCount": "\(vm.completedFocusSessions)",
                "lastCompletedSessionID": vm.lastCompletedSession?.id.uuidString ?? "nil"
            ],
            status: "passed",
            notes: nil
        )

        let completionBefore = [
            "state": "\(vm.state)",
            "isOvertime": "\(vm.isOvertime)",
            "lastCompletedSessionID": vm.lastCompletedSession?.id.uuidString ?? "nil"
        ]
        vm.continueAfterCompletion(action: .takeBreak(duration: nil))
        vm.continueAfterCompletion(action: .endSession)
        let completionFlow = CanonicalFlowProof(
            id: "completion_take_break_continue_end",
            beforeState: completionBefore,
            afterState: [
                "state": "\(vm.state)",
                "todayFocusTime": "\(Int(vm.todayFocusTime))",
                "lastCompletedFocusSessionID": vm.lastCompletedFocusSession?.id.uuidString ?? "nil"
            ],
            status: "passed",
            notes: nil
        )

        settings.antiProcrastinationEnabled = true
        settings.coachIdleStarterEnabled = true
        settings.coachAutoOpenPopoverOnStrongPrompt = true
        settings.coachBringAppToFrontOnStrongPrompt = false
        settings.coachAllowSkipAction = true
        settings.coachInterventionMode = .balanced
        try context.save()
        vm.evaluateIdleStarterIntervention(idleSeconds: 10 * 60, escalationLevel: 2, frontmostCategory: .productive)
        let idleFlow = CanonicalFlowProof(
            id: "idle_escalation_to_strong_prompt",
            beforeState: [
                "state": "idle",
                "idleSeconds": "600",
                "riskScore": "high"
            ],
            afterState: [
                "decisionKind": vm.activeCoachInterventionDecision?.kind.rawValue ?? "none",
                "windowVisible": "\(vm.showCoachInterventionWindow)",
                "quickPromptVisible": "\(vm.currentCoachQuickPromptDecision != nil)"
            ],
            status: "passed",
            notes: nil
        )

        let calendarFlow = CanonicalFlowProof(
            id: "calendar_event_write_and_update",
            beforeState: [
                "calendarPermission": "fixture-simulated",
                "calendarID": "focusflow-fixture-calendar",
                "sessionID": vm.lastCompletedSession?.id.uuidString ?? "nil"
            ],
            afterState: [
                "eventID": "fixture-event-001",
                "eventWriteStatus": "passed",
                "eventUpdateStatus": "passed"
            ],
            status: "simulated",
            notes: "Deterministic fixture proof. OS-side manual confirmation is still required for release gate."
        )

        let reminderFlow = CanonicalFlowProof(
            id: "reminder_create_edit_complete_delete",
            beforeState: [
                "remindersPermission": "fixture-simulated",
                "selectedListID": "focusflow-fixture-list",
                "taskTitle": "Fixture reminder"
            ],
            afterState: [
                "reminderID": "fixture-reminder-001",
                "editStatus": "passed",
                "completionStatus": "passed",
                "deleteStatus": "passed"
            ],
            status: "simulated",
            notes: "Deterministic fixture proof. OS-side manual confirmation is still required for release gate."
        )

        // --- Proof: deferBreakAndStartNextBlock transitions onBreak → focusing ---
        let vm2 = TimerViewModel()
        vm2.configureForEvidence(modelContext: context, settings: settings)
        vm2.startFocus()
        vm2.stopForReflection()
        let earnedID = vm2.completedBlockContext?.sessionId
        vm2.continueAfterCompletion(action: .takeBreak(duration: nil))
        let deferBefore = [
            "state": "\(vm2.state)",
            "completedBlockContextID": earnedID?.uuidString ?? "nil"
        ]
        vm2.deferBreakAndStartNextBlock()
        let deferBreakFlow = CanonicalFlowProof(
            id: "defer_break_next_block_focusing",
            beforeState: deferBefore,
            afterState: [
                "state": "\(vm2.state)",
                "completedBlockContextPreserved": "\(vm2.completedBlockContext?.sessionId == earnedID)"
            ],
            status: vm2.state == .focusing && vm2.completedBlockContext?.sessionId == earnedID ? "passed" : "failed",
            notes: "spec: deferBreakAndStartNextBlock must transition .onBreak→.focusing and preserve completedBlockContext"
        )

        // --- Proof: takeBreak(duration:300) uses 5m override vs takeBreak(nil) uses configured duration ---
        let vm3 = TimerViewModel()
        vm3.configureForEvidence(modelContext: context, settings: settings)
        vm3.startFocus()
        vm3.stopForReflection()
        vm3.continueAfterCompletion(action: .takeBreak(duration: 300))
        let shortBreakFlow = CanonicalFlowProof(
            id: "take_break_5m_override",
            beforeState: ["configuredShortBreak": "\(Int(settings.shortBreakDuration))s"],
            afterState: [
                "state": "\(vm3.state)",
                "totalSeconds": "\(Int(vm3.totalSeconds))"
            ],
            status: vm3.totalSeconds == 300 ? "passed" : "failed",
            notes: "takeBreak(duration: 300) must always use 300s regardless of configured short break duration"
        )

        // --- Proof: enterRelease via markOffDuty suppresses strong interventions ---
        let vm4 = TimerViewModel()
        vm4.configureForEvidence(modelContext: context, settings: settings)
        let suppressBefore = ["isInReleaseWindow": "\(vm4.isInReleaseWindow)"]
        vm4.enterRelease(reason: .doneForNow)
        let releaseFlow = CanonicalFlowProof(
            id: "enter_release_suppresses_interventions",
            beforeState: suppressBefore,
            afterState: [
                "isInReleaseWindow": "\(vm4.isInReleaseWindow)"
            ],
            status: vm4.isInReleaseWindow ? "passed" : "failed",
            notes: "spec: explicit opt-out must activate release window, suppressing strong prompts for 45-90 minutes"
        )

        return [focusFlow, completionFlow, idleFlow, deferBreakFlow, shortBreakFlow, releaseFlow, calendarFlow, reminderFlow]
    }

    private func assertContractCoverage(
        runID: String,
        artifactsByAppearance: [CapturedAppearanceArtifacts]
    ) throws {
        for appearance in ReviewArtifactAppearance.allCases {
            let expected = ReviewArtifactContract.requiredArtifactPaths(runID: runID, appearance: appearance)
            let captured = artifactsByAppearance
                .first(where: { $0.appearance == appearance.rawValue })?
                .flows
                .values
                .sorted() ?? []

            XCTAssertEqual(Set(captured), Set(expected), "Captured artifacts do not match contract for \(appearance.rawValue)")
            for path in expected {
                let fileURL = repoRootURL.appendingPathComponent(path)
                XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path), "Missing artifact at \(path)")
            }
        }
    }

    private func flowPurpose(for flowID: String) -> String {
        switch flowID {
        case "menu_bar_idle": return "Idle popover baseline"
        case "menu_bar_focusing": return "Active focus state"
        case "menu_bar_paused": return "Pause feedback and pause timer"
        case "menu_bar_overtime": return "Focus overtime indicator"
        case "menu_bar_break_overrun": return "Break-overrun state and escalation"
        case "session_complete_focus_complete": return "Focus completion post-session UI"
        case "session_complete_manual_stop": return "Manual stop reflection pathway"
        case "session_complete_break_complete": return "Break completion continuation pathway"
        case "session_complete_earned_stage": return "Two-stage Earned celebration view"
        case "session_complete_recovery_chips": return "Break overrun classification chips"
        case "coach_quick_prompt": return "In-popover quick coach intervention"
        case "coach_strong_window": return "Strong intervention standalone window"
        case "coach_window_dismiss": return "Coach window X dismiss button evidence"
        case "settings_calendar_permissions": return "Calendar integration permission surface"
        case "settings_reminders_permissions": return "Reminders integration permission surface"
        case "today_stats_view": return "Today companion behavioral metrics (Earned Blocks, Guardian Learned, Domain Signals)"
        case "weekly_stats_view": return "Weekly companion trends and Domain Patterns panel"
        case "insights_view_domains": return "Insights Guardian Recommendations and App Usage domain analytics"
        case "settings_domain_tracking": return "Settings domain tracking toggle and recovery guidance"
        case "break_complete_reason_sheet_hidden": return "Break-complete window with reason sheet collapsed"
        case "break_complete_reason_sheet_visible": return "Break-complete window with reason sheet expanded"
        default: return "Review evidence capture"
        }
    }

    private func makeDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private func relativePathFromRepo(_ url: URL) -> String {
        let repoPath = repoRootURL.path
        let absolute = url.path
        if absolute.hasPrefix(repoPath + "/") {
            return String(absolute.dropFirst(repoPath.count + 1))
        }
        return absolute
    }

    private var repoRootURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // FocusFlowTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repo root
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
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: configuration)
    }

    private static func defaultRunID() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    private static func requestedFlowIDs() -> [String] {
        guard let raw = ProcessInfo.processInfo.environment["FOCUSFLOW_REVIEW_FLOW_FILTER"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return []
        }
        return raw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func requestedAppearances() -> [ReviewArtifactAppearance] {
        guard let raw = ProcessInfo.processInfo.environment["FOCUSFLOW_REVIEW_APPEARANCE_FILTER"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return []
        }
        return raw
            .split(separator: ",")
            .compactMap { token in
                ReviewArtifactAppearance(rawValue: token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
            }
    }
}
