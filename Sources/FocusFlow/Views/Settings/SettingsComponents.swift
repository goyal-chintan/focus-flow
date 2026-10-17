import SwiftUI
import SwiftData
import AppKit

// Shared building blocks for the Settings scene tabs.

/// One fixed size for every Settings tab, so switching tabs never resizes the window.
/// Tall content scrolls inside the tab's Form.
enum SettingsLayout {
    static let width: CGFloat = 660
    static let height: CGFloat = 620
    /// Leading icon tile used by list rows (apps, websites, profiles).
    static let iconSize: CGFloat = 22
    /// Shared minimum height for two-line list rows.
    static let listRowMinHeight: CGFloat = 34
}

// MARK: - Bindings

/// Builds `AppSettings` bindings that save on every change.
@MainActor
struct SettingsBinder {
    let settings: AppSettings
    let save: () -> Void

    func callAsFunction<Value>(
        _ keyPath: ReferenceWritableKeyPath<AppSettings, Value>,
        onSet: ((Value) -> Void)? = nil
    ) -> Binding<Value> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { newValue in
                settings[keyPath: keyPath] = newValue
                save()
                onSet?(newValue)
            }
        )
    }

    /// Binds a minute-of-day field (0–1439) to a `Date` for an hour/minute picker.
    func minuteOfDay(_ keyPath: ReferenceWritableKeyPath<AppSettings, Int>) -> Binding<Date> {
        Binding(
            get: { settingsDate(forMinuteOfDay: settings[keyPath: keyPath]) },
            set: { date in
                settings[keyPath: keyPath] = settingsMinuteOfDay(from: date)
                save()
            }
        )
    }
}

func settingsDate(forMinuteOfDay minute: Int, calendar: Calendar = .current) -> Date {
    let clamped = min(max(minute, 0), 24 * 60 - 1)
    return calendar.date(
        bySettingHour: clamped / 60,
        minute: clamped % 60,
        second: 0,
        of: Date()
    ) ?? Date()
}

func settingsMinuteOfDay(from date: Date, calendar: Calendar = .current) -> Int {
    let parts = calendar.dateComponents([.hour, .minute], from: date)
    return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
}

// MARK: - Rows

/// One form row: label on the left, value and stepper arrows right-aligned in a shared column.
struct SettingsStepperRow: View {
    let title: String
    let valueText: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step: Int = 1

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                Text(valueText)
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                Stepper(title, value: $value, in: range, step: step)
                    .labelsHidden()
                    .accessibilityValue(valueText)
            }
        }
    }
}

func settingsMinutesText(_ minutes: Int) -> String {
    "\(minutes) min"
}

/// "45m", "2h", "2h 15m".
func settingsGoalText(minutes: Int) -> String {
    let hours = minutes / 60
    let remainder = minutes % 60
    switch (hours, remainder) {
    case (0, _): return "\(remainder)m"
    case (_, 0): return "\(hours)h"
    default: return "\(hours)h \(remainder)m"
    }
}

/// Small trailing "More" menu used by list rows.
struct SettingsRowMenu<Content: View>: View {
    let accessibilityLabel: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        Menu {
            content()
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More")
        .accessibilityLabel(accessibilityLabel)
    }
}

/// Leading tile + name + secondary detail + trailing controls. Shared by Distractions,
/// Blocking profiles and the rule editor so every list row has the same rhythm.
struct SettingsListRow<Leading: View, Trailing: View>: View {
    let title: String
    let detail: String?
    @ViewBuilder let leading: () -> Leading
    @ViewBuilder let trailing: () -> Trailing

    init(
        title: String,
        detail: String? = nil,
        @ViewBuilder leading: @escaping () -> Leading,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.title = title
        self.detail = detail
        self.leading = leading
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 10) {
            leading()
                .frame(width: SettingsLayout.iconSize, height: SettingsLayout.iconSize)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .layoutPriority(1)

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                trailing()
            }
            .controlSize(.small)
        }
        .frame(minHeight: SettingsLayout.listRowMinHeight)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Icons

/// Real app icons looked up from bundle identifiers, cached per identifier.
@MainActor
enum SettingsAppIconCache {
    private static var icons: [String: NSImage] = [:]
    private static var misses: Set<String> = []

    static func icon(forBundleIdentifier bundleIdentifier: String) -> NSImage? {
        let key = bundleIdentifier.lowercased()
        if let cached = icons[key] { return cached }
        if misses.contains(key) { return nil }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            misses.insert(key)
            return nil
        }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        icons[key] = image
        return image
    }
}

/// The installed app's name, falling back to the shared display-name helpers.
func settingsAppDisplayName(forBundleIdentifier bundleIdentifier: String) -> String {
    if let resolved = AppDisplayNameResolver.displayName(forBundleIdentifier: bundleIdentifier) {
        return resolved
    }
    return AppUsageEntry.recommendationDisplayLabel(for: "app:\(bundleIdentifier)")
}

/// App icon for a bundle ID, or a neutral app tile when the app isn't installed.
struct SettingsAppIcon: View {
    let bundleIdentifier: String

    var body: some View {
        if let image = SettingsAppIconCache.icon(forBundleIdentifier: bundleIdentifier) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .accessibilityHidden(true)
        } else {
            SettingsSymbolTile(systemName: "app.dashed")
        }
    }
}

/// Neutral rounded tile with an SF Symbol (websites, missing apps).
struct SettingsSymbolTile: View {
    let systemName: String
    var tint: Color? = nil

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(tint ?? Color.secondary.opacity(0.16))
            .overlay {
                Image(systemName: systemName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.white))
            }
            .accessibilityHidden(true)
    }
}

/// Small capsule badge, e.g. "Default".
struct SettingsBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Capsule().fill(Color.secondary.opacity(0.14)))
    }
}

func settingsProjectColor(_ name: String) -> Color {
    switch name {
    case "blue": .blue
    case "indigo": .indigo
    case "purple": .purple
    case "pink": .pink
    case "red": .red
    case "orange": .orange
    case "yellow": .yellow
    case "green": .green
    case "teal": .teal
    case "mint": .mint
    default: .blue
    }
}

// MARK: - Tab shortcuts

/// Invisible ⌘1–⌘5 shortcuts that switch Settings tabs.
struct SettingsTabShortcuts: View {
    @Binding var selection: SettingsTab

    var body: some View {
        ZStack {
            ForEach(Array(SettingsTab.allCases.enumerated()), id: \.element) { index, tab in
                Button(tab.title) {
                    selection = tab
                }
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
