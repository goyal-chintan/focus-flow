import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: - Obsidian Lens Design System
// Based on the "Liquid Refraction" DESIGN.md specifications.
// Near-black foundation, electric blue/amber spectral highlights,
// editorial SF Pro typography, no 1px borders.

enum LiquidDesignTokens {

    // MARK: - Surface Palette (Obsidian Layering)
    enum Surface {
        static let background = Color.adaptive(light: 0xF4F4F6, dark: 0x131315)
        static let containerLow = Color.adaptive(light: 0xEBEBEF, dark: 0x1C1C1E)
        static let container = Color.adaptive(light: 0xE4E4E8, dark: 0x252526)
        static let containerHigh = Color.adaptive(light: 0xDDDDE2, dark: 0x2C2C2E)
        static let containerHighest = Color.adaptive(light: 0xD6D6DC, dark: 0x353534)
        static let onSurface = Color.primary
        static let onSurfaceMuted = Color.secondary
        static let onProminent = Color.adaptive(light: 0xFFFFFF, dark: 0xFFFFFF)
        static let glassStroke = Color.adaptive(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.08, darkAlpha: 0.08)
        static let materialOverlay = Color.adaptive(light: 0xFFFFFF, dark: 0x000000, lightAlpha: 0.08, darkAlpha: 0.20)
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
        static let xs: CGFloat = 4       // progress bars, small chips
        static let sm: CGFloat = 8       // small components, text fields
        static let md: CGFloat = 10      // medium containers
        static let control: CGFloat = 12
        static let picker: CGFloat = 14
        static let card: CGFloat = 16
        static let cta: CGFloat = 18
        static let panel: CGFloat = 20
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

    // MARK: - Gradients (CTA Fills)
    enum Gradient {
        static let focus = LinearGradient(
            colors: [Color(hex: 0x5B9EF8), Color(hex: 0x6AABFF), Color(hex: 0xA5C4FF)],
            startPoint: .leading,
            endPoint: .trailing
        )
        static let resume = LinearGradient(
            colors: [Color(hex: 0xCC8800), Color(hex: 0xE6A820), Color(hex: 0xF0C040)],
            startPoint: .leading,
            endPoint: .trailing
        )
        static let breakStart = LinearGradient(
            colors: [Color(hex: 0x34C77B), Color(hex: 0x5ED4A0), Color(hex: 0x8CE6C0)],
            startPoint: .leading,
            endPoint: .trailing
        )
        static let pause = LinearGradient(
            colors: [Color(hex: 0xCC8800), Color(hex: 0xE6A820), Color(hex: 0xF0C040)],
            startPoint: .leading,
            endPoint: .trailing
        )
        static let stop = LinearGradient(
            colors: [Color(hex: 0xC03030), Color(hex: 0xD94848), Color(hex: 0xEF6B6B)],
            startPoint: .leading,
            endPoint: .trailing
        )

