import SwiftUI

// MARK: - Spacing

enum FFSpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
}

// MARK: - Radius

enum FFRadius {
    static let control: CGFloat = 12
    static let card: CGFloat = 18
    static let hero: CGFloat = 28
}

// MARK: - Sizing

enum FFSize {
    static let controlMin: CGFloat = 44
    static let iconFrame: CGFloat = 48
    static let heroIcon: CGFloat = 72
}

// MARK: - Typography (sized up for readability)

enum FFType {
    static let heroTimer = Font.system(size: 56, weight: .ultraLight, design: .rounded)
    static let heroLabel = Font.system(.body, design: .rounded).weight(.semibold)
    static let title = Font.system(.title3, design: .rounded).weight(.semibold)
    static let titleLarge = Font.system(.title2, design: .rounded).weight(.semibold)
    static let cardValue = Font.system(.title2, design: .rounded).weight(.semibold)
    static let body = Font.system(.body, design: .rounded).weight(.medium)
    static let callout = Font.system(.body, design: .rounded).weight(.semibold)
    static let meta = Font.system(.body, design: .rounded).weight(.medium)
    static let micro = Font.system(.subheadline, design: .rounded).weight(.medium)
}

// MARK: - Semantic Colors

enum FFColor {
    static let focus = Color.blue
    static let success = Color.green
    static let warning = Color.orange
    static let danger = Color.red
    static let deepFocus = Color.indigo

    // Adaptive panel colors (used by PremiumSurface and ContentPanel)
    static let panelFill = Color.primary.opacity(0.04)
    static let panelBorder = Color.primary.opacity(0.08)
    static let panelHighlight = Color.white.opacity(0.08)
    static let insetFill = Color.white.opacity(0.05)
    static let rowFill = Color.primary.opacity(0.03)
    static let fieldFill = Color.primary.opacity(0.05)
    static let fieldBorder = Color.primary.opacity(0.10)
}

// MARK: - Motion

enum FFMotion {
    // Original spring tokens (used by existing views)
    // Winner: Motion A - spring-forward but stable (less snap/jitter on press/release).
    static let popover = Animation.spring(response: 0.34, dampingFraction: 0.84)
    static let section = Animation.spring(response: 0.30, dampingFraction: 0.82)
    static let control = Animation.spring(response: 0.22, dampingFraction: 0.80)
    static let breathing = Animation.easeInOut(duration: 1.8).repeatForever(autoreverses: true)

    // Aliases for new code
    static let glass: Animation = .bouncy
    static let content = section
}

// MARK: - View Extensions

extension View {
    func ffCardChrome(cornerRadius: CGFloat) -> some View {
        overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18))
        }
        .shadow(color: .black.opacity(0.08), radius: 22, y: 10)
    }
}

// MARK: - Content Panel (opaque container for content)

struct ContentPanel<Content: View>: View {
    let cornerRadius: CGFloat
    let padding: CGFloat
    let content: Content

    init(
        cornerRadius: CGFloat = FFRadius.card,
        padding: CGFloat = FFSpacing.md,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: FFSpacing.sm) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(padding)
        .background(FFColor.panelFill, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(FFColor.panelBorder)
        }
    }
}

// MARK: - Centralized Helpers

func colorFromName(_ name: String) -> Color {
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

func moodColor(_ mood: FocusMood) -> Color {
    switch mood {
    case .distracted: FFColor.warning
    case .neutral: .secondary
    case .focused: FFColor.focus
    case .deepFocus: FFColor.deepFocus
    }
}
