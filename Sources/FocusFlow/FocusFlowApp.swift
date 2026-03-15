import SwiftUI
import SwiftData

struct FocusFlowApp: App {
    @State private var timerVM = TimerViewModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopoverView()
                .environment(timerVM)
        } label: {
            if timerVM.isRunning {
                HStack(spacing: 4) {
                    Image(systemName: "timer")
                    Text(timerVM.timeString)
                        .monospacedDigit()
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                }
            } else {
                Image(systemName: "timer")
            }
        }
        .menuBarExtraStyle(.window)
        .modelContainer(for: [Project.self, FocusSession.self, AppSettings.self]) { result in
            if case .success(let container) = result {
                timerVM.configure(modelContext: container.mainContext)
                NotificationService.shared.requestPermission()
            }
        }

        Window("FocusFlow", id: "stats") {
            CompanionWindowView()
                .environment(timerVM)
        }
        .defaultSize(width: 720, height: 520)
        .modelContainer(for: [Project.self, FocusSession.self, AppSettings.self])
    }
}
