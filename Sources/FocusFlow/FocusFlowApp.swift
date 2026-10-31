import SwiftUI
import SwiftData
import EventKit

struct FocusFlowApp: App {
    @State private var timerVM = TimerViewModel()
    @Environment(\.scenePhase) private var scenePhase
    private let container: ModelContainer = {
        let schema = Schema([Project.self, FocusSession.self, AppSettings.self, TimeSplit.self, BlockProfile.self, AppUsageRecord.self, AppUsageEntry.self, TaskIntent.self, CoachInterruption.self, InterventionAttempt.self, BreakLearningEvent.self, IdleDistractionItem.self, WeeklyPriority.self, PlannedBlock.self, ProjectGoal.self, GoalKeyResult.self, GoalProgressEntry.self, DailyTask.self, BlockStartEvent.self])
        let dir = (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("FocusFlow", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let storeURL = dir.appendingPathComponent("FocusFlow.store")
        #if DEBUG
        // FOCUSFLOW_DEBUG_FRESH_STORE=1: an empty in-memory store, so first-run screens (the welcome
        // tour) can be tried without touching the real store.
        if ProcessInfo.processInfo.environment["FOCUSFLOW_DEBUG_FRESH_STORE"] == "1",
           let fresh = try? ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)) {
            return fresh
        }
        #endif
        do {
            try StoreMigrator.migrateStoreIfNeeded(at: storeURL)
            let config = ModelConfiguration(schema: schema, url: storeURL)
            return try ModelContainer(for: schema, configurations: config)
        } catch {
            print("⚠️ FocusFlow: Failed to open store with migration — \(error). Creating fresh container.")
            do {
                let fallbackConfig = ModelConfiguration(schema: schema)
                return try ModelContainer(for: schema, configurations: fallbackConfig)
            } catch {
                print("⚠️ FocusFlow: Fallback container also failed — \(error). Using in-memory store.")
                let inMemoryConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                do {
                    return try ModelContainer(for: schema, configurations: inMemoryConfig)
                } catch {
                    fatalError("FocusFlow: Cannot create any ModelContainer — \(error)")
                }
            }
        }
    }()

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopoverView()
                .environment(timerVM)
                .environment(\.modelContext, container.mainContext)
                .background(WindowLauncherBridge(timerVM: timerVM))
        } label: {
            Group {
                if timerVM.isPrivate {
                    // Screen shared: a plain dot that names nothing (SharePrivacy).
                    Image(systemName: "circle.fill")
                        .font(.system(size: 7))
                        .accessibilityLabel("Private")
                } else {
                    liveLabel
                }
            }
            // Outside the branch, so toggling privacy never re-runs the launch wiring.
            .background(AppLaunchBridge(timerVM: timerVM, modelContext: container.mainContext).modelContainer(container))
            #if DEBUG
            .background(DebugWindowCaptureBridge())
            #endif
        }
        .menuBarExtraStyle(.window)
        .modelContainer(container)

        Window("FocusFlow", id: "stats") {
            CompanionWindowView()
                // Minimum frame gives AppKit's constraint engine a concrete lower bound
                // during the initial layout pass and, with .contentMinSize, the window's min size.
                .frame(minWidth: 780, minHeight: 540)
                .environment(timerVM)
                .environment(\.modelContext, container.mainContext)
        }
        .defaultSize(width: 960, height: 640)
        .windowResizability(.contentMinSize)
        .modelContainer(container)

        Window("Block complete", id: "session-complete") {
            SessionCompleteWindowView()
                .environment(timerVM)
                .environment(\.modelContext, container.mainContext)
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .modelContainer(container)

        // Settings window (⌘, and the popover gear). SettingsView owns its toolbar tab bar;
        // the expanded toolbar style puts the tab title above the centred bar, like the
        // native Settings layout, and the fixed content size keeps the window from jumping.
        Settings {
            SettingsView()
                .environment(timerVM)
                .environment(\.modelContext, container.mainContext)
        }
        .windowToolbarStyle(.expanded)
        .windowResizability(.contentSize)
        .modelContainer(container)
    }

    /// The usual label: icon, prompt dot, drift counter, blocking shield, timer and today's total.
    private var liveLabel: some View {
        HStack(spacing: 5) {
            Image(systemName: menuBarIconName)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                // A few pulses when a prompt starts waiting, then a static dot (v3 R9: a
                // repeating effect re-laid out the status item every frame, ~30% CPU for days).
                .symbolEffect(.pulse, options: .repeat(3), value: timerVM.coachMenuBarPulse)
                .accessibilityHidden(true)

            // A coach prompt is waiting (panel auto-hid or a badge prompt): clears on open.
            if timerVM.coachMenuBarPulse {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 5, height: 5)
                    .accessibilityLabel("Focus coach prompt waiting")
            }

            // Rescue loop: ambient drift counter while drifting in a focus window.
            if let driftText = timerVM.driftMenuBarText {
                DriftMenuBarCounter(text: driftText)
            }

            if timerVM.isBlockingActive {
                Image(systemName: "shield.checkered")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
            }

            if let liveStatusText {
                Text(liveStatusText)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(liveStatusColor)
            }

            if timerVM.todayFocusTime > 0 || timerVM.isRunning || timerVM.isOvertime {
                if liveStatusText != nil {
                    Text("·")
                        .foregroundStyle(.secondary)
                }
                Text(timerVM.todayFocusTime.formattedFocusTime)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 12, weight: .medium, design: .rounded))
    }

    private var liveStatusText: String? {
        if timerVM.isOvertime {
            return timerVM.overtimeTimeString
        }
        if timerVM.state == .paused {
            return "⏸"
        }
        if timerVM.isRunning {
            return timerVM.timeString
        }
        return nil
    }

    private var liveStatusColor: Color {
        if timerVM.isOvertime {
            return .orange
        }
        if timerVM.state == .paused {
            return .orange
        }
        return .primary
    }

    private var menuBarIconName: String {
        switch timerVM.state {
        case .idle:
            // A break running over keeps the cup: the orange +M:SS is break time, not a block's.
            if timerVM.isBreakOvertime { return "cup.and.saucer.fill" }
            return timerVM.coachMenuBarPulse ? "bolt.circle.fill" : "bolt.circle"
        case .focusing, .paused:
            return timerVM.selectedProject?.icon ?? "scope"
        case .onBreak(let type):
            switch type {
            case .shortBreak:
                return "cup.and.saucer.fill"
            case .longBreak:
                return "figure.walk"
            case .focus:
                return timerVM.selectedProject?.icon ?? "scope"
            }
        }
    }
}

