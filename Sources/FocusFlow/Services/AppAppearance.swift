import AppKit

/// FocusFlow's own appearance: follow macOS, or always light, or always dark.
/// Settings → General → Appearance. Applied app-wide through `NSApp.appearance`, so the
/// popover, every window and panel, and `Color.adaptive` / `colorScheme` switch live.
/// The notch stays dark on purpose (`NotchView` forces it).
enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    /// Defaults key (through `AppIsolation.defaults`). Missing = system.
    static let storageKey = "appAppearance"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var icon: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }

    /// nil follows the system appearance.
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    static func stored(in defaults: UserDefaults = AppIsolation.defaults) -> AppAppearance {
        defaults.string(forKey: storageKey).flatMap(AppAppearance.init(rawValue:)) ?? .system
    }

    /// Applies the saved choice. Called once at launch, before any scene is built.
    @MainActor
    static func applyStored(defaults: UserDefaults = AppIsolation.defaults) {
        apply(stored(in: defaults))
    }

    /// Applies a choice to the running app (Settings saves it through `@AppStorage`).
    @MainActor
    static func apply(_ appearance: AppAppearance) {
        NSApplication.shared.appearance = appearance.nsAppearance
    }
}
