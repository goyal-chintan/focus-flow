import SwiftUI

// MARK: - Codable Enums for Token Persistence

enum FFColorToken: String, Codable, CaseIterable {
    case blue, green, orange, red, purple, pink, yellow, cyan, mint, indigo, teal, brown, gray

    var color: Color {
        switch self {
        case .blue: .blue
        case .green: .green
        case .orange: .orange
        case .red: .red
        case .purple: .purple
        case .pink: .pink
        case .yellow: .yellow
        case .cyan: .cyan
        case .mint: .mint
        case .indigo: .indigo
        case .teal: .teal
        case .brown: .brown
        case .gray: .gray
        }
    }
}

enum FFWeightToken: String, Codable, CaseIterable {
    case ultraLight, thin, light, regular, medium, semibold, bold, heavy, black

    var weight: Font.Weight {
        switch self {
        case .ultraLight: .ultraLight
        case .thin: .thin
        case .light: .light
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        case .heavy: .heavy
        case .black: .black
        }
    }
}

// MARK: - Token Category Structs

struct FFSpacingTokens: Codable, Equatable {
    var xxs: CGFloat = 4 { didSet { xxs = max(0, min(64, xxs)) } }
    var xs: CGFloat = 8 { didSet { xs = max(0, min(64, xs)) } }
    var sm: CGFloat = 12 { didSet { sm = max(0, min(64, sm)) } }
    var md: CGFloat = 16 { didSet { md = max(0, min(64, md)) } }
    var lg: CGFloat = 24 { didSet { lg = max(0, min(64, lg)) } }
    var xl: CGFloat = 32 { didSet { xl = max(0, min(64, xl)) } }
}

struct FFRadiusTokens: Codable, Equatable {
    var control: CGFloat = 12 { didSet { control = max(0, min(40, control)) } }
    var card: CGFloat = 18 { didSet { card = max(0, min(40, card)) } }
    var hero: CGFloat = 28 { didSet { hero = max(0, min(40, hero)) } }
}

struct FFSizeTokens: Codable, Equatable {
    var controlMin: CGFloat = 44 { didSet { controlMin = max(20, min(80, controlMin)) } }
    var iconFrame: CGFloat = 48 { didSet { iconFrame = max(20, min(80, iconFrame)) } }
    var heroIcon: CGFloat = 72 { didSet { heroIcon = max(30, min(120, heroIcon)) } }
}

struct FFRingTokens: Codable, Equatable {
    var size: CGFloat = 198 { didSet { size = max(80, min(400, size)) } }
    var strokeWidth: CGFloat = 4.2 { didSet { strokeWidth = max(1, min(20, strokeWidth)) } }
    var timerFontSize: CGFloat = 60 { didSet { timerFontSize = max(20, min(120, timerFontSize)) } }
    var timerFontWeight: FFWeightToken = .regular
    var labelFontSize: CGFloat = 14 { didSet { labelFontSize = max(8, min(30, labelFontSize)) } }
    var labelFontWeight: FFWeightToken = .semibold
    var digitTracking: CGFloat = 1.0 { didSet { digitTracking = max(0, min(10, digitTracking)) } }
    var labelTracking: CGFloat = 1.2 { didSet { labelTracking = max(0, min(10, labelTracking)) } }
    var backgroundDiscOpacity: CGFloat = 0.03 { didSet { backgroundDiscOpacity = max(0, min(1, backgroundDiscOpacity)) } }
    var trackOpacity: CGFloat = 0.08 { didSet { trackOpacity = max(0, min(1, trackOpacity)) } }
    var glowRadius: CGFloat = 10 { didSet { glowRadius = max(0, min(30, glowRadius)) } }
    var glowOpacity: CGFloat = 0.45 { didSet { glowOpacity = max(0, min(1, glowOpacity)) } }

    var timerFont: Font { .system(size: timerFontSize, weight: timerFontWeight.weight, design: .rounded) }
    var labelFont: Font { .system(size: labelFontSize, weight: labelFontWeight.weight, design: .rounded) }
}

