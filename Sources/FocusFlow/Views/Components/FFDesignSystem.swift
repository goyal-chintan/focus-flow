import SwiftUI

// Companion-window design system (docs/plans/2026-10-17-companion-window-redesign.md §3).
//
// • Surfaces: content sits on plain sections (subtle fill, radius 12, hairline). No glass on content.
// • Type: six styles only, numbers always monospaced digits.
// • Spacing: 4-pt grid (4, 8, 12, 16, 24).
// • Colour: one accent for "your focus", semantic green/orange, project colours only on project marks.
// • Motion: 0.25–0.35 s smooth/snappy curves, nothing bouncy on data, all gated on Reduce Motion.
//
// This file is additive: it does not change the LiquidDesignTokens API used by the popover.

// MARK: - Spacing, radii

enum FFSpace {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24

    static let page: CGFloat = xl
    static let sectionGap: CGFloat = l
    static let row: CGFloat = s
}

enum FFRadius {
    static let control: CGFloat = 8
    static let section: CGFloat = 12
    static let hero: CGFloat = 16
}

// MARK: - Type

enum FFTextStyle {
    /// 26 semibold: page titles and the goal hero number.
    case largeTitle
    /// 17 semibold: section titles and stat values.
    case title3
    /// 13 semibold: row titles and emphasised labels.
    case headline
    /// 13 regular.
    case body
    /// 12 regular, secondary.
    case callout
    /// 11 regular, secondary.
    case caption

    var font: Font {
        switch self {
        case .largeTitle: .system(size: 26, weight: .semibold)
        case .title3: .system(size: 17, weight: .semibold)
        case .headline: .system(size: 13, weight: .semibold)
        case .body: .system(size: 13, weight: .regular)
        case .callout: .system(size: 12, weight: .regular)
        case .caption: .system(size: 11, weight: .regular)
        }
    }

    var isSecondary: Bool { self == .callout || self == .caption }
}

extension View {
    /// Applies one of the six companion text styles. Callout and caption default to secondary;
    /// the others inherit, so an outer `.foregroundStyle` can still colour them.
    @ViewBuilder
    func ffText(_ style: FFTextStyle) -> some View {
        if style.isSecondary {
            font(style.font).foregroundStyle(.secondary)
        } else {
            font(style.font)
        }
    }

    /// Numeric text: monospaced digits and a rolling-digit transition when the value changes.
    func ffNumber(_ style: FFTextStyle) -> some View {
        ffText(style)
            .monospacedDigit()
            .contentTransition(.numericText())
    }
}

// MARK: - Colour

enum FFPalette {
    /// The single accent for "your focus".
    static let accent = LiquidDesignTokens.Spectral.primaryContainer
    /// Goal met.
    static let goal = Color.green
    /// At risk / derailers.
    static let atRisk = Color.orange
    static let destructive = Color.red

    /// Window background (explicit so off-screen renders match the live window).
    static let windowBackground = Color(nsColor: .windowBackgroundColor)
    /// Section fill: a lifted white sheet in light mode, a faint lift in dark mode.
    static let sectionFill = Color.adaptive(light: 0xFFFFFF, dark: 0xFFFFFF, lightAlpha: 0.72, darkAlpha: 0.045)
    static let hairline = Color.adaptive(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.08, darkAlpha: 0.09)
    static let rowHover = Color.adaptive(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.045, darkAlpha: 0.06)
    static let rowSelected = accent.opacity(0.14)
    static let gridLine = Color.adaptive(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.07, darkAlpha: 0.09)
    /// Empty heatmap cell / track.
    static let track = Color.adaptive(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.055, darkAlpha: 0.07)
    static let comparison = Color.adaptive(light: 0x8E8E93, dark: 0x8E8E93, lightAlpha: 0.45, darkAlpha: 0.55)

    /// Colour for a stored project colour name. Use only on project-specific marks.
    static func project(_ name: String?) -> Color {
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
        case nil: Color.gray
        default: .blue
        }
    }

    static func outcome(_ outcome: SessionOutcome) -> Color {
        switch outcome {
        case .shipped: goal
        case .movedForward: accent
        case .busywork: atRisk
        }
    }

    /// Five-step accent ramp for heatmaps (0 = empty).
    static func heat(_ level: Int) -> Color {
        switch level {
        case ...0: track
        case 1: accent.opacity(0.25)
        case 2: accent.opacity(0.48)
        case 3: accent.opacity(0.72)
        default: accent
        }
    }
}

