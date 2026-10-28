import AppKit
import SwiftUI
import SwiftData

/// The notch companion's AppKit host, set on `TimerViewModel.notchHost` by FocusFlowApp.
@MainActor
protocol NotchHosting: AnyObject {
    func setEnabled(_ enabled: Bool)
}

/// A borderless panel above the menu bar that never takes focus. Buttons work without
/// activating FocusFlow, so the app you're in keeps the keyboard.
final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Hosts `NotchView` around the MacBook notch (or as a pill on the top edge of a screen without
/// one). Compact: a ring and a number in the wings. Hover: it springs open into a small control
/// surface. The window is resized to the island so clicks beside it reach the menu bar.
@MainActor
final class NotchController: NotchHosting {
    private let timerVM: TimerViewModel
    private let modelContainer: ModelContainer
    private let state = NotchState()
    private var panel: NotchPanel?
    private var geometry: NotchGeometry?
    private var hoverTask: Task<Void, Never>?
    private var screenObserver: NSObjectProtocol?
    private(set) var isEnabled = false

    /// Hover in → open after this (a pass-through on the way to the menu bar doesn't open it).
    static let openDelay: Duration = .milliseconds(140)
    /// Hover out → close after this (moving between buttons near the edge doesn't close it).
    static let closeDelay: Duration = .milliseconds(380)

    init(timerVM: TimerViewModel, modelContainer: ModelContainer) {
        self.timerVM = timerVM
        self.modelContainer = modelContainer
        state.onHover = { [weak self] hovering in self?.hoverChanged(hovering) }
        state.onTapCompact = { [weak self] in self?.expand() }
        state.onExpandedHeight = { [weak self] _ in self?.fitExpandedWindow() }
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        if enabled {
            screenObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.layout() }
            }
            layout()
            panel?.orderFrontRegardless()
        } else {
            if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
            screenObserver = nil
            hoverTask?.cancel()
            state.expanded = false
            panel?.orderOut(nil)
        }
    }

    // MARK: Layout

    /// The built-in display (the one with a notch) when present, else the main display.
    private func targetScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
    }

    private func layout() {
        guard isEnabled, let screen = targetScreen() else { return }
        let geometry = NotchGeometry(
            screenFrame: screen.frame,
            safeAreaTop: screen.safeAreaInsets.top,
            leftAreaWidth: screen.auxiliaryTopLeftArea?.width,
            rightAreaWidth: screen.auxiliaryTopRightArea?.width,
            menuBarHeight: NSStatusBar.system.thickness
        )
        self.geometry = geometry
        state.notchSize = geometry.notch.size
        state.hasHardwareNotch = geometry.hasHardwareNotch
        let panel = ensurePanel()
        panel.setFrame(state.expanded ? geometry.expandedFrame : geometry.compactFrame, display: true)
        panel.orderFrontRegardless()
    }

    private func ensurePanel() -> NotchPanel {
        if let panel { return panel }
        let panel = NotchPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        // Above the menu bar so the island can cover the notch row.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.acceptsMouseMovedEvents = true
        panel.title = "FocusFlow"

        let root = NotchLiveView(state: state, actions: makeActions())
            .environment(timerVM)
            .modelContainer(modelContainer)
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        self.panel = panel
        return panel
    }

    // MARK: Hover

    private func hoverChanged(_ hovering: Bool) {
        hoverTask?.cancel()
        hoverTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: hovering ? Self.openDelay : Self.closeDelay)
            guard !Task.isCancelled, let self else { return }
            hovering ? self.expand() : self.collapse()
        }
    }

    private func expand() {
        guard let geometry, let panel, !state.expanded else { return }
        // Grow the window first, then let SwiftUI spring the island open inside it.
        panel.setFrame(geometry.expandedFrame, display: true)
        state.expanded = true
    }

    /// Once the open island has measured its content, trim the window to it (top edge fixed).
    private func fitExpandedWindow() {
        guard state.expanded, let geometry, let panel else { return }
        var frame = geometry.expandedFrame
        let height = min(frame.height, max(geometry.notch.height + 80, state.expandedHeight))
        frame.origin.y = frame.maxY - height
        frame.size.height = height
        // Wait for the open animation so the island never clips while it springs.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard let self, self.state.expanded else { return }
            panel.setFrame(frame, display: true)
        }
    }

    private func collapse() {
        guard state.expanded else { return }
        state.expanded = false
        Task { @MainActor [weak self] in
            // After the close animation, shrink the window back so it never blocks the menu bar.
            try? await Task.sleep(for: .milliseconds(420))
            guard let self, !self.state.expanded, let geometry = self.geometry else { return }
            self.panel?.setFrame(geometry.compactFrame, display: true)
        }
    }

    // MARK: Actions

    private func makeActions() -> NotchActions {
        let vm = timerVM
        return NotchActions(
            pause: { vm.pause() },
            resume: { vm.resume() },
            extend: { vm.extendTimer(by: 300) },
            finish: { [weak self] in self?.collapse(); vm.stopForReflection() },
            keepGoing: { vm.continueAfterCompletion(action: .continueOvertime) },
            takeBreak: { vm.continueAfterCompletion(action: .takeBreak(duration: 300)) },
            end: { [weak self] in self?.collapse(); vm.continueAfterCompletion(action: .endSession) },
            skipBreak: { vm.skipBreak() },
            toggleBreak: { vm.isBreakPaused ? vm.resumeBreak() : vm.pauseBreak() },
            start: { [weak self] minutes in
                let lever = GoalDataBuilder.levers(vm.historyReaderActiveGoals(), now: Date()).first
                if vm.startNextBlock(minutes: minutes, projectID: lever?.projectID) { self?.collapse() }
            },
            logResult: { id in vm.logGoalProgress(resultID: id, amount: 1) },
            openGoals: { [weak self] in
                self?.collapse()
                vm.openCompanionWindow?(.goals)
            }
        )
    }
}