private struct AppLaunchBridge: View {
    let timerVM: TimerViewModel
    let modelContext: ModelContext
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    @Query private var rescueSettings: [AppSettings]

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .task {
                // On-screen coach panel (non-activating NSPanel) and the Settings opener for the
                // weekly-priorities invite. Wired before configure so launch prompts can show.
                if timerVM.coachPanelHost == nil {
                    timerVM.coachPanelHost = CoachPanelController(timerVM: timerVM, modelContainer: modelContext.container)
                }
                timerVM.openSettingsScene = {
                    WindowPolicyManager.shared.prepareToOpen()
                    openSettings()
                }
                // Rescue loop: full-screen pause screen host and the ⌃⌥Space starter shortcut.
                if timerVM.pauseScreenHost == nil {
                    timerVM.pauseScreenHost = PauseScreenController(timerVM: timerVM, modelContainer: modelContext.container)
                }
                if timerVM.hotkeyRegistrar == nil {
                    timerVM.hotkeyRegistrar = CoachGlobalHotkey.shared
                }
                timerVM.openCompanionWindow = { tab in
                    UserDefaults.standard.set(tab.rawValue, forKey: "companionRequestedTab")
                    WindowPolicyManager.shared.prepareToOpen()
                    openWindow(id: "stats")
                }
                if timerVM.openOnboarding == nil {
                    // Welcome tour, full screen (onboarding v2 §3.5): first launch, and Settings → General → Getting started.
                    let onboarding = OnboardingController(timerVM: timerVM, modelContainer: modelContext.container)
                    timerVM.openOnboarding = { onboarding.show() }
                }
                // Coach v4: the decision journal, written in release builds too.
                if timerVM.coachJournal.fileURL == nil, !timerVM.isEvidenceMode {
                    timerVM.coachJournal = CoachJournal(fileURL: CoachJournal.defaultURL())
                }
                timerVM.ensureConfigured(modelContext: modelContext)
                // Notch companion (notch design §2): on unless turned off in Settings.
                if timerVM.notchHost == nil, !timerVM.isEvidenceMode {
                    let notch = NotchController(timerVM: timerVM, modelContainer: modelContext.container)
                    timerVM.notchHost = notch
                    notch.setEnabled(timerVM.isNotchCompanionEnabled)
                }
                timerVM.syncGlobalHotkey()
                if !timerVM.isEvidenceMode {
                    timerVM.startPrivacyMonitor()
                    timerVM.startReminderSyncObservers()
                }
                WindowPolicyManager.shared.start()
                showOnboardingIfNeeded()
            }
            .onChange(of: rescueSettings.first?.coachGlobalHotkeyEnabled) { _, _ in
                timerVM.syncGlobalHotkey()
            }
    }
}

