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

/// Reports whether the hosting window is on screen. The MenuBarExtra popover's window is only
/// ordered out when it closes, so its SwiftUI tree keeps updating while hidden; the popover uses
/// this to pause its animations (`motionPaused`) until it is shown again.
struct WindowVisibilityReader: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> VisibilityView {
        let view = VisibilityView()
        view.onChange = onChange
        view.setAccessibilityElement(false)
        return view
    }

    func updateNSView(_ nsView: VisibilityView, context: Context) {
        nsView.onChange = onChange
    }

    final class VisibilityView: NSView {
        var onChange: ((Bool) -> Void)?
        private var lastReported: Bool?

        // Selector observers are removed by NotificationCenter when the view goes away.
        override func viewWillMove(toWindow newWindow: NSWindow?) {
            super.viewWillMove(toWindow: newWindow)
            NotificationCenter.default.removeObserver(self, name: NSWindow.didChangeOcclusionStateNotification, object: window)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window {
                NotificationCenter.default.addObserver(
                    self, selector: #selector(occlusionChanged),
                    name: NSWindow.didChangeOcclusionStateNotification, object: window
                )
            }
            reportCurrent()
        }

        @objc private func occlusionChanged(_ note: Notification) { reportCurrent() }

        private func reportCurrent() {
            guard let window else { report(false); return }
            report(window.isVisible && window.occlusionState.contains(.visible))
        }

        private func report(_ visible: Bool) {
            guard visible != lastReported else { return }
            lastReported = visible
            // Never change SwiftUI state inside its own update pass.
            DispatchQueue.main.async { [onChange] in onChange?(visible) }
        }
    }
}
