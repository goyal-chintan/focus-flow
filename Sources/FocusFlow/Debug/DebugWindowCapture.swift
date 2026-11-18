#if DEBUG
import AppKit
import SwiftUI

/// Invisible view placed on the menu bar label. When FOCUSFLOW_DEBUG_CAPTURE_DIR is set,
/// it opens the companion window ("stats") and snapshots every companion tab from inside the app,
/// then opens the Settings scene and snapshots every Settings tab.
/// Set FOCUSFLOW_DEBUG_CAPTURE_SETTINGS_ONLY=1 to skip the companion window.
struct DebugWindowCaptureBridge: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .task {
                guard let dir = ProcessInfo.processInfo.environment["FOCUSFLOW_DEBUG_CAPTURE_DIR"],
                      !dir.isEmpty else { return }
                DebugWindowCapture.start(directory: dir, open: {
                    WindowPolicyManager.shared.prepareToOpen()
                    openWindow(id: "stats")
                }, openSettings: {
                    WindowPolicyManager.shared.prepareToOpen()
                    openSettings()
                })
            }
    }
}

/// DEBUG-only window capture. Snapshots are written as PNG into the given directory;
/// progress is logged to /tmp/focusflow_debug.log.
@MainActor
enum DebugWindowCapture {
    private static var started = false
    private static let logPath = "/tmp/focusflow_debug.log"
    private static let targetContentSize = NSSize(width: 960, height: 640)

    static func start(
        directory: String,
        open: @escaping @MainActor () -> Void,
        openSettings: @escaping @MainActor () -> Void
    ) {
        guard !started else { return }
        started = true
        Task { @MainActor in
            let dirURL = URL(fileURLWithPath: directory, isDirectory: true)
            try? FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
            log("capture: start dir=\(directory)")
            if ProcessInfo.processInfo.environment["FOCUSFLOW_DEBUG_CAPTURE_SETTINGS_ONLY"] != "1" {
                await run(directory: dirURL, open: open)
            }
            await runSettings(directory: dirURL, openSettings: openSettings)
            log("capture complete")
        }
    }

    private static func runSettings(directory dirURL: URL, openSettings: @MainActor () -> Void) async {
        openSettings()
        var waited = 0.0
        var window: NSWindow?
        while waited < 10 {
            window = NSApp.windows.first {
                $0.isVisible && $0.identifier?.rawValue.localizedCaseInsensitiveContains("settings") == true
            }
            if window != nil { break }
            await pause(0.2)
            waited += 0.2
        }
        guard let window else {
            log("capture: FAILED - no Settings window appeared within 10s")
            for w in NSApp.windows {
                log("capture: diag window title=\"\(w.title)\" id=\(w.identifier?.rawValue ?? "nil") visible=\(w.isVisible)")
            }
            return
        }
        await pause(1.5)
        for (index, tab) in SettingsTab.allCases.enumerated() {
            AppIsolation.defaults.set(tab.rawValue, forKey: SettingsTab.storageKey)
            await pause(1.2)
            log("capture: settings tab=\(tab.rawValue) frame=\(window.frame)")
            snapshot(window, name: String(format: "settings_%02d_%@.png", index + 1, tab.rawValue), directory: dirURL)
        }
    }

    private static func run(directory dirURL: URL, open: @MainActor () -> Void) async {

        open()
        guard let window = await waitForWindow(timeout: 10) else {
            log("capture: FAILED - no companion window (id stats) appeared within 10s")
            for w in NSApp.windows {
                log("capture: diag window title=\"\(w.title)\" id=\(w.identifier?.rawValue ?? "nil") visible=\(w.isVisible) level=\(w.level.rawValue) class=\(type(of: w)) content=\(w.contentView != nil)")
            }
            return
        }
        await pause(2.0)
        log("capture: window appeared frame=\(window.frame) contentSize=\(window.contentLayoutRect.size)")

        // 00: default size, before any resizing.
        snapshot(window, name: "00_default_size.png", directory: dirURL)

        window.setContentSize(targetContentSize)
        await pause(1.2)
        log("capture: resized to \(targetContentSize.width)x\(targetContentSize.height) frame=\(window.frame)")

        for (index, tab) in CompanionTab.allCases.enumerated() {
            let nn = String(format: "%02d", index + 1)
            let tabName = tab.rawValue.lowercased()

            // Same mechanism openStatsWindow(requestedTab:) uses: CompanionWindowView observes this key.
            AppIsolation.defaults.set(tab.rawValue, forKey: "companionRequestedTab")
            await pause(1.2)
            log("capture: tab=\(tab.rawValue) frame=\(window.frame)")
            snapshot(window, name: "\(nn)_\(tabName).png", directory: dirURL)

            if tab == .insights {
                await scrollThrough(window, prefix: "\(nn)_\(tabName)", label: tab.rawValue, directory: dirURL)
            }
        }
    }