// MARK: - Motion

enum FFAnimation {
    /// Destination switches and section changes.
    static let page: Animation = .smooth(duration: 0.3)
    /// Picker, selection and toggles.
    static let control: Animation = .snappy(duration: 0.25)
    /// Charts growing in or re-ranging.
    static let chart: Animation = .smooth(duration: 0.35)
    /// Hover highlights.
    static let hover: Animation = .smooth(duration: 0.25)

    /// `nil` under Reduce Motion so state changes apply instantly.
    static func gated(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }
}

// MARK: - Formatting

enum FFFormat {
    /// "1h 40m", "2h", "40m", "0m".
    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int((max(0, seconds) / 60).rounded())
        let hours = total / 60
        let minutes = total % 60
        if hours > 0 && minutes == 0 { return "\(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    /// "2.5h" style for axes and compact labels.
    static func hours(_ seconds: TimeInterval) -> String {
        let hours = seconds / 3600
        if hours == 0 { return "0" }
        return hours.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(hours))h" : String(format: "%.1fh", hours)
    }

    static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    static func signedDuration(_ seconds: TimeInterval) -> String {
        let sign = seconds >= 0 ? "+" : "−"
        return sign + duration(abs(seconds))
    }

    static func hourLabel(_ hour: Int) -> String {
        String(format: "%02d:00", ((hour % 24) + 24) % 24)
    }

    static let weekdayShort = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    /// 24-hour clock ("22:05"), matching how focus windows are described.
    static func clock(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    /// Two-digit 24-hour label for axes ("00", "03", … "21").
    static func hour(_ date: Date, calendar: Calendar = .current) -> String {
        String(format: "%02d", calendar.component(.hour, from: date))
    }
}

// MARK: - Building blocks

/// Page header: large title, a quiet subtitle, and trailing actions.
struct FFPageHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: () -> Trailing

    init(_ title: String, subtitle: String? = nil, @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: FFSpace.m) {
            VStack(alignment: .leading, spacing: FFSpace.xs) {
                Text(title)
                    .ffText(.largeTitle)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle).ffText(.callout)
                }
            }
            Spacer(minLength: FFSpace.m)
            trailing()
        }
    }
}

/// A plain content section: title row, then content on a subtle fill with a hairline.
struct FFSection<Content: View, Accessory: View>: View {
    let title: String?
    var subtitle: String?
    var padding: CGFloat
    @ViewBuilder var accessory: () -> Accessory
    @ViewBuilder var content: () -> Content

    init(
        _ title: String? = nil,
        subtitle: String? = nil,
        padding: CGFloat = FFSpace.l,
        @ViewBuilder accessory: @escaping () -> Accessory = { EmptyView() },
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.padding = padding
        self.accessory = accessory
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: FFSpace.m) {
            if title != nil || subtitle != nil {
                HStack(alignment: .firstTextBaseline, spacing: FFSpace.s) {
                    VStack(alignment: .leading, spacing: 2) {
                        if let title {
                            Text(title)
                                .ffText(.title3)
                                .accessibilityAddTraits(.isHeader)
                        }
                        if let subtitle {
                            Text(subtitle)
                                .ffText(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: FFSpace.s)
                    accessory()
                }
            }
            content()
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ffSurface()
    }
}

extension View {
    /// Plain section surface: subtle fill, radius 12, hairline stroke.
    func ffSurface(radius: CGFloat = FFRadius.section) -> some View {
        background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(FFPalette.sectionFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(FFPalette.hairline, lineWidth: 0.5)
        )
    }

    /// Subtle hover (and optional selection) highlight for list rows.
    func ffHoverRow(isSelected: Bool = false, radius: CGFloat = FFRadius.control) -> some View {
        modifier(FFHoverRowModifier(isSelected: isSelected, radius: radius))
    }
}

private struct FFHoverRowModifier: ViewModifier {
    let isSelected: Bool
    let radius: CGFloat
    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(isSelected ? FFPalette.rowSelected : (isHovering ? FFPalette.rowHover : .clear))
            )
            .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .onHover { hovering in
                withAnimation(FFAnimation.gated(FFAnimation.hover, reduceMotion: reduceMotion)) {
                    isHovering = hovering
                }
            }
    }
}

