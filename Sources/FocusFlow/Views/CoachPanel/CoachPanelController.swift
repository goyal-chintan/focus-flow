import AppKit
import SwiftUI
import SwiftData

/// A floating, non-activating panel. It appears without taking focus, so typing in the current
/// app continues. Once the user clicks it, it becomes key (still without activating FocusFlow)
/// so ⏎ runs the primary action and Esc means "Not now".
final class CoachFloatingPanel: NSPanel {
    var onReturn: (() -> Void)?
    var onEscape: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }

    override func keyDown(with event: NSEvent) {
        switch Int(event.keyCode) {
        case 36, 76: onReturn?()   // Return, keypad Enter
        case 53: onEscape?()       // Esc
        default: super.keyDown(with: event)
        }
    }
}

/// Hosts `CoachPanelView` in a non-activating, floating NSPanel at the top right of the
/// screen, under the menu bar icon (companion redesign §5). It slides and fades in (fade only
/// with Reduce Motion), never stacks (one panel, content replaced) and never activates the app.
@MainActor
final class CoachPanelController: CoachPanelHosting {
    private let timerVM: TimerViewModel
    private let modelContainer: ModelContainer
    private var panel: CoachFloatingPanel?
    private var glassView: NSGlassEffectView?
    private var contentSize = CGSize(width: CoachPanelView.width, height: 120)
    private var isShown = false

    private static let margin: CGFloat = 8
    private static let slideDistance: CGFloat = 14

    init(timerVM: TimerViewModel, modelContainer: ModelContainer) {
        self.timerVM = timerVM
        self.modelContainer = modelContainer
    }

    // MARK: CoachPanelHosting

    func showPanel(_ presentation: CoachPanelPresentation) {
        let panel = ensurePanel()
        let target = frame(for: contentSize)
        if isShown, panel.isVisible {
            // Replace content in place; never stack a second panel.
            panel.setFrame(target, display: true)
            return
        }
        isShown = true
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        var start = target
        if !reduceMotion { start.origin.y += Self.slideDistance }
        panel.setFrame(start, display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0.2 : 0.32
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
            panel.animator().alphaValue = 1
            if !reduceMotion { panel.animator().setFrame(target, display: true) }
        }
    }

    func hidePanel() {
        guard let panel, isShown else { return }
        isShown = false
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        var end = panel.frame
        if !reduceMotion { end.origin.y += Self.slideDistance / 2 }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            panel.animator().alphaValue = 0
            if !reduceMotion { panel.animator().setFrame(end, display: true) }
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self, !self.isShown else { return }
                if self.panel?.isKeyWindow == true { self.panel?.resignKey() }
                self.panel?.orderOut(nil)
            }
        })
    }

    // MARK: Window

    private func ensurePanel() -> CoachFloatingPanel {
        if let panel { return panel }
        let panel = CoachFloatingPanel(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        // Key only after a click (orderFrontRegardless never makes it key), never main.
        panel.becomesKeyOnlyIfNeeded = false
        panel.onReturn = { [weak self] in self?.timerVM.performCoachPanelPrimary() }
        panel.onEscape = { [weak self] in self?.timerVM.performCoachPanelEscape() }
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = false
        panel.animationBehavior = .none
        panel.title = "Focus Coach"

        let root = CoachPanelHostView(chrome: .hosted) { [weak self] size in
            self?.contentSizeChanged(size)
        }
        .environment(timerVM)
        .modelContainer(modelContainer)
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []

        let glass = NSGlassEffectView()
        glass.cornerRadius = 18
        glass.contentView = hosting
        panel.contentView = glass
        glassView = glass
        self.panel = panel
        return panel
    }

    private func contentSizeChanged(_ size: CGSize) {
        guard size.height > 0, abs(size.height - contentSize.height) > 0.5 else { return }
        contentSize = CGSize(width: CoachPanelView.width, height: ceil(size.height))
        guard let panel, isShown else { return }
        panel.setFrame(frame(for: contentSize), display: true)
    }

    /// Top-right, under the FocusFlow menu bar icon when it can be found.
    private func frame(for size: CGSize) -> NSRect {
        let statusFrame = NSApplication.shared.windows
            .first { String(describing: type(of: $0)).contains("StatusBarWindow") && $0.isVisible }?
            .frame
        let screen = NSScreen.screens.first { screen in
            statusFrame.map { screen.frame.contains(NSPoint(x: $0.midX, y: $0.midY)) } ?? false
        } ?? NSScreen.main ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        var x = visible.maxX - size.width - Self.margin
        if let statusFrame {
            x = statusFrame.maxX + 12 - size.width
        }
        x = min(max(x, visible.minX + Self.margin), visible.maxX - size.width - Self.margin)
        let y = visible.maxY - size.height - Self.margin
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }
}
