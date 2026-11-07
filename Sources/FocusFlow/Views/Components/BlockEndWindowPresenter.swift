import AppKit

/// Brings the block-end window to you (7 Nov 2026: it opened behind other apps, on another screen
/// or Space, and too small to use). It moves to the screen under the pointer and the current Space,
/// opens at a usable size (your last size, once you resize it) and floats in front. The timer, not
/// a click, opens it, and macOS ignores activation requests from a background app, so ordering it
/// front ourselves is the only way it reliably shows.
@MainActor
enum BlockEndWindowPresenter {
    static let size = NSSize(width: 560, height: 760)
    /// Break end and wake recovery are short screens.
    static let compactSize = NSSize(width: 480, height: 560)
    static let minSize = NSSize(width: 480, height: 520)
    static let sizeKey = "focusflow.blockEndWindowSize"
    private static var resizeObserver: NSObjectProtocol?

    /// The size to open at: your last one if usable, else 560 × 760, fitted to the screen.
    static func frame(saved: NSSize?, visible: NSRect, compact: Bool = false) -> NSRect {
        let wanted = compact ? compactSize : (saved.flatMap { $0.width >= minSize.width && $0.height >= minSize.height ? $0 : nil } ?? size)
        let w = min(wanted.width, visible.width - 40), h = min(wanted.height, visible.height - 40)
        return NSRect(x: visible.midX - w / 2, y: visible.midY - h / 2, width: w, height: h)
    }

    static func present(_ window: NSWindow, compact: Bool = false) {
        window.collectionBehavior.insert([.moveToActiveSpace, .fullScreenAuxiliary])
        window.level = .floating
        window.styleMask.insert(.resizable)
        window.minSize = minSize

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let saved = UserDefaults.standard.string(forKey: sizeKey).map(NSSizeFromString)
        window.setFrame(frame(saved: saved, visible: screen?.visibleFrame ?? window.frame, compact: compact), display: true)

        NSApp.activate()
        window.orderFrontRegardless()
        window.makeKey()

        if let resizeObserver { NotificationCenter.default.removeObserver(resizeObserver) }
        resizeObserver = NotificationCenter.default.addObserver(forName: NSWindow.didEndLiveResizeNotification, object: window, queue: .main) { note in
            guard let w = note.object as? NSWindow, !compact else { return }
            UserDefaults.standard.set(NSStringFromSize(w.frame.size), forKey: sizeKey)
        }
    }
}