        /// Interpolated blue→green gradient based on Pomodoro cycle progress.
        /// progress 0.0 = pure blue (just started), 1.0 = pure green (earned it).
        static func cycleCompletion(progress: Double) -> LinearGradient {
            let p = min(max(progress, 0), 1)

            // Blue endpoints (focus gradient)
            let blueStart = (r: 0x5B, g: 0x9E, b: 0xF8)
            let blueMid   = (r: 0x6A, g: 0xAB, b: 0xFF)
            let blueEnd   = (r: 0xA5, g: 0xC4, b: 0xFF)

            // Green endpoints (breakStart gradient)
            let greenStart = (r: 0x34, g: 0xC7, b: 0x7B)
            let greenMid   = (r: 0x5E, g: 0xD4, b: 0xA0)
            let greenEnd   = (r: 0x8C, g: 0xE6, b: 0xC0)

            func lerp(_ a: Int, _ b: Int) -> Double {
                Double(a) + (Double(b) - Double(a)) * p
            }

            let c1 = Color(
                red: lerp(blueStart.r, greenStart.r) / 255,
                green: lerp(blueStart.g, greenStart.g) / 255,
                blue: lerp(blueStart.b, greenStart.b) / 255
            )
            let c2 = Color(
                red: lerp(blueMid.r, greenMid.r) / 255,
                green: lerp(blueMid.g, greenMid.g) / 255,
                blue: lerp(blueMid.b, greenMid.b) / 255
            )
            let c3 = Color(
                red: lerp(blueEnd.r, greenEnd.r) / 255,
                green: lerp(blueEnd.g, greenEnd.g) / 255,
                blue: lerp(blueEnd.b, greenEnd.b) / 255
            )

            return LinearGradient(
                colors: [c1, c2, c3],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }

    // MARK: - Padding
    enum Padding {
        static let popoverHorizontal: CGFloat = 24
        static let controlVertical: CGFloat = 12
        static let controlHorizontal: CGFloat = 14
        static let cardPadding: CGFloat = 16
        static let cardPaddingSmall: CGFloat = 12
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

    static func adaptive(light: UInt, dark: UInt, lightAlpha: Double = 1.0, darkAlpha: Double = 1.0) -> Color {
#if os(macOS)
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light, alpha: isDark ? darkAlpha : lightAlpha)
        })
#else
        Color(hex: dark, alpha: darkAlpha)
#endif
    }
}

#if os(macOS)
private extension NSColor {
    convenience init(hex: UInt, alpha: Double = 1.0) {
        self.init(
            srgbRed: CGFloat(Double((hex >> 16) & 0xFF) / 255),
            green: CGFloat(Double((hex >> 8) & 0xFF) / 255),
            blue: CGFloat(Double(hex & 0xFF) / 255),
            alpha: CGFloat(alpha)
        )
    }
}
#endif

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
                Color.adaptive(light: 0xFFFFFF, dark: 0xFFFFFF, lightAlpha: 0.45, darkAlpha: 0.05),
                Color.adaptive(light: 0xFFFFFF, dark: 0xFFFFFF, lightAlpha: 0.20, darkAlpha: 0.02)
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
                            .stroke(LiquidDesignTokens.Surface.glassStroke, lineWidth: 0.5)
                    )
            )
    }
}

extension View {
    func obsidianGlass(cornerRadius: CGFloat = LiquidDesignTokens.CornerRadius.card) -> some View {
        modifier(ObsidianGlassContainer(cornerRadius: cornerRadius))
    }

    /// Evidence-safe replacement for `.glassEffect(.regular, in: RoundedRectangle(...))`.
    /// Uses native glass in production; falls back to obsidian glass during evidence rendering.
    func evidenceSafeGlass(cornerRadius: CGFloat = LiquidDesignTokens.CornerRadius.control) -> some View {
        modifier(EvidenceSafeGlassModifier(cornerRadius: cornerRadius))
    }

    /// Conditionally apply a view modifier
    @ViewBuilder
    func `if`<Transform: View>(_ condition: Bool, transform: (Self) -> Transform) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

/// Modifier that uses native `.glassEffect` in production but falls back to obsidian glass
/// during evidence rendering, where native glass APIs produce invisible output.
struct EvidenceSafeGlassModifier: ViewModifier {
    @Environment(\.focusFlowEvidenceRendering) private var isEvidenceRendering
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if isEvidenceRendering {
            content
                .obsidianGlass(cornerRadius: cornerRadius)
        } else {
            content
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius))
        }
    }
}

/// Evidence-safe replacement for `.buttonStyle(.glass)` on standalone buttons.
/// Renders a visible obsidian-glass capsule during evidence capture.
struct EvidenceSafeGlassButtonStyle: ButtonStyle {
    let shape: AnyShape
    let isEvidence: Bool

    init(shape: AnyShape = AnyShape(Capsule(style: .continuous)), isEvidence: Bool) {
        self.shape = shape
        self.isEvidence = isEvidence
    }