struct FFTypographyTokens: Codable, Equatable {
    // Each FFType style → size + weight (design is always .rounded)
    var heroLabelSize: CGFloat = 13 { didSet { heroLabelSize = max(8, min(40, heroLabelSize)) } }
    var heroLabelWeight: FFWeightToken = .semibold
    var titleSize: CGFloat = 15 { didSet { titleSize = max(8, min(40, titleSize)) } }
    var titleWeight: FFWeightToken = .semibold
    var titleLargeSize: CGFloat = 17 { didSet { titleLargeSize = max(8, min(40, titleLargeSize)) } }
    var titleLargeWeight: FFWeightToken = .semibold
    var cardValueSize: CGFloat = 17 { didSet { cardValueSize = max(8, min(40, cardValueSize)) } }
    var cardValueWeight: FFWeightToken = .semibold
    var bodySize: CGFloat = 13 { didSet { bodySize = max(8, min(40, bodySize)) } }
    var bodyWeight: FFWeightToken = .medium
    var calloutSize: CGFloat = 13 { didSet { calloutSize = max(8, min(40, calloutSize)) } }
    var calloutWeight: FFWeightToken = .semibold
    var metaSize: CGFloat = 13 { didSet { metaSize = max(8, min(40, metaSize)) } }
    var metaWeight: FFWeightToken = .medium
    var microSize: CGFloat = 11 { didSet { microSize = max(8, min(40, microSize)) } }
    var microWeight: FFWeightToken = .medium

    // Computed fonts (all .rounded design, matching FFType)
    var heroLabel: Font { .system(size: heroLabelSize, weight: heroLabelWeight.weight, design: .rounded) }
    var title: Font { .system(size: titleSize, weight: titleWeight.weight, design: .rounded) }
    var titleLarge: Font { .system(size: titleLargeSize, weight: titleLargeWeight.weight, design: .rounded) }
    var cardValue: Font { .system(size: cardValueSize, weight: cardValueWeight.weight, design: .rounded) }
    var bodyFont: Font { .system(size: bodySize, weight: bodyWeight.weight, design: .rounded) }
    var callout: Font { .system(size: calloutSize, weight: calloutWeight.weight, design: .rounded) }
    var meta: Font { .system(size: metaSize, weight: metaWeight.weight, design: .rounded) }
    var micro: Font { .system(size: microSize, weight: microWeight.weight, design: .rounded) }
}

struct FFColorTokens: Codable, Equatable {
    var focusToken: FFColorToken = .blue
    var successToken: FFColorToken = .green
    var warningToken: FFColorToken = .orange
    var dangerToken: FFColorToken = .red
    var deepFocusToken: FFColorToken = .indigo

    // Panel & surface opacities (matching DesignSystem.swift FFColor)
    var panelFillOpacity: CGFloat = 0.04 { didSet { panelFillOpacity = max(0, min(1, panelFillOpacity)) } }
    var panelBorderOpacity: CGFloat = 0.08 { didSet { panelBorderOpacity = max(0, min(1, panelBorderOpacity)) } }
    var panelHighlightOpacity: CGFloat = 0.08 { didSet { panelHighlightOpacity = max(0, min(1, panelHighlightOpacity)) } }
    var insetFillOpacity: CGFloat = 0.05 { didSet { insetFillOpacity = max(0, min(1, insetFillOpacity)) } }
    var rowFillOpacity: CGFloat = 0.03 { didSet { rowFillOpacity = max(0, min(1, rowFillOpacity)) } }
    var fieldFillOpacity: CGFloat = 0.05 { didSet { fieldFillOpacity = max(0, min(1, fieldFillOpacity)) } }
    var fieldBorderOpacity: CGFloat = 0.10 { didSet { fieldBorderOpacity = max(0, min(1, fieldBorderOpacity)) } }

    // Convenience accessors matching FFColor.* naming
    var focus: Color { focusToken.color }
    var success: Color { successToken.color }
    var warning: Color { warningToken.color }
    var danger: Color { dangerToken.color }
    var deepFocus: Color { deepFocusToken.color }
}

