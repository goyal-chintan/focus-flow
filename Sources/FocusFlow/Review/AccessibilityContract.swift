import Foundation

struct AccessibilityControlRequirement: Hashable {
    let id: String
    let label: String
    let sourceFile: String
}

enum AccessibilityContract {
    /// Critical-path controls that must keep explicit VoiceOver labels.
    static let criticalControls: [AccessibilityControlRequirement] = [
        AccessibilityControlRequirement(
            id: "popover.header.openStats",
            label: "Open statistics",
            sourceFile: "Sources/FocusFlow/Views/MenuBar/MenuBarPopoverView.swift"
        ),
        AccessibilityControlRequirement(
            id: "popover.header.close",
            label: "Close",
            sourceFile: "Sources/FocusFlow/Views/MenuBar/MenuBarPopoverView.swift"
        ),
        AccessibilityControlRequirement(
            id: "sessionComplete.primary.takeBreak",
            label: "Take a break",
            sourceFile: "Sources/FocusFlow/Views/SessionCompleteWindow.swift"
        ),
        AccessibilityControlRequirement(
            id: "sessionComplete.secondary.skipBreak",
            label: "Skip break and continue focus",
            sourceFile: "Sources/FocusFlow/Views/SessionCompleteWindow.swift"
        ),
        AccessibilityControlRequirement(
            id: "coachWindow.skipCheck",
            label: "Skip this coach check",
            sourceFile: "Sources/FocusFlow/Views/CoachInterventionWindowView.swift"
        ),
        AccessibilityControlRequirement(
            id: "coachWindow.skipWithoutReason",
            label: "Skip this check without giving a reason",
            sourceFile: "Sources/FocusFlow/Views/CoachInterventionWindowView.swift"
        )
    ]
}
