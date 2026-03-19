import SwiftUI

// MARK: - Obsidian Lens Design System
// Based on the "Liquid Refraction" DESIGN.md specifications.
// Near-black foundation, electric blue/amber spectral highlights,
// editorial SF Pro typography, no 1px borders.

enum LiquidDesignTokens {

    // MARK: - Surface Palette (Obsidian Layering)
    enum Surface {
        static let background = Color(hex: 0x131315)
        static let containerLow = Color(hex: 0x1C1C1E)
        static let container = Color(hex: 0x252526)
        static let containerHigh = Color(hex: 0x2C2C2E)
        static let containerHighest = Color(hex: 0x353534)
        static let onSurface = Color(hex: 0xE5E2E1)
        static let onSurfaceMuted = Color(hex: 0xE5E2E1).opacity(0.55)
    }

    // MARK: - Spectral Colors (Light Sources)
    enum Spectral {
        static let electricBlue = Color(hex: 0xAAC7FF)
        static let primaryContainer = Color(hex: 0x3E90FF)
        static let amber = Color(hex: 0xFFC07A)
        static let amberDark = Color(hex: 0xD4940A)
        static let mint = Color(hex: 0x5ED4A0)
        static let mintDark = Color(hex: 0x34C77B)
        static let salmon = Color(hex: 0xFFB4A8)
        static let destructive = Color(hex: 0xFF6B6B)
    }

    // MARK: - Spacing (Editorial Breathing Room)
    enum Spacing {
        static let xSmall: CGFloat = 4
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
        static let xLarge: CGFloat = 20
        static let xxLarge: CGFloat = 24
        static let section: CGFloat = 32
    }

    // MARK: - Corner Radius (Continuous Squircle)
    enum CornerRadius {
        static let control: CGFloat = 12
        static let picker: CGFloat = 14
        static let card: CGFloat = 16
        static let panel: CGFloat = 20
        static let cta: CGFloat = 18
        static let ring: CGFloat = 9999
    }

    // MARK: - Editorial Typography
    enum Typography {
        // Display — ultra-light, tight tracking, for hero time displays
        static let displayLarge = Font.system(size: 42, weight: .ultraLight, design: .rounded)
        static let displayMedium = Font.system(size: 28, weight: .light, design: .rounded)

        // Headlines — semibold, section anchors
        static let headlineLarge = Font.system(size: 20, weight: .semibold)
        static let headlineMedium = Font.system(size: 16, weight: .medium)

        // Body — regular weight workhorse
        static let bodyMedium = Font.system(size: 14, weight: .regular)
        static let bodySmall = Font.system(size: 13, weight: .regular)

        // Labels — uppercase micro-copy, tracked
        static let labelLarge = Font.system(size: 12, weight: .semibold)
        static let labelMedium = Font.system(size: 11, weight: .medium)
        static let labelSmall = Font.system(size: 10, weight: .medium)

        // Control — button/CTA text
        static let controlLabel = Font.system(size: 15, weight: .semibold)
        static let controlSmall = Font.system(size: 13, weight: .medium)
    }

    // MARK: - Padding
    enum Padding {
        static let popoverHorizontal: CGFloat = 24
        static let controlVertical: CGFloat = 12
        static let cardPadding: CGFloat = 16
    }

    // MARK: - Ghost Border (Never opaque)
    static func ghostBorder(_ color: Color = Surface.onSurface, opacity: Double = 0.1) -> some ShapeStyle {
        color.opacity(opacity)
    }
}

// MARK: - Hex Color Initializer

extension Color {
    init(hex: UInt, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

// MARK: - Gradient Helpers

enum ObsidianGradients {
    static func blueCTA() -> LinearGradient {
        LinearGradient(
            colors: [
                Color(hex: 0x3E90FF),
                Color(hex: 0x6BB5FF),
                Color(hex: 0xAAC7FF, alpha: 0.85)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    static func amberCTA() -> LinearGradient {
        LinearGradient(
            colors: [
                Color(hex: 0xD4940A),
                Color(hex: 0xFFC07A),
                Color(hex: 0xFFD89E)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    static func glassPanel() -> LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.05),
                Color.white.opacity(0.02)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Obsidian View Modifiers

struct ObsidianGlassContainer: ViewModifier {
    var cornerRadius: CGFloat = LiquidDesignTokens.CornerRadius.card

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(ObsidianGradients.glassPanel())
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                    )
            )
    }
}

extension View {
    func obsidianGlass(cornerRadius: CGFloat = LiquidDesignTokens.CornerRadius.card) -> some View {
        modifier(ObsidianGlassContainer(cornerRadius: cornerRadius))
    }
}

// MARK: - Uppercase Tracked Label

struct TrackedLabel: View {
    let text: String
    var font: Font = LiquidDesignTokens.Typography.labelMedium
    var color: Color = LiquidDesignTokens.Surface.onSurfaceMuted
    var tracking: CGFloat = 1.5

    var body: some View {
        Text(text.uppercased())
            .font(font)
            .tracking(tracking)
            .foregroundStyle(color)
    }
}
