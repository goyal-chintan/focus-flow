// Sources/FocusFlow/FocusFlowApp.swift
import SwiftUI
import SwiftData

struct FocusFlowApp: App {
    var body: some Scene {
        MenuBarExtra {
            MenuBarPopoverView()
        } label: {
            Label("FocusFlow", systemImage: "timer")
        }
        .menuBarExtraStyle(.window)
        .modelContainer(for: [Project.self, FocusSession.self, AppSettings.self])

        Window("FocusFlow", id: "stats") {
            CompanionWindowView()
        }
        .defaultSize(width: 700, height: 500)
        .modelContainer(for: [Project.self, FocusSession.self, AppSettings.self])
    }
}