    /// Snapshots the floating coach panel (its window title is "Focus Coach").
    static func snapshotCoachPanel(directory: String, name: String) {
        let dirURL = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        guard let panel = NSApp.windows.first(where: { $0.title == "Focus Coach" && $0.isVisible }) else {
            log("capture: no visible coach panel for \(name)")
            return
        }
        snapshot(panel, name: name, directory: dirURL)
    }

    private static func findWindow() -> NSWindow? {
        // Title follows the selected tab (navigationTitle), so match the scene id "stats".
        NSApp.windows.first { $0.identifier?.rawValue.hasPrefix("stats") == true && $0.contentView != nil }
    }

    private static func waitForWindow(timeout: Double) async -> NSWindow? {
        var waited = 0.0
        while waited < timeout {
            if let window = findWindow() { return window }
            await pause(0.2)
            waited += 0.2
        }
        return nil
    }

    private static func snapshot(_ window: NSWindow, name: String, directory: URL) {
        guard let content = window.contentView else {
            log("capture: no contentView for \(name)")
            return
        }
        let view = content.superview ?? content
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            log("capture: no bitmap rep for \(name)")
            return
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            log("capture: PNG encode failed for \(name)")
            return
        }
        do {
            try data.write(to: directory.appendingPathComponent(name))
            log("capture: wrote \(name) \(rep.pixelsWide)x\(rep.pixelsHigh) bytes=\(data.count) frame=\(window.frame)")
        } catch {
            log("capture: write failed for \(name): \(error)")
        }
    }

    private static func findDetailScrollView(in window: NSWindow) -> NSScrollView? {
        guard let root = window.contentView?.superview ?? window.contentView else { return nil }
        var found: [NSScrollView] = []
        func walk(_ view: NSView) {
            if let scrollView = view as? NSScrollView { found.append(scrollView) }
            view.subviews.forEach(walk)
        }
        walk(root)
        return found.max { lhs, rhs in
            (lhs.documentView?.frame.height ?? 0) < (rhs.documentView?.frame.height ?? 0)
        }
    }

    private static func scrollThrough(_ window: NSWindow, prefix: String, label: String, directory: URL) async {
        guard let scrollView = findDetailScrollView(in: window),
              let docView = scrollView.documentView else {
            log("capture: \(label) no scroll view found")
            return
        }
        let clip = scrollView.contentView
        let visibleHeight = clip.bounds.height
        let maxY = max(0, docView.frame.height - visibleHeight)
        log("capture: \(label) scroll doc=\(docView.frame.height) visible=\(visibleHeight) maxY=\(maxY) flipped=\(docView.isFlipped)")

        var step = 1
        var lastY = clip.bounds.origin.y
        while maxY > 0, step <= 40 {
            let targetY = min(lastY + visibleHeight, maxY)
            clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: targetY))
            scrollView.reflectScrolledClipView(clip)
            await pause(0.5)
            let actualY = clip.bounds.origin.y
            log("capture: \(label) scroll step \(step) requested=\(targetY) actual=\(actualY)")
            snapshot(window, name: "\(prefix)_scroll_\(step).png", directory: directory)
            if actualY <= lastY + 0.5 { break }
            lastY = actualY
            if actualY >= maxY - 0.5 { break }
            step += 1
        }
        log("capture: \(label) scroll finished at bottom after \(step) steps")
    }

    private static func pause(_ seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    private static func log(_ message: String) {
        let entry = "[\(Date())] \(message)\n"
        guard let data = entry.data(using: .utf8) else { return }
        if let handle = FileHandle(forWritingAtPath: logPath) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        } else {
            FileManager.default.createFile(atPath: logPath, contents: data)
        }
    }
}
#endif
