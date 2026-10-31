import AppKit
import SwiftUI
import SwiftData

/// A borderless window that can take typing.
final class OnboardingWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Shows the welcome tour full screen on the active display (onboarding v2 §3.5), over a
/// behind-window blur, like the rescue pause screen. Below the menu bar, so the card can fly up
/// to where FocusFlow lives. Each opening starts a fresh tour.
@MainActor
final class OnboardingController {
    private let timerVM: TimerViewModel
    private let modelContainer: ModelContainer
    private var window: OnboardingWindow?

    init(timerVM: TimerViewModel, modelContainer: ModelContainer) {
        self.timerVM = timerVM
        self.modelContainer = modelContainer
    }

    var isShown: Bool { window?.isVisible == true }

    func show() {
        let screen = Self.activeScreen()
        let frame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let window = self.window ?? makeWindow()
        self.window = window
        window.contentView = content(frame: frame)
        window.setFrame(frame, display: false)
        window.alphaValue = 0
        // You type into the tour, so FocusFlow takes focus while it is open.
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0.2 : 0.45
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
            window.animator().alphaValue = 1
        }
    }

    func hide() {
        guard let window, window.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            window.animator().alphaValue = 0
        }, completionHandler: {
            Task { @MainActor in
                window.orderOut(nil)
                window.contentView = nil
            }
        })
    }

    private static func activeScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func makeWindow() -> OnboardingWindow {
        let window = OnboardingWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1440, height: 900),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        window.title = "Welcome to FocusFlow"
        window.level = .floating
        window.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.animationBehavior = .none
        return window
    }

    private func content(frame: NSRect) -> NSView {
        let material = NSVisualEffectView(frame: NSRect(origin: .zero, size: frame.size))
        material.material = .fullScreenUI
        material.blendingMode = .behindWindow
        material.state = .active

        let hosting = NSHostingView(
            rootView: OnboardingView(onClose: { [weak self] in self?.hide() })
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
        return material
    }
}