/// A plain stat: label, value, optional caption.
struct FFStat: View {
    let label: String
    let value: String
    var caption: String?
    var valueColor: Color?

    var body: some View {
        VStack(alignment: .leading, spacing: FFSpace.xs) {
            Text(label).ffText(.callout)
            Text(value)
                .ffNumber(.title3)
                .foregroundStyle(valueColor ?? .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let caption {
                Text(caption)
                    .ffText(.caption)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Quiet empty state used inside sections.
struct FFEmptyState: View {
    let systemImage: String
    let message: String
    var detail: String?

    var body: some View {
        HStack(alignment: .top, spacing: FFSpace.m) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(.tertiary)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(message).ffText(.body).foregroundStyle(.secondary)
                if let detail {
                    Text(detail).ffText(.caption)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, FFSpace.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Legend swatch + label.
struct FFLegendItem: View {
    let color: Color
    let label: String
    var marker: Marker = .square

    enum Marker { case square, circle, line }

    var body: some View {
        HStack(spacing: FFSpace.xs) {
            Group {
                switch marker {
                case .square: RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
                case .circle: Circle().fill(color).frame(width: 8, height: 8)
                case .line: Capsule().fill(color).frame(width: 14, height: 2)
                }
            }
            .accessibilityHidden(true)
            Text(label).ffText(.caption)
        }
    }
}

/// Floating value tooltip for chart hover/selection.
struct FFChartTooltip: View {
    let title: String
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).ffText(.headline).monospacedDigit()
            ForEach(lines, id: \.self) { line in
                Text(line).ffText(.caption).monospacedDigit()
            }
        }
        .padding(.horizontal, FFSpace.s + 2)
        .padding(.vertical, FFSpace.s - 2)
        .background(
            RoundedRectangle(cornerRadius: FFRadius.control, style: .continuous)
                .fill(FFPalette.windowBackground)
                .shadow(color: .black.opacity(0.14), radius: 8, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: FFRadius.control, style: .continuous)
                .strokeBorder(FFPalette.hairline, lineWidth: 0.5)
        )
        .fixedSize()
        .allowsHitTesting(false)
    }
}

/// Segmented range picker. The native segmented control carries Tahoe's glass and its own smooth
/// selection indicator, so no custom pill is drawn (see CLAUDE.md "matchedGeometryEffect pills").
struct FFSegmentedPicker<Value: Hashable & Identifiable>: View {
    let title: String
    let options: [Value]
    @Binding var selection: Value
    let label: (Value) -> String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Picker(title, selection: Binding(
            get: { selection },
            set: { newValue in
                withAnimation(FFAnimation.gated(FFAnimation.chart, reduceMotion: reduceMotion)) {
                    selection = newValue
                }
            }
        )) {
            ForEach(options) { option in
                Text(label(option)).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .accessibilityLabel(title)
    }
}

/// Animates a 0→1 "reveal" value on appear and whenever `trigger` changes, so bars grow from
/// their baseline. Under Reduce Motion the value is 1 immediately.
struct FFRevealModifier<Trigger: Equatable>: ViewModifier {
    @Binding var progress: Double
    let trigger: Trigger
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.focusFlowEvidenceRendering) private var evidenceRendering

    func body(content: Content) -> some View {
        content
            .onAppear { reveal() }
            .onChange(of: trigger) { _, _ in reveal() }
    }

    private func reveal() {
        guard !reduceMotion, !evidenceRendering else {
            progress = 1
            return
        }
        progress = 0
        withAnimation(FFAnimation.chart.delay(0.05)) { progress = 1 }
    }
}

extension View {
    func ffReveal<Trigger: Equatable>(_ progress: Binding<Double>, trigger: Trigger) -> some View {
        modifier(FFRevealModifier(progress: progress, trigger: trigger))
    }
}
