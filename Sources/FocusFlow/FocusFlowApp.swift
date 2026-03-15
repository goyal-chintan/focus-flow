// Sources/FocusFlow/FocusFlowApp.swift
import SwiftUI

struct FocusFlowApp: App {
    var body: some Scene {
        MenuBarExtra {
            MenuBarPopoverView()
        } label: {
            Label("FocusFlow", systemImage: "timer")
        }
        .menuBarExtraStyle(.window)

        Window("FocusFlow", id: "stats") {
            CompanionWindowView()
        }
        .defaultSize(width: 700, height: 500)
    }
}
