import SwiftUI
import SwiftData

struct FocusFlowApp: App {
    @State private var timerVM = TimerViewModel()
    private let container: ModelContainer = {
        let schema = Schema([Project.self, FocusSession.self, AppSettings.self, TimeSplit.self, BlockProfile.self, AppUsageRecord.self])
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("FocusFlow", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let storeURL = dir.appendingPathComponent("FocusFlow.store")
        let config = ModelConfiguration(schema: schema, url: storeURL)
        return try! ModelContainer(for: schema, configurations: config)
    }()

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopoverView()
                .environment(timerVM)
                .environment(\.modelContext, container.mainContext)
                .background(CompletionWindowLauncher(timerVM: timerVM))
                .onAppear {
                    AppUsageTracker.shared.start(timerVM: timerVM)
                }
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
                .onAppear {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
        }
        .defaultSize(width: 720, height: 520)
        .modelContainer(container)

        Window("Session Complete", id: "session-complete") {
            SessionCompleteWindowView()
                .environment(timerVM)
                .environment(\.modelContext, container.mainContext)
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .modelContainer(container)
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

/// Invisible view that wires up the openWindow action to TimerViewModel.
/// Lives inside MenuBarExtra content so it has access to @Environment(\.openWindow).
private struct CompletionWindowLauncher: View {
    let timerVM: TimerViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                timerVM.openCompletionWindow = {
                    openWindow(id: "session-complete")
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
            }
    }
}
