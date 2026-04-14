import AppKit

/// Manages `NSApp.activationPolicy` dynamically based on open windows.
///
/// FocusFlow ships with `LSUIElement=true` so it behaves as a menu-bar-only
/// app when idle. This manager promotes the app to `.regular` (shows Dock icon,
/// Cmd+Tab, Activity Monitor) whenever a real companion window is visible, and
/// reverts to `.accessory` once all such windows close.
///
/// The MenuBarExtra popup runs at `.statusBar` window level and is excluded from
/// the count, so merely opening the popover never triggers a Dock icon.
@MainActor
final class WindowPolicyManager {
    static let shared = WindowPolicyManager()

    private var observations: [NSObjectProtocol] = []
    private var revertTask: Task<Void, Never>?

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

        // Fires when a window is miniaturized — may need to revert.
        let miniaturized = center.addObserver(
            forName: NSWindow.didMiniaturizeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.scheduleRevertIfNeeded() }
        }

        // Fires when a window is restored from the Dock — re-promote.
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

        observations = [becameKey, becameMain, miniaturized, deminiaturized, willClose]
        update()
    }

    private func update() {
        revertTask?.cancel()
        revertTask = nil

        if hasVisibleNormalWindows {
            if NSApp.activationPolicy() != .regular {
                NSApp.setActivationPolicy(.regular)
                NSApp.activate()
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
            if !hasVisibleNormalWindows { revert() }
        }
    }

    private func revert() {
        if NSApp.activationPolicy() != .accessory {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    /// Returns true when at least one visible, non-miniaturized window is running
    /// at `.normal` level — which covers Stats, Settings, Coach, and Session Complete,
    /// but excludes the MenuBarExtra popup (`.statusBar` level) and system overlays.
    private var hasVisibleNormalWindows: Bool {
        NSApp.windows.contains {
            $0.isVisible && !$0.isMiniaturized && $0.level == .normal
        }
    }
}
