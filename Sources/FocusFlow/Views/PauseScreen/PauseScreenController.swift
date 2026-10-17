import AppKit
import SwiftUI
import SwiftData

/// Full-screen, borderless, non-activating panel. It may become key while shown (so Esc and ⏎
/// work) without activating FocusFlow or bringing its other windows forward.
final class PauseScreenPanel: NSPanel {
    var onEscape: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }

    override func keyDown(with event: NSEvent) {
        if Int(event.keyCode) == 53 {
            onEscape?()
        } else {
            super.keyDown(with: event)
        }
    }
}

/// Hosts `PauseScreenView` above other apps on the active display (the one under the pointer).
/// It dims with a behind-window material; it is not a lock. Fades and scales in over 0.35 s
/// (fade only with Reduce Motion) and never calls `NSApp.activate`.
@MainActor
final class PauseScreenController: CoachPauseScreenHosting {
    private let timerVM: TimerViewModel
    private let modelContainer: ModelContainer
    private var panel: PauseScreenPanel?
    private var isShown = false

    init(timerVM: TimerViewModel, modelContainer: ModelContainer) {
        self.timerVM = timerVM
        self.modelContainer = modelContainer
    }

    func showPauseScreen(_ presentation: CoachPauseScreenPresentation) {
        let screen = Self.activeScreen()
        let panel = ensurePanel()
        panel.setFrame(screen?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900), display: false)
        isShown = true
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        // Key without activating the app (non-activating panel), so Esc and ⏎ reach it.
        panel.makeKey()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.35
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
            panel.animator().alphaValue = 1
        }
    }

    func hidePauseScreen() {
        guard let panel, isShown else { return }
        isShown = false
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.22
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self, !self.isShown else { return }
                if self.panel?.isKeyWindow == true { self.panel?.resignKey() }
                self.panel?.orderOut(nil)
            }
        })
    }

    private static func activeScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func ensurePanel() -> PauseScreenPanel {
        if let panel { return panel }
        let panel = PauseScreenPanel(
            contentRect: NSRect(x: 0, y: 0, width: 1440, height: 900),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        // Above normal and floating windows, including a full-screen video in another app.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.animationBehavior = .none
        panel.title = "Focus Coach Pause"
        panel.onEscape = { [weak self] in self?.timerVM.performPauseScreenExit(.escape) }

        let material = NSVisualEffectView()
        material.material = .fullScreenUI
        material.blendingMode = .behindWindow
        material.state = .active

        let hosting = NSHostingView(
            rootView: PauseScreenHostView()
                .environment(timerVM)
                .modelContainer(modelContainer)
        )
        hosting.translatesAutoresizingMaskIntoConstraints = false
        material.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: material.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: material.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: material.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: material.bottomAnchor),
        ])
        panel.contentView = material
        self.panel = panel
        return panel
    }
}
