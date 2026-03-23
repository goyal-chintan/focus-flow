import SwiftUI
import SwiftData

struct FocusFlowApp: App {
    @State private var timerVM = TimerViewModel()
    @Environment(\.scenePhase) private var scenePhase
    private let container: ModelContainer = {
        let schema = Schema([Project.self, FocusSession.self, AppSettings.self, TimeSplit.self, BlockProfile.self, AppUsageRecord.self, AppUsageEntry.self, TaskIntent.self, CoachInterruption.self, InterventionAttempt.self])
        let dir = (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("FocusFlow", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let storeURL = dir.appendingPathComponent("FocusFlow.store")
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
            HStack(spacing: 5) {
                Image(systemName: menuBarIconName)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))

                if timerVM.isBlockingActive {
                    Image(systemName: "shield.checkered")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.green)
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
        .menuBarExtraStyle(.window)
        .modelContainer(container)

        Window("FocusFlow", id: "stats") {
            CompanionWindowView()
                .environment(timerVM)
                .environment(\.modelContext, container.mainContext)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 720, height: 520)
        .modelContainer(container)

        Window("Session Complete", id: "session-complete") {
            SessionCompleteWindowView()
                .environment(timerVM)
                .environment(\.modelContext, container.mainContext)
                .preferredColorScheme(.dark)
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .modelContainer(container)

        Window("Focus Coach", id: "coach-intervention") {
            CoachInterventionWindowView()
                .environment(timerVM)
                .environment(\.modelContext, container.mainContext)
                .preferredColorScheme(.dark)
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .modelContainer(container)

        // Keyboard shortcuts
        Settings {
            CompanionWindowView()
                .environment(timerVM)
                .environment(\.modelContext, container.mainContext)
                .preferredColorScheme(.dark)
        }
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
            return "bolt.circle"
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

/// Invisible view that wires up openWindow actions to TimerViewModel.
/// Lives inside MenuBarExtra content so it has access to @Environment(\.openWindow).
private struct WindowLauncherBridge: View {
    let timerVM: TimerViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                timerVM.openCompletionWindow = {
                    openWindow(id: "session-complete")
                }
                timerVM.openCoachInterventionWindow = {
                    openWindow(id: "coach-intervention")
                }
                timerVM.requestAppActivation = {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
                // Graceful shutdown — save session state on app termination
                NotificationCenter.default.addObserver(
                    forName: NSApplication.willTerminateNotification,
                    object: nil,
                    queue: .main
                ) { _ in
                    timerVM.saveSessionBeforeTermination()
                }
            }
    }
}
