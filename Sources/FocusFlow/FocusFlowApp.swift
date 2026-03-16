import SwiftUI
import SwiftData

struct FocusFlowApp: App {
    @State private var timerVM = TimerViewModel()
    private let container: ModelContainer = {
        let schema = Schema([Project.self, FocusSession.self, AppSettings.self, TimeSplit.self, BlockProfile.self])
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
        } label: {
            HStack(spacing: 6) {
                Image(systemName: menuBarIconName)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))

                if timerVM.isBlockingActive {
                    Image(systemName: "shield.checkered")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(FFColor.success)
                }
                if timerVM.isOvertime {
                    Text(timerVM.overtimeTimeString)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(.orange)
                } else if timerVM.state == .paused {
                    Text("\u{23F8}")
                        .foregroundStyle(FFColor.warning)
                } else if timerVM.isRunning {
                    Text(timerVM.timeString)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(.primary)
                }

                if timerVM.todayFocusTime > 0 || timerVM.isRunning || timerVM.isOvertime {
                    if timerVM.isRunning || timerVM.isOvertime {
                        Text("\u{00B7}")
                            .foregroundStyle(.secondary)
                    }
                    Text(timerVM.todayFocusTime.formattedFocusTime)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(.secondary.opacity(0.9))
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
