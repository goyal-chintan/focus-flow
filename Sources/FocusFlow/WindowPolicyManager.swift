import AppKit

/// Manages `NSApp.activationPolicy` dynamically based on open windows.
///
/// FocusFlow ships with `LSUIElement=true` so it behaves as a menu-bar-only
/// app when idle. This manager promotes the app to `.regular` (shows Dock icon,
/// Cmd+Tab, Activity Monitor, Force Quit) whenever a companion window is open
/// (even if minimized), and reverts to `.accessory` once all such windows close.
///
/// The MenuBarExtra popup runs at `.statusBar` window level and is excluded from
/// the count, so merely opening the popover never triggers a Dock icon.
@MainActor
final class WindowPolicyManager {
    static let shared = WindowPolicyManager()

    private var observations: [NSObjectProtocol] = []
    private var revertTask: Task<Void, Never>?
    private var activationTask: Task<Void, Never>?

    private init() {}

    func start() {
        let center = NotificationCenter.default

        // Fires when a window gains key status — covers new SwiftUI Window scenes appearing.
        let becameKey = center.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.update() }
        }

        // Fires when a window gains main status (e.g. clicking a non-key window).
        let becameMain = center.addObserver(
            forName: NSWindow.didBecomeMainNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.update() }
        }

        // Fires when a window is miniaturized. Keep .regular so the app stays in
        // Dock/Force Quit while a window is sitting in the Dock.
        let miniaturized = center.addObserver(
            forName: NSWindow.didMiniaturizeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.update() }
        }

        // Fires when a window is restored from the Dock — re-promote if needed.
        let deminiaturized = center.addObserver(
            forName: NSWindow.didDeminiaturizeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.update() }
        }

        let willClose = center.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Slight delay: the window is still in NSApp.windows at this point.
            Task { @MainActor in self?.scheduleRevertIfNeeded() }
        }

        // Belt-and-suspenders: re-evaluate whenever the app itself becomes active.
        // This catches the Settings scene (Cmd+,) which re-uses a cached NSWindow
        // and may not fire didBecomeKey if the window was previously closed.
        let appActive = center.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.update() }
        }

        observations = [becameKey, becameMain, miniaturized, deminiaturized, willClose, appActive]
        update()
    }

    /// Call this **before** dismissing the MenuBarExtra popover to open a companion window.
    /// Promoting the policy while FocusFlow is still the active process (inside a user-event
    /// handler) gives macOS Tahoe the context it needs to accept the activation — calling
    /// `NSApp.activate()` asynchronously after the popover closes is a no-op on Tahoe.
    func prepareToOpen() {
        activationTask?.cancel()
        activationTask = nil
        revertTask?.cancel()
        revertTask = nil
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate()
    }

    private func update() {
        revertTask?.cancel()
        revertTask = nil
        activationTask?.cancel()
        activationTask = nil

        if hasCompanionWindows {
            if NSApp.activationPolicy() != .regular {
                NSApp.setActivationPolicy(.regular)
                // Reactive fallback for windows that open without a prepareToOpen() call
                // (e.g. Settings via Cmd+,). setActivationPolicy briefly deactivates the app
                // on Tahoe, so we defer makeKeyAndOrderFront until the policy change settles.
                activationTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(50))
                    guard !Task.isCancelled else { return }
                    NSApp.windows.first(where: { $0.isVisible && !$0.isMiniaturized && $0.level == .normal })?
                        .makeKeyAndOrderFront(nil)
                }
            }
        } else {
            revert()
        }
    }

    private func scheduleRevertIfNeeded() {
        revertTask?.cancel()
        revertTask = Task { @MainActor in
            // 150 ms debounce: gives SwiftUI time to open a replacement window
            // during transitions (e.g., closing one tab and opening another).
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            if !hasCompanionWindows { revert() }
        }
    }

    private func revert() {
        activationTask?.cancel()
        activationTask = nil
        if NSApp.activationPolicy() != .accessory {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    /// Returns true when at least one companion window exists — fully on screen OR
    /// miniaturized in the Dock. Excludes the MenuBarExtra popup (`.statusBar` level)
    /// and other system overlays above that level.
    private var hasCompanionWindows: Bool {
        NSApp.windows.contains {
            ($0.isVisible || $0.isMiniaturized) && $0.level == .normal
        }
    }
}
