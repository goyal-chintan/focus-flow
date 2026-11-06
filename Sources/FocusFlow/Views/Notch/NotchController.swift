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
            setLength: { minutes in vm.setBlockLength(minutes: minutes) },
            finish: { [weak self] in self?.collapse(); vm.stopForReflection() },
            // Coach v7 §3.1: a 10-minute lap, then the block-end window comes back.
            keepGoing: { vm.keepGoingLap() },
            takeBreak: { vm.continueAfterCompletion(action: .takeBreak(duration: 300)) },
            end: { [weak self] in self?.collapse(); vm.continueAfterCompletion(action: .endSession) },
            skipBreak: { vm.skipBreak() },
            startAfterBreak: { [weak self] in self?.collapse(); vm.continueAfterCompletion(action: .continueFocusing) },
            toggleBreak: { vm.isBreakPaused ? vm.resumeBreak() : vm.pauseBreak() },
            start: { [weak self] minutes in
                // The picked project first; with none, the first lever's project.
                let projectID = vm.selectedProject?.id
                    ?? PopoverProjectScope.lever(vm.todayLevers(), projectID: nil)?.projectID
                if vm.startNextBlock(minutes: minutes, projectID: projectID) { self?.collapse() }
            },
            logResult: { id in vm.logOneMore(resultID: id) },
            tickTask: { id in
                if let task = vm.todayTasks().first(where: { $0.id == id }) { vm.advanceDailyTask(task) }
            },
            undoTask: { vm.undoDailyTaskReceipt() },
            log: { [weak self] in
                // Same as the popover's "Log this block": the block-end window.
                self?.collapse()
                vm.openCompletionWindow?()
                vm.requestAppActivation?()
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
        let mode = NotchSnapshot.Mode.from(
            state: vm.state, isOvertime: vm.isOvertime,
            isBreakOvertime: vm.isBreakOvertime, isBreakPaused: vm.isBreakPaused
        )
        let goals = vm.historyReaderActiveGoals()
        let levers = vm.todayLevers(now: now)
        let projects = (try? modelContext.fetch(FetchDescriptor<Project>(predicate: #Predicate { !$0.archived }))) ?? []
        let topProject = projects.filter { $0.priorityRank != nil }.min { ($0.priorityRank ?? .max) < ($1.priorityRank ?? .max) }
        let leverProject = levers.first?.projectID.flatMap { id in projects.first { $0.id == id } }
        // Idle follows the project picked in the popover; a block or break follows that block.
        let shownProject: Project? = mode == .idle ? (vm.selectedProject ?? leverProject ?? topProject) : vm.selectedProject
        let scopeID = mode == .idle ? shownProject?.id : vm.taskScopeProjectID
        let lever = PopoverProjectScope.lever(levers, projectID: scopeID)

        let idleOpen = mode == .idle && state.expanded
        // The learned size is a store read: only while the idle island is open.
        let suggested = idleOpen ? vm.startLadderRecommendation(now: now).minutes : CoachBlockSizeLadder.defaultMinutes

        var quick: (id: UUID, title: String, done: Double, target: Double)?
        if mode == .focusing || mode == .paused, let projectID = vm.selectedProject?.id {
            let lever = levers.first { $0.projectID == projectID }
            let result = goals.filter { $0.projectID == projectID }
                .flatMap(\.sortedKeyResults)
                .first { $0.id == lever?.id && $0.kind == .count }
                ?? goals.filter { $0.projectID == projectID }.flatMap(\.sortedKeyResults).first { $0.kind == .count && $0.done < $0.target }
            if let result { quick = (result.id, result.title, result.done, result.target) }
        }

        // Today's tasks: in a block, only the block's own task (no fallback to the next one).
        let todays = vm.todayTasks(now: now)
        let taskStats = DailyTaskPlanner.stats(DailyTaskPlanner.forProject(todays, scopeID), on: now)
        let next: DailyTask?
        if mode == .focusing || mode == .paused {
            next = vm.currentBlockTaskID.flatMap { id in todays.first { $0.id == id && !$0.isDone } }
        } else {
            next = DailyTaskPlanner.nextTask(todays, on: now, for: shownProject?.id)
        }

        let attention = mode == .idle && (vm.coachPanel != nil || vm.coachMenuBarPulse)
        // The day's goal, sized by today's day type (coach v8 §3.5) as on Today and in Goals.
        let dailyGoal = vm.dailyGoal(now: now)
        return NotchSnapshot(
            mode: mode,
            time: vm.isOvertime ? vm.overtimeTimeString : vm.timeString,
            progress: min(1, vm.progress),
            projectName: shownProject?.name,
            projectColor: shownProject?.color,
            intent: vm.currentIntentText,
            goalDone: vm.goalProgressSeconds(now: now),
            goalTarget: dailyGoal.seconds,
            goalLabel: dailyGoal.label,
            lever: lever,
            coachHook: attention ? (vm.coachPanel?.message.hook ?? "The coach has a start for you.") : nil,
            quickResult: quick,
            tasks: taskStats,
            nextTask: next.map { ($0.id, $0.title) },
            nextTaskCount: next.flatMap { $0.isCounted ? ($0.loggedCount, $0.progressAmount) : nil },
            receipt: vm.dailyTaskReceipt?.text,
            suggestedMinutes: suggested,
            regularMinutes: vm.regularMinutes,
            growToMinutes: CoachBlockSizeLadder.sizes.first { $0 > vm.blockLengthMinutes && vm.canSetBlockLength($0) }
        )
    }
}
