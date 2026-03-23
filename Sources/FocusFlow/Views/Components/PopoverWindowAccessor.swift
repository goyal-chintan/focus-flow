import SwiftUI
import AppKit

/// Captures the hosting NSWindow reference from a MenuBarExtra popover.
///
/// Embedded as an invisible background view so TimerViewModel can close
/// the popover directly via `window.close()` instead of relying on the
/// fragile responder-chain `NSApp.sendAction(NSPopover.performClose)`.
struct PopoverWindowAccessor: NSViewRepresentable {
    let onWindowFound: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.setAccessibilityElement(false)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                onWindowFound(window)
            }
        }
    }
}
