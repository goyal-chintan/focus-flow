import SwiftUI

// Parts of the welcome tour (onboarding design §4).

/// A soft glow in the #1 project's colour behind the tour. It drifts slowly unless motion is reduced.
struct OnboardingBackdrop: View {
    let tint: Color
    let animated: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            FFPalette.windowBackground
            if animated {
                TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                    glow(phase: context.date.timeIntervalSinceReferenceDate)
                }
            } else {
                glow(phase: 0)
            }
        }
        .ignoresSafeArea()
    }

    /// Radial gradients rather than `.blur`: the same soft edge everywhere, and cheap to redraw.
    private func glow(phase: Double) -> some View {
        let strength = colorScheme == .dark ? 0.42 : 0.26
        return ZStack {
            RadialGradient(colors: [tint.opacity(strength), tint.opacity(0)], center: .center, startRadius: 0, endRadius: 300)
                .frame(width: 600, height: 600)
                .offset(x: -190 + 26 * sin(phase / 3.1), y: -260 + 18 * cos(phase / 3.7))
            RadialGradient(colors: [Color.accentColor.opacity(strength * 0.6), Color.accentColor.opacity(0)], center: .center, startRadius: 0, endRadius: 260)
                .frame(width: 520, height: 520)
                .offset(x: 230 + 22 * cos(phase / 4.3), y: -200 + 20 * sin(phase / 2.9))
        }
        .animation(.smooth(duration: 0.6), value: tint)
    }
}

/// Five segments; the current one fills with the tint.
struct OnboardingProgress: View {
    let step: OnboardingStep
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingStep.allCases, id: \.self) { item in
                Capsule()
                    .fill(item <= step ? tint : FFPalette.track)
                    .frame(width: item == step ? 34 : 18, height: 5)
            }
        }
        .animation(.snappy(duration: 0.35), value: step)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(step.rawValue + 1) of \(OnboardingStep.allCases.count)")
    }
}

/// A capsule choice. Selected chips fill with the tint.
struct OnboardingChip: View {
    let title: String
    var symbol: String?
    let selected: Bool
    var tint: Color = .accentColor
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 13, weight: selected ? .semibold : .medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 30)
            .fixedSize()
            .foregroundStyle(selected ? tint : .primary)
            .background(
                Capsule().fill(selected ? tint.opacity(0.16) : (hovering ? FFPalette.rowHover : FFPalette.sectionFill))
            )
            .overlay(Capsule().strokeBorder(selected ? tint.opacity(0.55) : FFPalette.hairline, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.snappy(duration: 0.2), value: selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A card surface for tour content (not glass: glass stays on controls).
struct OnboardingCard<Content: View>: View {
    var padding: CGFloat = FFSpace.l
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: FFRadius.hero, style: .continuous).fill(FFPalette.sectionFill))
            .overlay(RoundedRectangle(cornerRadius: FFRadius.hero, style: .continuous).strokeBorder(FFPalette.hairline, lineWidth: 1))
    }
}

/// A small caps label above a group of choices.
struct OnboardingLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(.secondary)
    }
}

/// The welcome ring: it fills to a 5-minute block and counts "5 min" in the middle.
struct OnboardingHeroRing: View {
    let tint: Color
    let animated: Bool

    @State private var fill: CGFloat = 0
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.12))
                .scaleEffect(pulse ? 1.12 : 0.96)
                .opacity(pulse ? 0 : 1)
            Circle().stroke(FFPalette.track, lineWidth: 8)
            Circle()
                .trim(from: 0, to: fill)
                .stroke(
                    AngularGradient(colors: [tint.opacity(0.55), tint], center: .center, startAngle: .degrees(-90), endAngle: .degrees(270)),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: -2) {
                Text("5")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("min")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 128, height: 128)
        .onAppear {
            guard animated else { fill = 1; return }
            withAnimation(.smooth(duration: 1.4).delay(0.2)) { fill = 1 }
            withAnimation(.easeOut(duration: 2.2).repeatForever(autoreverses: false).delay(1.4)) { pulse = true }
        }
        .accessibilityHidden(true)
    }
}

