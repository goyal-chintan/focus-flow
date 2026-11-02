import SwiftUI

// The Settings scene's own tab bar and content container. They replace the native toolbar
// `TabView`, which swaps hosting controllers on a tab switch and so cannot animate.

// MARK: - Motion

/// Timing for the Settings tab switch, in one place so tests and views agree.
enum SettingsTabMotion {
    /// Distance the content slides while it cross-fades.
    static let slideDistance: CGFloat = 8
    /// Content cross-fade + slide.
    static let contentAnimation: Animation = .smooth(duration: 0.28)
    /// Content cross-fade when Reduce Motion is on (no slide).
    static let reducedContentAnimation: Animation = .easeInOut(duration: 0.2)
    /// Selection highlight sliding between tab bar items.
    static let highlightAnimation: Animation = .snappy(duration: 0.3)

    /// The page transition. Forward (to a tab further right): the new page comes in from the
    /// right and the old page leaves to the left. Backward is the mirror image. Reduce Motion
    /// fades only.
    static func transition(direction: SettingsTabSlideDirection, reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        let distance = slideDistance * direction.sign
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(x: distance)),
            removal: .opacity.combined(with: .offset(x: -distance))
        )
    }
}

/// Which way the content slides on a tab switch, from the tab order in the bar.
enum SettingsTabSlideDirection: Equatable {
    case forward
    case backward

    init(from old: SettingsTab, to new: SettingsTab) {
        self = new.order >= old.order ? .forward : .backward
    }

    /// +1 for forward (enter from the right), -1 for backward (enter from the left).
    var sign: CGFloat { self == .forward ? 1 : -1 }
}

// MARK: - Content container

/// One fixed-size container that holds the page for the shown tab. The page is keyed by the
/// tab (`.id(tab)`), so a switch removes the old page and inserts the new one with the
/// directional cross-fade. The window size never changes; tall pages scroll inside their Form.
struct SettingsTabContainer: View {
    let tab: SettingsTab
    let direction: SettingsTabSlideDirection
    let reduceMotion: Bool
    var initialScrollTarget: SettingsView.ScrollTarget? = nil

    var body: some View {
        ZStack {
            SettingsTabContent(tab: tab, initialScrollTarget: initialScrollTarget)
                .frame(width: SettingsLayout.width, height: SettingsLayout.height)
                .id(tab)
                .transition(SettingsTabMotion.transition(direction: direction, reduceMotion: reduceMotion))
        }
        .frame(width: SettingsLayout.width, height: SettingsLayout.height)
        .clipped()
        .animation(
            reduceMotion ? SettingsTabMotion.reducedContentAnimation : SettingsTabMotion.contentAnimation,
            value: tab
        )
    }
}

// MARK: - Tab bar

/// Five toolbar items (symbol above label), at least `itemWidth` wide. The selected item sits on a soft
/// accent-tinted rounded highlight that slides between items with `matchedGeometryEffect`.
struct SettingsTabBar: View {
    let selection: SettingsTab
    let onSelect: (SettingsTab) -> Void

    static let itemWidth: CGFloat = 78
    static let itemHeight: CGFloat = 44
    static let itemSpacing: CGFloat = 2
    static let cornerRadius: CGFloat = 10

    @Namespace private var highlightNamespace
    @State private var hoveredTab: SettingsTab?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Self.itemSpacing) {
            ForEach(SettingsTab.allCases) { tab in
                item(for: tab)
            }
        }
        .padding(.horizontal, 2)
        .animation(reduceMotion ? nil : SettingsTabMotion.highlightAnimation, value: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Settings sections")
    }

    private func item(for tab: SettingsTab) -> some View {
        let isSelected = tab == selection
        let isHovered = hoveredTab == tab && !isSelected
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)

        return Button {
            onSelect(tab)
        } label: {
            VStack(spacing: 3) {
                Image(systemName: tab.icon)
                    .font(.system(size: 16, weight: .regular))
                    .symbolVariant(isSelected ? .fill : .none)
                    .frame(height: 19)
                Text(tab.title)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
            // At least `itemWidth`; "Permissions & Sync" grows its item instead of truncating.
            .padding(.horizontal, 8)
            .frame(minWidth: Self.itemWidth, minHeight: Self.itemHeight, maxHeight: Self.itemHeight)
            .background {
                if isSelected {
                    shape
                        .fill(Color.accentColor.opacity(0.14))
                        .overlay(shape.strokeBorder(Color.accentColor.opacity(0.18), lineWidth: 0.5))
                        .matchedGeometryEffect(id: "settings.tabBar.highlight", in: highlightNamespace)
                } else if isHovered {
                    shape.fill(Color.primary.opacity(0.06))
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                hoveredTab = tab
            } else if hoveredTab == tab {
                hoveredTab = nil
            }
        }
        .help("\(tab.title) (⌘\(tab.order + 1))")
        .accessibilityLabel(tab.title)
        .accessibilityHint("Shows \(tab.title) settings")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityIdentifier("settings.tabBar.\(tab.rawValue)")
    }
}
