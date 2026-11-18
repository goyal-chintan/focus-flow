import SwiftUI
import SwiftData

// Write a test file to verify main.swift executes
try? "main.swift executing\n".write(toFile: "/tmp/focusflow_main.log", atomically: true, encoding: .utf8)

// Settings → General → Appearance, before any scene, panel or window is built.
AppAppearance.applyStored()

FocusFlowApp.main()
