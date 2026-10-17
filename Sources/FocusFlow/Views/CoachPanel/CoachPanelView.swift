import SwiftUI

/// The on-screen coach panel (companion redesign §5): one hook, at most one fact,
/// one primary action and a "Not now ▾" menu. About 340 pt wide.
struct CoachPanelView: View {
    enum Chrome {
        /// Inside the floating NSPanel: AppKit draws the Liquid Glass background.
        case hosted
        /// Rendered on its own (evidence captures, previews): draws its own surface.
        case standalone
    }

    static let width: CGFloat = 356

    let presentation: CoachPanelPresentation
    var chrome: Chrome = .hosted
    var errorText: String?
    var onPrimary: () -> Void = {}
    var onSecondary: (CoachPanelSecondaryAction) -> Void = { _ in }
    var onClose: () -> Void = {}
    var onHover: (Bool) -> Void = { _ in }

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.focusFlowEvidenceRendering) private var isEvidenceRendering
    @State private var closeHovered = false
    @State private var primaryHovered = false

    private var message: CoachComposedMessage { presentation.message }
    private var palette: CoachPanelPalette { CoachPanelPalette(style: message.style) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
                header
                Text(message.hook)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
                if let detail = message.detail {
                    detailView(detail)
                        .padding(.top, 3)
                }
                if let errorText, !errorText.isEmpty {
                    Label(errorText, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(colorScheme == .dark ? Color.orange : Color(hex: 0xB45309))
                        .lineLimit(2)
                        .padding(.top, 6)
                        .accessibilityLabel("Couldn't start: \(errorText)")
                }
                if presentation.hasPrimary || !presentation.secondaryActions.isEmpty {
                    actions
                        .padding(.top, 10)
                }
                if let hint = presentation.footerHint {
                    footer(hint)
                        .padding(.top, 8)
                }
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.top, 8)
        .padding(.bottom, 14)
        .frame(width: Self.width, alignment: .leading)
        .background(surface)
        .overlay(accentWash)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(strokeColor, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onHover(perform: onHover)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Focus coach: \(message.accessibilityText)")
    }

    // MARK: Pieces

    private var glyph: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(LinearGradient(colors: palette.gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(systemName: glyphSymbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: 22, height: 22)
        .shadow(color: palette.gradient[0].opacity(0.35), radius: 4, y: 1)
        .accessibilityHidden(true)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            glyph
            Text(eyebrow)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(1.1)
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            if let level = presentation.level, presentation.kind == .rescue || presentation.kind == .pseudoProductivity {
                levelPips(level)
            }
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(Color.primary.opacity(closeHovered ? 0.12 : 0.06)))
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { closeHovered = $0 }
            .accessibilityLabel("Dismiss")
        }
        .frame(height: 30)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func detailView(_ detail: CoachDetail) -> some View {
        switch detail {
        case .quote(let quote):
            Text("\(Text("“\(quote.text)”").italic()) \(Text("— \(quote.author)").foregroundStyle(.tertiary))")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .help(quote.attribution)
        case .why(let line):
            Label {
                Text(line)
            } icon: {
                Image(systemName: "heart.fill").foregroundStyle(palette.gradient[0])
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .lineLimit(2)
        case .houseLine(let text):
            Text(text)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.primary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        case .fact(let text), .line(let text):
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Three small pips: how deep the drift is (L1–L3).
    private func levelPips(_ level: DriftLevel) -> some View {
        HStack(spacing: 3) {
            ForEach(1...3, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(index <= level.rawValue ? AnyShapeStyle(palette.gradient[index == 3 ? 1 : 0]) : AnyShapeStyle(Color.primary.opacity(0.12)))
                    .frame(width: 10, height: 4)
            }
        }
        .padding(.trailing, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Drift level \(level.rawValue) of 3: \(level.label)")
    }

    private func footer(_ hint: String) -> some View {
        Text(hint)
            .font(.system(size: 10, weight: .medium, design: .rounded))
        .foregroundStyle(.tertiary)
        .padding(.trailing, 8)
    }

    private var actions: some View {
        HStack(spacing: 6) {
            if presentation.hasPrimary {
                primaryButton
            }

            if let single = presentation.singleSecondary {
                Button {
                    onSecondary(single)
                } label: {
                    Text(presentation.title(for: single))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .padding(.horizontal, 8)
                        .frame(minHeight: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .keyboardShortcut(.cancelAction)
            } else if !presentation.secondaryActions.isEmpty {
                Menu {
                    ForEach(presentation.secondaryActions) { action in
                        Button(presentation.title(for: action)) { onSecondary(action) }
                    }
                } label: {
                    Text(presentation.menuTitle)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .frame(minHeight: 30)
                .padding(.horizontal, 6)
                .foregroundStyle(.secondary)
                .accessibilityLabel(presentation.menuTitle)
            }

            Spacer(minLength: 0)
        }
    }

    private var primaryButton: some View {
            Button(action: onPrimary) {
                HStack(spacing: 6) {
                    Image(systemName: primarySymbol)
                        .font(.system(size: 10, weight: .bold))
                    Text(message.primaryTitle)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Text("⏎")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .opacity(0.6)
                        .accessibilityHidden(true)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(
                    Capsule(style: .continuous)
                        .fill(LinearGradient(colors: palette.gradient, startPoint: .leading, endPoint: .trailing))
                        .brightness(primaryHovered ? 0.06 : 0)
                )
                .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5))
                .shadow(color: palette.gradient[1].opacity(0.30), radius: 5, y: 2)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            .onHover { primaryHovered = $0 }
            .layoutPriority(1)
    }

    // MARK: Surfaces

    @ViewBuilder
    private var surface: some View {
        switch chrome {
        case .hosted:
            Color.clear
        case .standalone:
            if isEvidenceRendering {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(LiquidDesignTokens.Surface.containerHigh)
            } else {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.regularMaterial)
            }
        }
    }

    /// A faint wash of the style colour from the top-left, so styles read at a glance.
    private var accentWash: some View {
        LinearGradient(
            colors: [palette.gradient[0].opacity(colorScheme == .dark ? 0.16 : 0.10), .clear],
            startPoint: .topLeading,
            endPoint: UnitPoint(x: 0.55, y: 0.9)
        )
        .allowsHitTesting(false)
    }

    private var strokeColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.08)
    }

    // MARK: Copy helpers

    private var eyebrow: String {
        switch presentation.kind {
        case .startNudge: "FOCUS COACH · \(message.style.displayName.uppercased())"
        case .pseudoProductivity: "FOCUS COACH · CHECK-IN"
        case .inSessionDrift: "FOCUS COACH · IN BLOCK"
        case .weeklyPriorities: "FOCUS COACH · THIS WEEK"
        case .rescue: "FOCUS COACH · \((presentation.level ?? .drifting).label.uppercased())"
        case .keepGoing: "STARTER BLOCK · DONE"
        case .momentum: "FOCUS COACH · MOMENTUM"
        case .notice: "FOCUS COACH"
        }
    }

    private var glyphSymbol: String {
        switch presentation.kind {
        case .pseudoProductivity: return "scope"
        case .inSessionDrift: return "arrow.uturn.backward"
        case .weeklyPriorities: return "flag.checkered"
        case .keepGoing: return "checkmark"
        case .momentum: return "bolt.fill"
        case .notice: return "play.fill"
        case .rescue:
            switch presentation.level ?? .drifting {
            case .ok, .drifting: return "arrow.uturn.backward"
            case .lost: return "arrow.down.forward.and.arrow.up.backward"
            case .spiral: return "pause.fill"
            }
        case .startNudge:
            switch message.style {
            case .challenger: return "flame.fill"
            case .data: return "chart.bar.fill"
            case .gentle: return "leaf.fill"
            }
        }
    }

    private var primarySymbol: String {
        switch presentation.kind {
        case .startNudge, .pseudoProductivity, .rescue, .notice: "play.fill"
        case .inSessionDrift: "arrow.uturn.backward"
        case .weeklyPriorities: "list.bullet"
        case .keepGoing: "forward.fill"
        case .momentum: "plus"
        }
    }
}

/// Accent colours per coaching style. Saturated enough for white button text in both modes.
struct CoachPanelPalette {
    let gradient: [Color]

    init(style: CoachStyle) {
        switch style {
        case .challenger: gradient = [Color(hex: 0xFF8A3D), Color(hex: 0xE8483A)]
        case .data: gradient = [Color(hex: 0x3E90FF), Color(hex: 0x2B5FE0)]
        case .gentle: gradient = [Color(hex: 0x2FBF7A), Color(hex: 0x15936B)]
        }
    }
}

/// Live panel content: reads the presentation and error from `TimerViewModel`.
struct CoachPanelHostView: View {
    @Environment(TimerViewModel.self) private var timerVM
    var chrome: CoachPanelView.Chrome = .hosted
    var onSizeChange: (CGSize) -> Void = { _ in }

    var body: some View {
        if let presentation = timerVM.coachPanel {
            CoachPanelView(
                presentation: presentation,
                chrome: chrome,
                errorText: timerVM.coachPanelError,
                onPrimary: { timerVM.performCoachPanelPrimary() },
                onSecondary: { timerVM.performCoachPanelSecondary($0) },
                onClose: { timerVM.dismissCoachInterventionWindow() },
                onHover: { timerVM.coachPanelHoverChanged($0) }
            )
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGSize.self) { $0.size } action: { onSizeChange($0) }
        }
    }
}
