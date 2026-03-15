import SwiftUI
import SwiftData

struct FocusFlowApp: App {
    @State private var timerVM = TimerViewModel()
    private let container: ModelContainer = {
        let schema = Schema([Project.self, FocusSession.self, AppSettings.self])
        let config = ModelConfiguration(schema: schema)
        return try! ModelContainer(for: schema, configurations: config)
    }()

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopoverView()
                .environment(timerVM)
                .onAppear {
                    timerVM.configure(modelContext: container.mainContext)
                    NotificationService.shared.requestPermission()
                }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "timer")
                if timerVM.state == .paused {
                    Text("\u{23F8}")
                } else if timerVM.isRunning {
                    Text(timerVM.timeString)
                        .monospacedDigit()
                }
                if timerVM.todayFocusTime > 0 || timerVM.isRunning {
                    if timerVM.isRunning {
                        Text("\u{00B7}")
                            .foregroundStyle(.secondary)
                    }
                    Text(timerVM.todayFocusTime.formattedFocusTime)
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
                .onAppear {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
        }
        .defaultSize(width: 720, height: 520)
        .modelContainer(container)
    }
}
