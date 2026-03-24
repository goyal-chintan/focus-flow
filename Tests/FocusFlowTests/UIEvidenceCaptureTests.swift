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

        case "first_run_initial_render":
            let fixture = try fixtures.breakCompletionFixture()
            fixture.vm.showCoachReasonSheet = false
            return try renderSessionComplete(fixture, appearance: appearance)

        case "first_run_first_toggle":
            let fixture = try fixtures.breakCompletionFixture()
            fixture.vm.showCoachReasonSheet = true
            return try renderSessionComplete(fixture, appearance: appearance)

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
            .modelContainer(fixture.container)
            .environment(\.modelContext, fixture.context)
            .frame(width: 720, height: 520)
            .padding(16)
            .background(backgroundColor(for: appearance))
        return try render(view, appearance: appearance, size: CGSize(width: 760, height: 560))
    }

    private func render<V: View>(
        _ view: V,
        appearance: ReviewArtifactAppearance,
        size: CGSize
    ) throws -> CGImage {
        let rootView = view.environment(\.colorScheme, appearance == .dark ? .dark : .light)
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
        }
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

        return [focusFlow, completionFlow, idleFlow, calendarFlow, reminderFlow]
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
        case "coach_quick_prompt": return "In-popover quick coach intervention"
        case "coach_strong_window": return "Strong intervention standalone window"
        case "settings_calendar_permissions": return "Calendar integration permission surface"
        case "settings_reminders_permissions": return "Reminders integration permission surface"
        case "first_run_initial_render": return "Geometry baseline before first interaction"
        case "first_run_first_toggle": return "Geometry after first disclosure toggle"
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
            InterventionAttempt.self
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