/// A miniature menu bar with the notch island, so the notch step shows what you'll get.
struct OnboardingNotchPreview: View {
    let tint: Color
    let enabled: Bool
    let animated: Bool

    @State private var progress: CGFloat = 0.08

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(red: 0.36, green: 0.42, blue: 0.62), Color(red: 0.75, green: 0.55, blue: 0.62)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Rectangle().fill(.white.opacity(0.28)).frame(height: 26)
            HStack {
                Text("  Finder  File  Edit").font(.system(size: 11, weight: .medium))
                Spacer()
                Text("12:30  ").font(.system(size: 11, weight: .medium))
            }
            .frame(height: 26)
            .foregroundStyle(.black.opacity(0.75))
            island
        }
        .frame(height: 58)
        .clipShape(RoundedRectangle(cornerRadius: FFRadius.section, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: FFRadius.section, style: .continuous).strokeBorder(FFPalette.hairline, lineWidth: 1))
        .onAppear {
            guard animated else { progress = 0.35; return }
            withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) { progress = 1 }
        }
        .accessibilityHidden(true)
    }

    private var island: some View {
        HStack(spacing: 0) {
            ZStack {
                Circle().stroke(.white.opacity(0.18), lineWidth: 2.5)
                Circle().trim(from: 0, to: progress).stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round)).rotationEffect(.degrees(-90))
            }
            .frame(width: 13, height: 13)
            .frame(width: 44)
            Spacer().frame(width: 92)
            Text("4:59")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .frame(width: 44)
        }
        .frame(height: 26)
        .background(UnevenRoundedRectangle(bottomLeadingRadius: 10, bottomTrailingRadius: 10, style: .continuous).fill(.black))
        .opacity(enabled ? 1 : 0)
        .overlay {
            // With the companion off, only the hardware notch remains.
            UnevenRoundedRectangle(bottomLeadingRadius: 9, bottomTrailingRadius: 9, style: .continuous)
                .fill(.black)
                .frame(width: 92, height: 26)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: enabled)
    }
}

/// A short burst of confetti from the top. Draws nothing once it has fallen.
struct OnboardingConfetti: View {
    let colors: [Color]
    var duration: Double = 2.2

    @State private var start = Date()

    private struct Piece {
        let x: Double, drift: Double, speed: Double, spin: Double, size: Double, colorIndex: Int, delay: Double
    }

    private let pieces: [Piece] = {
        var generator = OnboardingRandom(seed: 7)
        return (0..<70).map { index in
            Piece(
                x: Double.random(in: 0...1, using: &generator),
                drift: Double.random(in: -60...60, using: &generator),
                speed: Double.random(in: 240...420, using: &generator),
                spin: Double.random(in: -6...6, using: &generator),
                size: Double.random(in: 5...9, using: &generator),
                colorIndex: index,
                delay: Double.random(in: 0...0.35, using: &generator)
            )
        }
    }()

    var body: some View {
        TimelineView(.animation) { context in
            Canvas { canvas, size in
                let elapsed = context.date.timeIntervalSince(start)
                guard elapsed < duration + 0.4 else { return }
                for piece in pieces {
                    let t = elapsed - piece.delay
                    guard t > 0 else { continue }
                    let y = -20 + piece.speed * t + 140 * t * t
                    guard y < size.height + 20 else { continue }
                    let x = piece.x * size.width + piece.drift * t
                    let fade = max(0, min(1, (duration - t) / 0.5))
                    var rect = canvas
                    rect.translateBy(x: x, y: y)
                    rect.rotate(by: .radians(piece.spin * t))
                    rect.opacity = fade
                    let shape = Path(roundedRect: CGRect(x: -piece.size / 2, y: -piece.size / 4, width: piece.size, height: piece.size / 2), cornerRadius: 1)
                    rect.fill(shape, with: .color(colors[piece.colorIndex % colors.count]))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Deterministic randomness so the confetti looks the same in captures and tests.
struct OnboardingRandom: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 0x9E37_79B9_7F4A_7C15 | 1 }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
