import SwiftUI

/// The ambient drift counter in the menu bar label: a small orange "YouTube 23m" or
/// "Drift 23m" while drifting in a focus window (rescue loop design §3.1). Compact by design:
/// names are truncated by `CoachDriftCounter`.
struct DriftMenuBarCounter: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(Color.orange)
            .lineLimit(1)
            .fixedSize()
            .contentTransition(.numericText())
            .accessibilityLabel("Drift time in this focus window: \(text)")
    }
}