struct FFMotionTokens: Codable, Equatable {
    var popoverResponse: CGFloat = 0.34 { didSet { popoverResponse = max(0.05, min(3.0, popoverResponse)) } }
    var popoverDamping: CGFloat = 0.84 { didSet { popoverDamping = max(0.1, min(1.5, popoverDamping)) } }
    var sectionResponse: CGFloat = 0.30 { didSet { sectionResponse = max(0.05, min(3.0, sectionResponse)) } }
    var sectionDamping: CGFloat = 0.82 { didSet { sectionDamping = max(0.1, min(1.5, sectionDamping)) } }
    var controlResponse: CGFloat = 0.22 { didSet { controlResponse = max(0.05, min(3.0, controlResponse)) } }
    var controlDamping: CGFloat = 0.80 { didSet { controlDamping = max(0.1, min(1.5, controlDamping)) } }
    var breathingDuration: CGFloat = 1.8 { didSet { breathingDuration = max(0.5, min(5.0, breathingDuration)) } }

    var popover: Animation { .spring(response: popoverResponse, dampingFraction: popoverDamping) }
    var section: Animation { .spring(response: sectionResponse, dampingFraction: sectionDamping) }
    var control: Animation { .spring(response: controlResponse, dampingFraction: controlDamping) }
    var breathing: Animation { .easeInOut(duration: breathingDuration).repeatForever(autoreverses: true) }
    var glass: Animation { .bouncy }
    var content: Animation { section }
}

struct FFLayoutTokens: Codable, Equatable {
    var popoverWidth: CGFloat = 340 { didSet { popoverWidth = max(250, min(500, popoverWidth)) } }
    var sessionDotSize: CGFloat = 6 { didSet { sessionDotSize = max(2, min(20, sessionDotSize)) } }
    var barChartHeight: CGFloat = 140 { didSet { barChartHeight = max(60, min(400, barChartHeight)) } }
}

// MARK: - Main Observable Token Container

@Observable
final class FFDesignTokens: Codable, Equatable {
    var spacing = FFSpacingTokens()
    var radius = FFRadiusTokens()
    var sizing = FFSizeTokens()
    var ring = FFRingTokens()
    var typography = FFTypographyTokens()
    var color = FFColorTokens()
    var motion = FFMotionTokens()
    var layout = FFLayoutTokens()

    init() {}

    // MARK: Codable

    enum CodingKeys: String, CodingKey {
        case spacing, radius, sizing, ring, typography, color, motion, layout
    }

    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        spacing = try c.decodeIfPresent(FFSpacingTokens.self, forKey: .spacing) ?? FFSpacingTokens()
        radius = try c.decodeIfPresent(FFRadiusTokens.self, forKey: .radius) ?? FFRadiusTokens()
        sizing = try c.decodeIfPresent(FFSizeTokens.self, forKey: .sizing) ?? FFSizeTokens()
        ring = try c.decodeIfPresent(FFRingTokens.self, forKey: .ring) ?? FFRingTokens()
        typography = try c.decodeIfPresent(FFTypographyTokens.self, forKey: .typography) ?? FFTypographyTokens()
        color = try c.decodeIfPresent(FFColorTokens.self, forKey: .color) ?? FFColorTokens()
        motion = try c.decodeIfPresent(FFMotionTokens.self, forKey: .motion) ?? FFMotionTokens()
        layout = try c.decodeIfPresent(FFLayoutTokens.self, forKey: .layout) ?? FFLayoutTokens()
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(spacing, forKey: .spacing)
        try c.encode(radius, forKey: .radius)
        try c.encode(sizing, forKey: .sizing)
        try c.encode(ring, forKey: .ring)
        try c.encode(typography, forKey: .typography)
        try c.encode(color, forKey: .color)
        try c.encode(motion, forKey: .motion)
        try c.encode(layout, forKey: .layout)
    }

    // MARK: Equatable

    static func == (lhs: FFDesignTokens, rhs: FFDesignTokens) -> Bool {
        lhs.spacing == rhs.spacing && lhs.radius == rhs.radius && lhs.sizing == rhs.sizing &&
        lhs.ring == rhs.ring && lhs.typography == rhs.typography && lhs.color == rhs.color &&
        lhs.motion == rhs.motion && lhs.layout == rhs.layout
    }

    // MARK: Utilities

    func copy() -> FFDesignTokens {
        let data = try! JSONEncoder().encode(self)
        return try! JSONDecoder().decode(FFDesignTokens.self, from: data)
    }

    func apply(from other: FFDesignTokens) {
        spacing = other.spacing
        radius = other.radius
        sizing = other.sizing
        ring = other.ring
        typography = other.typography
        color = other.color
        motion = other.motion
        layout = other.layout
    }
}
