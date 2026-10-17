import SwiftUI

/// The rescue loop's pause screen (rescue loop design §3.3): a full-screen translucent dim
/// with one large vetted quote, one honest fact and a one-click way back to work. It is a
/// pause, not a lock: Esc works at once, "Real break · 15m" and "Done for today" are always
/// there, and a quiet ✕ fades in after 8 seconds.
struct PauseScreenView: View {
    enum Chrome {
        /// Inside the pause-screen window: AppKit draws the behind-window material.
        case hosted
        /// Evidence renders: draws a stand-in desktop and blur so the dim can be judged.
        case standalone
    }

    let presentation: CoachPauseScreenPresentation
    var chrome: Chrome = .hosted
    /// Evidence renders show the ✕ that normally appears after 8 s.
    var showCloseImmediately = false
    var onStart: () -> Void = {}
    var onRealBreak: () -> Void = {}
    var onDone: () -> Void = {}
    var onEscape: () -> Void = {}
    var onClose: () -> Void = {}

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var closeVisible = false
    @State private var primaryHovered = false

    private var palette: CoachPanelPalette { CoachPanelPalette(style: presentation.style) }
    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        ZStack {
            dim
            content
                .frame(maxWidth: 860)
                .padding(.horizontal, 48)
                .scaleEffect(appeared || reduceMotion ? 1 : 0.965)
                .opacity(appeared ? 1 : 0)
            VStack {
                HStack {
                    Spacer()
                    closeButton
                }
                Spacer()
            }
            .padding(28)
        }
        .onAppear {
            if showCloseImmediately {
                appeared = true
                closeVisible = true
                return
            }
            withAnimation(.timingCurve(0.2, 0.9, 0.25, 1, duration: 0.35)) { appeared = true }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(CoachPauseScreenPolicy.closeButtonDelay))
                withAnimation(.easeOut(duration: 0.6)) { closeVisible = true }
            }
        }
        .onExitCommand(perform: onEscape)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Focus coach pause: \(presentation.accessibilityText)")
    }

    // MARK: Layers

    @ViewBuilder
    private var dim: some View {
        ZStack {
            if chrome == .standalone {
                EvidenceDesktop(isDark: isDark)
                    .blur(radius: 28)
                // Stands in for the behind-window blur, which off-screen renders cannot draw.
                Rectangle().fill(isDark ? Color(hex: 0x14161C).opacity(0.80) : Color(hex: 0xF2F2F5).opacity(0.80))
            }
            // The dim itself: darker toward the edges so the centre column reads first.
            RadialGradient(
                colors: isDark
                    ? [Color.black.opacity(0.30), Color.black.opacity(0.58)]
                    : [Color.white.opacity(0.28), Color.white.opacity(0.10)],
                center: .center,
                startRadius: 80,
                endRadius: 900
            )
            // A faint wash of the style colour from the top, so the screen feels like FocusFlow.
            LinearGradient(
                colors: [palette.gradient[0].opacity(isDark ? 0.14 : 0.10), .clear],
                startPoint: .top,
                endPoint: UnitPoint(x: 0.5, y: 0.55)
            )
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .accessibilityHidden(true)
    }

    private var content: some View {
        VStack(spacing: 0) {
            eyebrow
                .padding(.bottom, 34)
            headline
            if let fact = presentation.fact {
                factPill(fact)
                    .padding(.top, 40)
            }
            primaryButton
                .padding(.top, presentation.fact == nil ? 44 : 28)
            secondaryRow
                .padding(.top, 14)
            Text("esc to dismiss  ·  ⏎ to start")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .tracking(0.3)
                .foregroundStyle(.tertiary)
                .padding(.top, 26)
                .accessibilityHidden(true)
        }
        .multilineTextAlignment(.center)
    }

    private var eyebrow: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: palette.gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: presentation.lateNight ? "moon.fill" : "pause.fill")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(.white)
            }
            .frame(width: 20, height: 20)
            .shadow(color: palette.gradient[1].opacity(0.4), radius: 6, y: 1)
            Text(presentation.eyebrow.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .tracking(1.6)
                .foregroundStyle(.secondary)
        }
        .padding(.leading, 6)
        .padding(.trailing, 14)
        .padding(.vertical, 6)
        .background(Capsule(style: .continuous).fill(Color.primary.opacity(isDark ? 0.08 : 0.05)))
        .overlay(Capsule(style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
    }

    @ViewBuilder
    private var headline: some View {
        switch presentation.headline {
        case .quote(let quote) where quote.isHouseLine:
            Text(quote.resolvedText(starterMinutes: presentation.starterMinutes))
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        case .quote(let quote):
            VStack(spacing: 18) {
                Text("“\(quote.text)”")
                    .font(.system(size: quote.text.count > 80 ? 38 : 46, weight: .regular, design: .serif))
                    .lineSpacing(6)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 4) {
                    Text("\(quote.author)  ·  \(Text(quote.source).italic())")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                    if let note = quote.attributionNote {
                        Text(note.prefix(1).uppercased() + note.dropFirst())
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        case .why(let line):
            VStack(spacing: 16) {
                Label("Your why", systemImage: "heart.fill")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(palette.gradient[0])
                Text(line)
                    .font(.system(size: 44, weight: .regular, design: .serif))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case nil:
            Text(presentation.fallbackLine)
                .font(.system(size: 46, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func factPill(_ fact: String) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color.orange)
                .frame(width: 7, height: 7)
                .shadow(color: .orange.opacity(0.6), radius: 4)
            Text(fact)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary.opacity(0.88))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(Capsule(style: .continuous).fill(Color.primary.opacity(isDark ? 0.08 : 0.06)))
        .overlay(Capsule(style: .continuous).strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5))
    }

    private var primaryButton: some View {
        Button(action: onStart) {
            HStack(spacing: 10) {
                Image(systemName: "play.fill")
                    .font(.system(size: 14, weight: .bold))
                Text(presentation.primaryTitle)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                Text("⏎")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.white.opacity(0.18)))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 30)
            .frame(height: 54)
            .background(
                Capsule(style: .continuous)
                    .fill(LinearGradient(colors: palette.gradient, startPoint: .leading, endPoint: .trailing))
                    .brightness(primaryHovered ? 0.06 : 0)
            )
            .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.22), lineWidth: 0.5))
            .shadow(color: palette.gradient[1].opacity(0.42), radius: 16, y: 6)
            .scaleEffect(primaryHovered && !reduceMotion ? 1.02 : 1)
            .animation(.easeOut(duration: 0.15), value: primaryHovered)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.defaultAction)
        .onHover { primaryHovered = $0 }
        .accessibilityLabel(presentation.primaryTitle)
    }

    private var secondaryRow: some View {
        HStack(spacing: 6) {
            SecondaryPauseButton(title: CoachPauseScreenPresentation.realBreakTitle, symbol: "cup.and.saucer", action: onRealBreak)
            Text("·").foregroundStyle(.tertiary).accessibilityHidden(true)
            SecondaryPauseButton(title: CoachPauseScreenPresentation.doneTitle, symbol: "moon.zzz", action: onDone)
        }
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.primary.opacity(0.08)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .opacity(closeVisible ? 1 : 0)
        .allowsHitTesting(closeVisible)
        .accessibilityLabel("Close")
        .accessibilityHidden(!closeVisible)
    }
}