/// Builds the snapshot from the live timer and the store.
private struct NotchLiveView: View {
    let state: NotchState
    let actions: NotchActions

    @Environment(TimerViewModel.self) private var vm
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NotchView(state: state, snapshot: snapshot(now: Date()), actions: actions)
    }

    private func snapshot(now: Date) -> NotchSnapshot {
        let mode: NotchSnapshot.Mode
        switch vm.state {
        case .idle: mode = vm.isOvertime ? .overtime : .idle
        case .focusing: mode = vm.isOvertime ? .overtime : .focusing
        case .paused: mode = .paused
        case .onBreak: mode = .onBreak(paused: vm.isBreakPaused)
        }
        let goals = vm.historyReaderActiveGoals()
        let levers = GoalDataBuilder.levers(goals, now: now)
        let projects = (try? modelContext.fetch(FetchDescriptor<Project>(predicate: #Predicate { !$0.archived }))) ?? []
        let topProject = projects.filter { $0.priorityRank != nil }.min { ($0.priorityRank ?? .max) < ($1.priorityRank ?? .max) }
        let leverProject = levers.first?.projectID.flatMap { id in projects.first { $0.id == id } }
        let shownProject: Project? = mode == .idle ? (leverProject ?? topProject) : vm.selectedProject

        var verdict: String?
        if mode == .idle, state.expanded {
            let dayStart = Calendar.current.startOfDay(for: now)
            let since = dayStart.addingTimeInterval(-12 * 3600)
            let sessions = (try? modelContext.fetch(FetchDescriptor<FocusSession>(predicate: #Predicate { $0.startedAt >= since }))) ?? []
            let samples = sessions.filter { $0.type == .focus }.map(FocusSample.init)
            let day = DateInterval(start: dayStart, end: dayStart.addingTimeInterval(86_400))
            let allocation = GoalDataBuilder.allocation(samples: samples, projects: projects, day: day)
            verdict = allocation.totalSeconds > 0 ? allocation.shortVerdict(format: FFFormat.duration) : nil
        }

        var quick: (id: UUID, title: String, done: Double, target: Double)?
        if mode == .focusing || mode == .paused, let projectID = vm.selectedProject?.id {
            let lever = levers.first { $0.projectID == projectID }
            let result = goals.filter { $0.projectID == projectID }
                .flatMap(\.sortedKeyResults)
                .first { $0.id == lever?.id && $0.kind == .count }
                ?? goals.filter { $0.projectID == projectID }.flatMap(\.sortedKeyResults).first { $0.kind == .count && $0.done < $0.target }
            if let result { quick = (result.id, result.title, result.done, result.target) }
        }

        let attention = mode == .idle && (vm.coachPanel != nil || vm.coachMenuBarPulse)
        let ownOnly = GoalDataBuilder.ownWorkConfigured(projects)
        return NotchSnapshot(
            mode: mode,
            time: vm.isOvertime ? vm.overtimeTimeString : vm.timeString,
            progress: min(1, vm.progress),
            projectName: shownProject?.name,
            projectColor: shownProject?.color,
            intent: vm.currentIntentText,
            goalDone: vm.goalProgressSeconds(now: now),
            goalTarget: vm.settings?.dailyFocusGoal ?? 7200,
            goalLabel: ownOnly ? "Your own work" : "Focus today",
            lever: levers.first,
            verdict: verdict,
            coachHook: attention ? (vm.coachPanel?.message.hook ?? "The coach has a start for you.") : nil,
            quickResult: quick
        )
    }
}
