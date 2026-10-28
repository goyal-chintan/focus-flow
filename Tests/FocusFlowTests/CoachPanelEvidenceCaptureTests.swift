import XCTest
import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers
@testable import FocusFlow

/// Evidence renders for Coach v2 surfaces, in the same off-screen style as
/// `UIEvidenceCaptureTests`: the on-screen panel (three styles and its other kinds), the popover
/// intent field and the session-complete outcome chips, in light and dark.
///
/// Output: `FOCUSFLOW_CAPTURE_OUTPUT_DIR` when set, otherwise a temporary directory.
@MainActor
final class CoachPanelEvidenceCaptureTests: XCTestCase {
    private var containers: [ModelContainer] = []
    private var defaultsSuite = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaultsSuite = "FocusFlowTests-\(UUID())"
        defaults = UserDefaults(suiteName: defaultsSuite)!
    }

    override func tearDown() {
        containers.removeAll()
        defaults.removePersistentDomain(forName: defaultsSuite)
        super.tearDown()
    }

    func testCaptureCoachV2SurfacesInBothAppearances() throws {
        let output = outputDirectory()
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        for appearance in ReviewArtifactAppearance.allCases {
            let suffix = appearance.rawValue

            for style in CoachStyle.allCases {
                let image = try renderPanel(startNudgePresentation(style: style), appearance: appearance)
                try assertVisible(image, "panel \(style) \(suffix)")
                try writePNG(image, to: output.appendingPathComponent("coach_panel_\(style.rawValue)_\(suffix).png"))
            }

            let pseudo = CoachPanelPresentation(
                kind: .pseudoProductivity,
                message: CoachMessageComposer.compose(CoachComposerInput(
                    style: .challenger,
                    trigger: .pseudoProductivity(priority: "Ship Side App v1"),
                    facts: { var f = CoachFacts(); f.contextMinutes = 34; f.contextAppName = "Claude"; return f }(),
                    target: CoachStartTarget(minutes: 50, name: "Ship Side App v1")
                )),
                plan: CoachStartTarget(minutes: 50, name: "Ship Side App v1")
            )
            try writePNG(try renderPanel(pseudo, appearance: appearance), to: output.appendingPathComponent("coach_panel_pseudo_\(suffix).png"))

            let drift = CoachPanelPresentation(
                kind: .inSessionDrift,
                message: CoachMessageComposer.compose(CoachComposerInput(
                    style: .data,
                    trigger: .inSessionDrift(projectName: "Side App", appName: "YouTube", minutesInApp: 7),
                    facts: CoachFacts(),
                    target: CoachStartTarget(minutes: 25, name: "Side App")
                ))
            )
            try writePNG(try renderPanel(drift, appearance: appearance), to: output.appendingPathComponent("coach_panel_drift_\(suffix).png"))

            let weekly = CoachPanelPresentation(
                kind: .weeklyPriorities,
                message: CoachMessageComposer.compose(CoachComposerInput(
                    style: .challenger,
                    trigger: .weeklyPriorities,
                    facts: CoachFacts(),
                    target: CoachStartTarget(minutes: 25, name: nil)
                ))
            )
            try writePNG(try renderPanel(weekly, appearance: appearance), to: output.appendingPathComponent("coach_panel_weekly_\(suffix).png"))

            var quoteFacts = CoachFacts()
            quoteFacts.goalMinutes = 120
            quoteFacts.derailer = CoachDerailerFact(name: "X", minutesThisWeek: 52)
            let quote = CoachPanelPresentation(
                kind: .startNudge,
                message: CoachMessageComposer.compose(CoachComposerInput(
                    style: .challenger,
                    trigger: .startNudge,
                    facts: quoteFacts,
                    target: CoachStartTarget(minutes: 25, name: "Finish chapter 3"),
                    seed: 3
                ))
            )
            try writePNG(try renderPanel(quote, appearance: appearance), to: output.appendingPathComponent("coach_panel_quote_\(suffix).png"))

            // Coach v4: the start card (5 · 15 · 25 now, plan later) and a counter-offer.
            let cardTarget = CoachStartTarget(minutes: 15, name: "SQL interview prep")
            let card = CoachPanelPresentation(
                kind: .dailyPlan,
                message: CoachMessageComposer.compose(CoachComposerInput(
                    style: .challenger, trigger: .dailyPlan(goalMinutes: 120, firstSuggestion: nil),
                    facts: CoachFacts(), target: cardTarget,
                    pickedDetail: .houseLine("Starting is the whole game. 5 minutes counts.")
                )),
                plan: cardTarget,
                planSlots: [
                    CoachPlanSlot(start: Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!, reason: .bestWindow(lift: 2.1)),
                    CoachPlanSlot(start: Calendar.current.date(bySettingHour: 21, minute: 0, second: 0, of: Date())!, reason: .evening),
                ],
                sizeOptions: CoachBlockSizeLadder.sizes,
                recommendedMinutes: 15,
                sizeCaption: CoachBlockSizeLadder.Recommendation(minutes: 15, why: .starting).caption
            )
            let cardImage = try renderPanel(card, appearance: appearance)
            try assertVisible(cardImage, "start card \(suffix)")
            try writePNG(cardImage, to: output.appendingPathComponent("coach_panel_start_card_\(suffix).png"))

            var offerTarget = cardTarget
            offerTarget.minutes = 5
            offerTarget.findNextStep = true
            let offer = CoachPanelPresentation(
                kind: .startNudge,
                message: CoachMessageComposer.compose(CoachComposerInput(
                    style: .challenger, trigger: .counterOffer(reason: .unclearNextStep), facts: CoachFacts(), target: offerTarget
                )),
                plan: offerTarget
            )
            try writePNG(try renderPanel(offer, appearance: appearance), to: output.appendingPathComponent("coach_panel_counter_offer_\(suffix).png"))

            let error = try renderPanel(startNudgePresentation(style: .challenger), appearance: appearance, error: "Complete the current session first.")
            try writePNG(error, to: output.appendingPathComponent("coach_panel_error_\(suffix).png"))

            let popover = try renderPopoverWithIntent(appearance: appearance)
            try assertVisible(popover, "popover \(suffix)")
            try writePNG(popover, to: output.appendingPathComponent("popover_intent_\(suffix).png"))

            let complete = try renderSessionCompleteWithOutcome(appearance: appearance)
            try assertVisible(complete, "session complete \(suffix)")
            try writePNG(complete, to: output.appendingPathComponent("session_complete_outcome_\(suffix).png"))
        }
    }

    /// Rescue loop surfaces: ladder panels L1–L3, keep going, momentum, the shortcut notice,
    /// the pause screen, the menu bar counter and the popover during a starter block.
    func testCaptureRescueLoopSurfaces() throws {
        let output = outputDirectory()
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let target = CoachStartTarget(minutes: 50, name: "Ship Side App v1")
        let why = CoachMotivationItem.quote(CoachQuoteLibrary.quote(id: "king-amateurs")!)

        for appearance in ReviewArtifactAppearance.allCases {
            let suffix = appearance.rawValue
            let levels: [(DriftLevel, DriftSignal, CoachDetail?)] = [
                (.drifting, .derailer(name: "YouTube", minutes: 14), .quote(CoachQuoteLibrary.quote(id: "dillard-days")!)),
                (.lost, .derailer(name: "YouTube", minutes: 23), nil),
                (.spiral, .derailer(name: "YouTube", minutes: 47), nil),
            ]
            for (level, signal, picked) in levels {
                let ask = CoachRescueLadder.ask(level: level, target: target, starterMinutes: 5)!
                let rescue = CoachRescueContext(level: level, signal: signal, spanLabel: "in your 22:00 window", ask: ask, priorityName: target.name)
                var input = CoachComposerInput(style: .challenger, trigger: .rescue(rescue), facts: CoachFacts(), target: target)
                input.pickedDetail = picked
                let presentation = CoachPanelPresentation(
                    kind: .rescue, message: CoachMessageComposer.compose(input), plan: ask.target,
                    level: level, ask: ask, footerHint: CoachStarterBlock.hotkeyHint(minutes: 5)
                )
                let image = try renderPanel(presentation, appearance: appearance, height: 214)
                try assertVisible(image, "rescue L\(level.rawValue) \(suffix)")
                try writePNG(image, to: output.appendingPathComponent("rescue_panel_L\(level.rawValue)_\(suffix).png"))
            }

            var keepInput = CoachComposerInput(style: .challenger, trigger: .keepGoing(step: "Sketch the onboarding empty state"), facts: CoachFacts(), target: CoachStartTarget(minutes: 20))
            keepInput.pickedDetail = .quote(CoachQuoteLibrary.quote(id: "rohn-motivation-habit")!)
            let keep = CoachPanelPresentation(kind: .keepGoing, message: CoachMessageComposer.compose(keepInput), step: "Sketch the onboarding empty state")
            try writePNG(try renderPanel(keep, appearance: appearance, height: 196), to: output.appendingPathComponent("rescue_keep_going_\(suffix).png"))

            let momentum = CoachPanelPresentation(kind: .momentum, message: CoachMessageComposer.compose(CoachComposerInput(
                style: .challenger, trigger: .momentum, facts: CoachFacts(), target: CoachStartTarget(minutes: 25)
            )))
            try writePNG(try renderPanel(momentum, appearance: appearance, height: 180), to: output.appendingPathComponent("rescue_momentum_\(suffix).png"))

            let notice = CoachPanelPresentation(kind: .notice, message: CoachMessageComposer.compose(CoachComposerInput(
                style: .challenger, trigger: .starterStarted(minutes: 5), facts: CoachFacts(), target: CoachStartTarget(minutes: 5)
            )))
            try writePNG(try renderPanel(notice, appearance: appearance, height: 140), to: output.appendingPathComponent("rescue_hotkey_notice_\(suffix).png"))

            let pause = CoachPauseScreenPresentation(
                style: .challenger,
                headline: .quote(CoachQuoteLibrary.quote(id: "seneca-short-life")!),
                fact: "47 minutes on YouTube in your 22:00 window",
                starterMinutes: 5,
                attemptID: nil
            )
            let pauseImage = try render(
                PauseScreenView(presentation: pause, chrome: .standalone, showCloseImmediately: true).frame(width: 1440, height: 900),
                appearance: appearance,
                size: CGSize(width: 1440, height: 900)
            )
            try assertVisible(pauseImage, "pause screen \(suffix)")
            try writePNG(pauseImage, to: output.appendingPathComponent("rescue_pause_screen_challenger_\(suffix).png"))

            let lateNight = CoachPauseScreenPresentation(
                style: .challenger, headline: why, fact: "52 minutes on Netflix in your 23:00 window",
                starterMinutes: 2, attemptID: nil, lateNight: true
            )
            try writePNG(
                try render(PauseScreenView(presentation: lateNight, chrome: .standalone, showCloseImmediately: false).frame(width: 1440, height: 900), appearance: appearance, size: CGSize(width: 1440, height: 900)),
                to: output.appendingPathComponent("rescue_pause_screen_late_night_2min_\(suffix).png")
            )

            try writePNG(try renderMenuBar(appearance: appearance), to: output.appendingPathComponent("rescue_menu_bar_counter_\(suffix).png"))

            let popover = try renderPopoverStarter(appearance: appearance)
            try assertVisible(popover, "popover starter \(suffix)")
            try writePNG(popover, to: output.appendingPathComponent("rescue_popover_starter_\(suffix).png"))
        }
    }

    private func renderMenuBar(appearance: ReviewArtifactAppearance) throws -> CGImage {
        let dark = appearance == .dark
        let items: [String] = ["YouTube 23m", "Drift 41m", "Amazon Pr… 12m"]
        let view = VStack(spacing: 10) {
            ForEach(items, id: \.self) { text in
                HStack(spacing: 14) {
                    Spacer()
                    Image(systemName: "wifi").font(.system(size: 13, weight: .semibold))
                    HStack(spacing: 5) {
                        Image(systemName: "bolt.circle")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                        DriftMenuBarCounter(text: text)
                        Text("·").foregroundStyle(.secondary)
                        Text("52m").monospacedDigit().foregroundStyle(.secondary)
                    }
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    Text("Sat 22:41").font(.system(size: 13, weight: .medium))
                }
                .padding(.horizontal, 14)
                .frame(height: 26)
                .background(dark ? Color(hex: 0x2B2D33).opacity(0.92) : Color(hex: 0xF4F4F6).opacity(0.92))
            }
        }
        .padding(12)
        .background(LinearGradient(colors: dark ? [Color(hex: 0x1B2236), Color(hex: 0x2A1F33)] : [Color(hex: 0xDCE6F5), Color(hex: 0xF3E6EE)], startPoint: .leading, endPoint: .trailing))
        return try render(view, appearance: appearance, size: CGSize(width: 500, height: 126))
    }

    private func renderPopoverStarter(appearance: ReviewArtifactAppearance) throws -> CGImage {
        let container = try makeContainer()
        let context = container.mainContext
        let settings = AppSettings()
        context.insert(settings)
        try context.save()
        let vm = TimerViewModel(defaults: defaults)
        vm.systemIdleSecondsProvider = { 0 } // at the desk (v4 presence gate)
        vm.coachExploreSizes = false
        vm.configureForEvidence(modelContext: context, settings: settings)
        vm.seedEvidenceStarterState(step: "Sketch the onboarding empty state")
        let view = MenuBarPopoverView()
            .environment(vm)
            .modelContainer(container)
            .environment(\.modelContext, context)
            .padding(16)
            .background(appearance == .dark ? Color.black : Color.white)
        return try render(view, appearance: appearance, size: CGSize(width: 360, height: 760))
    }

    // MARK: Fixtures

    private func startNudgePresentation(style: CoachStyle) -> CoachPanelPresentation {
        var facts = CoachFacts()
        facts.hasHistory = true
        facts.streakDays = 6
        facts.sessionsToday = 1
        facts.goalMinutes = 120
        facts.doneMinutesToday = 56
        facts.pacing = CoachGoalPacing(goalMinutes: 120, doneMinutes: 56, windowMinutesLeft: 120)
        facts.derailer = style == .gentle ? nil : CoachDerailerFact(name: "YouTube", minutesThisWeek: 130)
        let target = CoachStartTarget(minutes: 50, name: "Ship Side App v1")
        let message = CoachMessageComposer.compose(CoachComposerInput(
            style: style,
            trigger: .startNudge,
            facts: facts,
            target: target,
            whyLines: ["Ship the side project by December"],
            seed: style == .gentle ? 1 : 2
        ))
        return CoachPanelPresentation(kind: .startNudge, message: message, plan: target)
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Project.self, FocusSession.self, AppSettings.self, TimeSplit.self, BlockProfile.self,
            AppUsageRecord.self, AppUsageEntry.self, TaskIntent.self, CoachInterruption.self,
            InterventionAttempt.self, BreakLearningEvent.self, IdleDistractionItem.self, WeeklyPriority.self, PlannedBlock.self, ProjectGoal.self, GoalKeyResult.self, GoalProgressEntry.self,
        ])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        containers.append(container)
        return container
    }

    // MARK: Renders

    private func renderPanel(_ presentation: CoachPanelPresentation, appearance: ReviewArtifactAppearance, error: String? = nil, height: CGFloat? = nil) throws -> CGImage {
        let view = ZStack(alignment: .topTrailing) {
            desktopBackdrop(appearance)
            CoachPanelView(presentation: presentation, chrome: .standalone, errorText: error)
                .shadow(color: .black.opacity(0.22), radius: 16, y: 8)
                .padding(20)
        }
        return try render(view, appearance: appearance, size: CGSize(width: 400, height: height ?? (error == nil ? 190 : 210)))
    }

    private func desktopBackdrop(_ appearance: ReviewArtifactAppearance) -> some View {
        LinearGradient(
            colors: appearance == .dark
                ? [Color(hex: 0x1B2236), Color(hex: 0x2A1F33)]
                : [Color(hex: 0xDCE6F5), Color(hex: 0xF3E6EE)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func renderPopoverWithIntent(appearance: ReviewArtifactAppearance) throws -> CGImage {
        let container = try makeContainer()
        let context = container.mainContext
        let settings = AppSettings()
        context.insert(settings)
        let project = Project(name: "Side App", color: "mint", icon: "hammer.fill")
        context.insert(project)
        let weekStart = WeeklyPriority.weekStart(for: Date())
        let ship = WeeklyPriority(title: "Ship Side App v1 onboarding", weekStart: weekStart, order: 0, projectID: project.id)
        context.insert(ship)
        context.insert(WeeklyPriority(title: "Finish chapter 3 draft", weekStart: weekStart, order: 1))
        try context.save()

        let vm = TimerViewModel(defaults: defaults)

        vm.systemIdleSecondsProvider = { 0 } // at the desk (v4 presence gate)

        vm.coachExploreSizes = false
        vm.configureForEvidence(modelContext: context, settings: settings)
        vm.selectedProject = project
        vm.reloadWeeklyPriorities()
        vm.pendingIntentText = "Onboarding empty states merged"
        vm.pendingPriorityID = ship.id

        let view = MenuBarPopoverView()
            .environment(vm)
            .modelContainer(container)
            .environment(\.modelContext, context)
            .padding(16)
            .background(appearance == .dark ? Color.black : Color.white)
        return try render(view, appearance: appearance, size: CGSize(width: 360, height: 820))
    }

    private func renderSessionCompleteWithOutcome(appearance: ReviewArtifactAppearance) throws -> CGImage {
        let container = try makeContainer()
        let context = container.mainContext
        let settings = AppSettings()
        context.insert(settings)
        let project = Project(name: "Side App", color: "mint", icon: "hammer.fill")
        context.insert(project)
        try context.save()

        let vm = TimerViewModel(defaults: defaults)

        vm.systemIdleSecondsProvider = { 0 } // at the desk (v4 presence gate)

        vm.coachExploreSizes = false
        vm.configureForEvidence(modelContext: context, settings: settings)
        vm.seedEvidenceCompletionState(sessionType: .focus, project: project, customLabel: nil, duration: 50 * 60, overtimeSeconds: 64)
        vm.lastCompletedFocusSession?.outcome = .movedForward
        vm.todayFocusTime = 106 * 60

        let view = SessionCompleteWindowView()
            .environment(vm)
            .modelContainer(container)
            .environment(\.modelContext, context)
            .padding(16)
            .background(appearance == .dark ? Color.black : Color.white)
        return try render(view, appearance: appearance, size: CGSize(width: 560, height: 980))
    }

    // MARK: Rendering (mirrors UIEvidenceCaptureTests.render)

    private func render<V: View>(_ view: V, appearance: ReviewArtifactAppearance, size: CGSize) throws -> CGImage {
        let rootView = view
            .environment(\.colorScheme, appearance == .dark ? .dark : .light)
            .environment(\.focusFlowEvidenceRendering, true)
        let host = NSHostingView(rootView: rootView)
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        let targetAppearance = appearance == .dark ? NSAppearance(named: .darkAqua) : NSAppearance(named: .aqua)

        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isOpaque = false
        window.appearance = targetAppearance
        host.appearance = targetAppearance
        window.contentView = host
        window.displayIfNeeded()

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.08))
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()

        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            throw NSError(domain: "CoachPanelEvidence", code: 1)
        }
        if let targetAppearance {
            targetAppearance.performAsCurrentDrawingAppearance { host.cacheDisplay(in: host.bounds, to: rep) }
        } else {
            host.cacheDisplay(in: host.bounds, to: rep)
        }
        guard let image = rep.cgImage else { throw NSError(domain: "CoachPanelEvidence", code: 2) }
        return image
    }

    private func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw NSError(domain: "CoachPanelEvidence", code: 3)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw NSError(domain: "CoachPanelEvidence", code: 4) }
    }

    /// The render must not be a blank canvas.
    private func assertVisible(_ image: CGImage, _ label: String) throws {
        XCTAssertGreaterThan(image.width, 0, label)
        let bitmap = NSBitmapImageRep(cgImage: image)
        var colors = Set<UInt32>()
        for x in stride(from: 0, to: bitmap.pixelsWide, by: 7) {
            for y in stride(from: 0, to: bitmap.pixelsHigh, by: 7) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let key = UInt32(color.redComponent * 31) << 10 | UInt32(color.greenComponent * 31) << 5 | UInt32(color.blueComponent * 31)
                colors.insert(key)
            }
        }
        XCTAssertGreaterThan(colors.count, 12, "\(label) looks blank")
    }

    private func outputDirectory() -> URL {
        if let override = ProcessInfo.processInfo.environment["FOCUSFLOW_CAPTURE_OUTPUT_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.temporaryDirectory.appendingPathComponent("focusflow-coach-v2-evidence", isDirectory: true)
    }
}
