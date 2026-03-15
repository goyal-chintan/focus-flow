// Sources/FocusFlow/FocusFlowApp.swift
import SwiftUI
import SwiftData

@main
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
        .modelContainer(for: [Project.self, FocusSession.self, AppSettings.self])

        Window("FocusFlow", id: "stats") {
            CompanionWindowView()
                .environment(timerVM)
        }
        .defaultSize(width: 700, height: 500)
        .modelContainer(for: [Project.self, FocusSession.self, AppSettings.self])
    }
}