extension AppLaunchBridge {
    /// First launch on an empty store opens the welcome tour; an existing store is marked done silently.
    fileprivate func showOnboardingIfNeeded() {
        guard !timerVM.isEvidenceMode, let settings = timerVM.settings else { return }
        let hasSessions = ((try? modelContext.fetchCount(FetchDescriptor<FocusSession>())) ?? 0) > 0
        switch OnboardingLaunch.decide(completedAt: settings.onboardingCompletedAt, hasSessions: hasSessions) {
        case .show:
            timerVM.openOnboarding?()
        case .markDone:
            settings.onboardingCompletedAt = Date()
            try? modelContext.save()
        case .none:
            break
        }
    }
}

/// Invisible view that wires up openWindow actions to TimerViewModel.
/// Lives inside MenuBarExtra content so it has access to @Environment(\.openWindow).
private struct WindowLauncherBridge: View {
    let timerVM: TimerViewModel
    @Environment(\.openWindow) private var openWindow
    @Query private var allSettings: [AppSettings]
    @Environment(\.modelContext) private var modelContext

    private var settings: AppSettings? { allSettings.first }

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                timerVM.openCompletionWindow = {
                    WindowPolicyManager.shared.prepareToOpen()
                    openWindow(id: "session-complete")
                }
                timerVM.requestAppActivation = {
                    WindowPolicyManager.shared.prepareToOpen()
                }
                // Graceful shutdown — save session state on app termination
                NotificationCenter.default.addObserver(
                    forName: NSApplication.willTerminateNotification,
                    object: nil,
                    queue: .main
                ) { _ in
                    Task { @MainActor in
                        timerVM.saveSessionBeforeTermination()
                    }
                }
                // Auto-pause running sessions when the Mac goes to sleep
                NSWorkspace.shared.notificationCenter.addObserver(
                    forName: NSWorkspace.willSleepNotification,
                    object: nil,
                    queue: .main
                ) { _ in
                    Task { @MainActor in
                        timerVM.pauseForSystemSleep()
                    }
                }
                // Auto-resume if sleep was brief (accidental lid close)
                NSWorkspace.shared.notificationCenter.addObserver(
                    forName: NSWorkspace.didWakeNotification,
                    object: nil,
                    queue: .main
                ) { _ in
                    Task { @MainActor in
                        timerVM.resumeAfterSystemWake()
                    }
                }

                // Reconcile permissions when the popover first opens (Reminders sync has its own
                // always-on triggers: `TimerViewModel.startReminderSyncObservers`).
                reconcilePermissionsIfNeeded()
            }
            // Reconcile permissions every time the app becomes active — catches
            // revocations that happened while the app was in the background or
            // between launches after a rebuild with a new signature.
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                reconcilePermissionsIfNeeded()
                timerVM.checkDayRolloverIfNeeded()
            }
            // Also reconcile when EventKit reports store changes (permission
            // grants/revocations trigger this notification).
            .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in
                reconcilePermissionsIfNeeded()
            }
    }

    private func reconcilePermissionsIfNeeded() {
        guard let settings else { return }
        EventStoreManager.shared.reconcilePermissions(settings: settings)
        try? modelContext.save()
    }
}