    func makeBody(configuration: Configuration) -> some View {
        if isEvidence {
            configuration.label
                .background(
                    shape
                        .fill(ObsidianGradients.glassPanel())
                        .overlay(shape.stroke(LiquidDesignTokens.Surface.glassStroke, lineWidth: 0.5))
                )
                .opacity(configuration.isPressed ? 0.7 : 1.0)
        } else {
            // Fallback plain — the caller should layer .buttonStyle(.glass) on top if not evidence
            configuration.label
        }
    }
}

/// Evidence-safe replacement for `GlassEffectContainer`.
/// Uses native `GlassEffectContainer` in production; wraps content with an obsidian glass
/// background during evidence rendering where the native container renders as invisible.
struct EvidenceSafeGlassGroup<Content: View>: View {
    @Environment(\.focusFlowEvidenceRendering) private var isEvidenceRendering
    let cornerRadius: CGFloat
    let content: () -> Content

    init(cornerRadius: CGFloat = LiquidDesignTokens.CornerRadius.card, @ViewBuilder content: @escaping () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content
    }

    var body: some View {
        if isEvidenceRendering {
            content()
                .obsidianGlass(cornerRadius: cornerRadius)
        } else {
            GlassEffectContainer {
                content()
            }
        }
    }
}

/// Evidence-safe replacement for `.ultraThinMaterial` backgrounds.
struct EvidenceSafeMaterialModifier: ViewModifier {
    @Environment(\.focusFlowEvidenceRendering) private var isEvidenceRendering

    func body(content: Content) -> some View {
        if isEvidenceRendering {
            content
                .background(
                    Rectangle()
                        .fill(LiquidDesignTokens.Surface.containerLow)
                        .overlay(LiquidDesignTokens.Surface.materialOverlay)
                )
        } else {
            content
                .background(
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .overlay(LiquidDesignTokens.Surface.materialOverlay)
                )
        }
    }
}

extension View {
    func evidenceSafeMaterial() -> some View {
        modifier(EvidenceSafeMaterialModifier())
    }
}

private struct FocusFlowEvidenceRenderingKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var focusFlowEvidenceRendering: Bool {
        get { self[FocusFlowEvidenceRenderingKey.self] }
        set { self[FocusFlowEvidenceRenderingKey.self] = newValue }
    }
}

// MARK: - Motion System (Standardized Springs)

enum FFMotion {
    /// Popover entry/exit — gentle spring with slight overshoot
    static let popover: Animation = .spring(response: 0.36, dampingFraction: 0.82)

    /// Section/state transitions — medium spring
    static let section: Animation = .spring(response: 0.34, dampingFraction: 0.84)

    /// Control interactions — snappy spring for buttons, toggles
    static let control: Animation = .spring(response: 0.26, dampingFraction: 0.82)

    /// Warning/intervention surfaces — tight, precise, no bounce (Gillison 2019: firm not punishing)
    /// Spec §11: "warning motion: subtle pulse/tighten, 140-220ms"
    static let warning: Animation = .easeOut(duration: 0.18)

    /// Reward/celebration — slight overshoot for delight (Harkin 2016: concrete progress feedback)
    /// Spec §11: "reward motion: single glow/settle, 220-320ms"
    static let reward: Animation = .spring(response: 0.32, dampingFraction: 0.65)

    /// Commitment lock-in — firm spring, minimal overshoot (Steel 2007: commitment devices)
    static let commit: Animation = .spring(response: 0.28, dampingFraction: 0.75)

    /// CPU-safe breathing — opacity-only oscillation on a STATIC-blur overlay.
    /// The blur radius stays fixed (pre-rendered); only opacity animates.
    /// This avoids the 60fps shadow re-rasterization that caused the original
    /// breathing animation to be removed (commit 6a7940e, Mar 23 2026).
    static let breathing: Animation = .easeInOut(duration: 2.2).repeatForever(autoreverses: true)

    /// Progress ring updates — smooth easing
    static let progress: Animation = .easeInOut(duration: 0.75)
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