private struct SecondaryPauseButton: View {
    let title: String
    let symbol: String
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(hovered ? .primary : .secondary)
                .padding(.horizontal, 14)
                .frame(minHeight: 34)
                .background(Capsule(style: .continuous).fill(Color.primary.opacity(hovered ? 0.08 : 0)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

/// A stand-in desktop for evidence renders: a wallpaper and a video app window behind the dim.
private struct EvidenceDesktop: View {
    let isDark: Bool

    var body: some View {
        ZStack {
            LinearGradient(
                colors: isDark ? [Color(hex: 0x1B2236), Color(hex: 0x2A1F33)] : [Color(hex: 0xDCE6F5), Color(hex: 0xF3E6EE)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(hex: 0x0F0F0F))
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 14) {
                        RoundedRectangle(cornerRadius: 6).fill(Color(hex: 0xE5352B)).frame(width: 70, height: 18)
                        RoundedRectangle(cornerRadius: 8).fill(Color(hex: 0x2A2A2A)).frame(height: 300)
                        HStack(spacing: 14) {
                            ForEach(0..<4, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 8).fill(Color(hex: 0x262626)).frame(height: 90)
                            }
                        }
                    }
                    .padding(22)
                }
                .padding(.horizontal, 140)
                .padding(.vertical, 90)
                .shadow(color: .black.opacity(0.35), radius: 30, y: 12)
        }
    }
}

/// Live content: reads the presentation from `TimerViewModel`.
struct PauseScreenHostView: View {
    @Environment(TimerViewModel.self) private var timerVM

    var body: some View {
        if let presentation = timerVM.pauseScreen {
            PauseScreenView(
                presentation: presentation,
                onStart: { timerVM.performPauseScreenExit(.startStarter) },
                onRealBreak: { timerVM.performPauseScreenExit(.realBreak) },
                onDone: { timerVM.performPauseScreenExit(.doneForToday) },
                onEscape: { timerVM.performPauseScreenExit(.escape) },
                onClose: { timerVM.performPauseScreenExit(.close) }
            )
            .id(presentation.id)
        }
    }
}
