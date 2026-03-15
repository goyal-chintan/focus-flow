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
        .modelContainer(container)

        Window("FocusFlow", id: "stats") {
            CompanionWindowView()
                .environment(timerVM)
        }
        .defaultSize(width: 720, height: 520)
        .modelContainer(container)
    }
}
