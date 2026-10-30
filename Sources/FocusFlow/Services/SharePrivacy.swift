import CoreGraphics
import Foundation

/// "Hide while sharing my screen" (2026-10-30): while your screen is being shared or recorded,
/// FocusFlow shows nothing that says what it is or what you work on: a plain dot in the menu bar,
/// no notch, no panels, no notifications, and the block-end window waits until the share ends.
/// Being in a meeting without sharing changes nothing.
///
/// Why FocusFlow hides itself instead of asking macOS to: since macOS 15, ScreenCaptureKit (Zoom,
/// browsers) still captures windows marked `sharingType = .none`.
enum SharePrivacy {
    struct Signals: Equatable {
        /// "Private now" from the popover: on until you turn it off.
        var manual = false
        /// Something is capturing the screen (`ScreenCapture.isActive`).
        var screenShared = false
    }

    /// After a share ends, stay hidden this long, so a blip in the signal never flashes FocusFlow.
    static let holdSeconds: TimeInterval = 5

    static func isPrivate(_ signals: Signals, lastSharedAt: Date?, now: Date) -> Bool {
        if signals.manual || signals.screenShared { return true }
        guard let lastSharedAt else { return false }
        return now.timeIntervalSince(lastSharedAt) < holdSeconds
    }
}

/// Is the screen being captured right now (a share in Zoom, Meet, Teams…, or a recording)?
///
/// macOS has no public API for this. `CGSIsScreenWatcherPresent` is a private CoreGraphics call
/// (CGSInternal) that is true while any process captures the screen. Measured on macOS 26 with a
/// Zoom share on 2026-10-30: false in the meeting, true the second the share started, false the
/// second it stopped. It is looked up at run time, so a macOS that drops it makes this fall back
/// to Zoom's sharing frame (a `CptHost` window at the top layer, present only while sharing).
enum ScreenCapture {
    private typealias BoolFunction = @convention(c) () -> Bool

    private static let watcherPresent: BoolFunction? = {
        guard let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY),
              let symbol = dlsym(handle, "CGSIsScreenWatcherPresent") else { return nil }
        return unsafeBitCast(symbol, to: BoolFunction.self)
    }()

    static var isActive: Bool {
        if let watcherPresent { return watcherPresent() }
        return zoomSharingFrameOnScreen()
    }

    /// Owner names are readable without Screen Recording permission; window titles are not.
    private static func zoomSharingFrameOnScreen() -> Bool {
        let windows = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) ?? []
        return windows.contains { window in
            (window[kCGWindowOwnerName as String] as? String) == "CptHost"
                && (window[kCGWindowLayer as String] as? Int ?? 0) > 1_000_000_000
        }
    }
}
