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
        /// Light-mode frosting laid over glass and material panels (popover, coach panel), so a
        /// dark desktop behind never turns them grey. Clear in dark mode.
        static let frosted = Color.adaptive(light: 0xFBFBFD, dark: 0x000000, lightAlpha: 0.78, darkAlpha: 0)
        static let materialOverlay = Color.adaptive(light: 0xFFFFFF, dark: 0x000000, lightAlpha: 0.08, darkAlpha: 0.20)
    }

    // MARK: - Spectral Colors (Light Sources)
    /// Dark mode keeps the luminous pastels that glow on near-black. Light mode uses deep,
    /// saturated versions of the same hues (≥ 4.5:1 on white; light-mode design 2026-11-18),
    /// so state colours read as ink on frosted white instead of washing out.
    enum Spectral {
        static let electricBlue = Color.adaptive(light: 0x1F6FE0, dark: 0xAAC7FF)
        static let primaryContainer = Color.adaptive(light: 0x1F6FE0, dark: 0x3E90FF)
        static let amber = Color.adaptive(light: 0xB45309, dark: 0xFFC07A)
        static let amberDark = Color.adaptive(light: 0x9A4A06, dark: 0xD4940A)
        static let mint = Color.adaptive(light: 0x15805A, dark: 0x5ED4A0)
        static let mintDark = Color.adaptive(light: 0x0F6B43, dark: 0x34C77B)
        static let salmon = Color.adaptive(light: 0xC2362F, dark: 0xFFB4A8)
        static let destructive = Color.adaptive(light: 0xC2362F, dark: 0xFF6B6B)
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
    /// Each gradient has a dark-mode ramp (bright, towards a pastel) and a light-mode ramp that
    /// stays deep end to end, so the white label holds ≥ 3:1 across the whole button.
    enum Gradient {
        private static let blueLight: [UInt] = [0x1A63D6, 0x2A72E8, 0x3D84F2]
        private static let blueDark: [UInt] = [0x5B9EF8, 0x6AABFF, 0xA5C4FF]
        private static let greenLight: [UInt] = [0x116B44, 0x15805A, 0x1A8A57]
        private static let greenDark: [UInt] = [0x34C77B, 0x5ED4A0, 0x8CE6C0]

        static let focus = adaptiveRamp(light: blueLight, dark: blueDark)
        static let resume = adaptiveRamp(light: [0xB45F00, 0xC47200, 0xD48812], dark: [0xCC8800, 0xE6A820, 0xF0C040])
        static let pause = resume
        static let stop = adaptiveRamp(light: [0xA82828, 0xB83232, 0xC83A3A], dark: [0xC03030, 0xD94848, 0xEF6B6B])

        /// Interpolated blue→green gradient based on Pomodoro cycle progress.
        /// progress 0.0 = pure blue (just started), 1.0 = pure green (earned it).
        static func cycleCompletion(progress: Double) -> LinearGradient {
            let p = min(max(progress, 0), 1)
            return adaptiveRamp(
                light: zip(blueLight, greenLight).map { lerpHex($0, $1, p) },
                dark: zip(blueDark, greenDark).map { lerpHex($0, $1, p) }
            )
        }

        static func adaptiveRamp(light: [UInt], dark: [UInt]) -> LinearGradient {
            LinearGradient(
                colors: zip(light, dark).map { Color.adaptive(light: $0, dark: $1) },
                startPoint: .leading,
                endPoint: .trailing
            )
        }

        private static func lerpHex(_ a: UInt, _ b: UInt, _ p: Double) -> UInt {
            func channel(_ shift: UInt) -> UInt {
                let x = Double((a >> shift) & 0xFF), y = Double((b >> shift) & 0xFF)
                return UInt((x + (y - x) * p).rounded()) << shift
            }
            return channel(16) | channel(8) | channel(0)
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

    /// True while the view's window is off screen (the closed menu bar popover). Repeating and
    /// per-second animations stop: a hidden popover kept animating its ring and redrew it every
    /// frame, about a third of a core for as long as a block ran (17 Nov 2026).
    @Entry var motionPaused = false
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
