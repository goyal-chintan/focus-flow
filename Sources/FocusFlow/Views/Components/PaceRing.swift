import SwiftUI

/// The goal ring: today's own work against the day's target, drawn like the running timer's ring
/// (a spectral blue sweep with a soft glow and a lit tip; green once the goal is met). Pace is not
/// painted on the ring: `PaceDot` beside it says on pace / behind / at risk (6 Nov 2026: a ring
/// filled orange or red with a halo looked cheap next to the timer).
struct PaceRing: View {
    let done: TimeInterval
    let target: TimeInterval
    let tier: CoachGoalPacing.Tier
    var size: CGFloat = 64
    var lineWidth: CGFloat = 6
    /// Inside the ring: "50m / of 2h" (popover) or the percent (Today).
    var showsTime = true

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var reveal = 0.0

    private var fraction: Double { target > 0 ? min(1, done / target) : 0 }
    private var isMet: Bool { target > 0 && done >= target }

    /// The timer's focusing sweep, and a green one once the goal is met.
    private var sweep: [Color] {
        isMet
            ? [Color(hex: 0x1F7A4D), Color(hex: 0x3DA86A), Color(hex: 0x7FD6A0)]
            : [Color(hex: 0x3A4F85), Color(hex: 0x5B96F8), Color(hex: 0x7DB4FF)]
    }

    private var glow: Color { isMet ? Color(hex: 0x3DA86A) : Color(hex: 0x5B96F8) }

    static func color(_ tier: CoachGoalPacing.Tier, met: Bool) -> Color {
        if met { return FFPalette.goal }
        switch tier {
        case .goalMet, .onTrack: return FFPalette.goal
        case .nudge: return FFPalette.atRisk
        case .atRisk: return FFPalette.destructive
        case .unknown: return FFPalette.accent
        }
    }

    static func word(_ tier: CoachGoalPacing.Tier, met: Bool) -> String {
        if met { return "Goal met" }
        switch tier {
        case .goalMet: return "Goal met"
        case .onTrack: return "On pace"
        case .nudge: return "Behind"
        case .atRisk: return "At risk"
        case .unknown: return "Today"
        }
    }

    var body: some View {
        let shown = max(0.001, fraction * reveal)
        ZStack {
            // Track: a quiet groove, lighter in the dark.
            Circle()
                .stroke(Color.primary.opacity(colorScheme == .dark ? 0.09 : 0.07), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: shown)
                .stroke(
                    // A met ring is a whole circle: one even sweep, no seam at the top.
                    isMet
                        ? AngularGradient(colors: [sweep[1], sweep[2], sweep[1], sweep[0], sweep[1]], center: .center)
                        : AngularGradient(colors: sweep, center: .center, startAngle: .degrees(0), endAngle: .degrees(360 * max(shown, 0.05))),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: glow.opacity(0.45), radius: lineWidth * 0.9)
            // The lit tip: where today has got to.
            if fraction > 0.02, !isMet {
                Circle()
                    .fill(.white)
                    .frame(width: lineWidth * 0.62, height: lineWidth * 0.62)
                    .shadow(color: glow.opacity(0.9), radius: lineWidth * 0.8)
                    .offset(y: -(size - lineWidth) / 2)
                    .rotationEffect(.degrees(360 * shown))
            }
            center
        }
        .frame(width: size, height: size)
        .onAppear {
            guard reveal == 0 else { return }
            if reduceMotion { reveal = 1 } else { withAnimation(.smooth(duration: 0.9)) { reveal = 1 } }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Self.word(tier, met: isMet)): \(FFFormat.duration(done)) of \(FFFormat.duration(target))")
    }

    @ViewBuilder
    private var center: some View {
        if isMet {
            Image(systemName: "checkmark")
                .font(.system(size: size * 0.26, weight: .semibold))
                .foregroundStyle(FFPalette.goal)
        } else if showsTime {
            VStack(spacing: 0) {
                Text(FFFormat.duration(done))
                    .font(.system(size: size * 0.22, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("of \(FFFormat.compactDuration(target))")
                    .font(.system(size: size * 0.155, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, lineWidth + 2)
        } else {
            Text(FFFormat.percent(fraction))
                .font(.system(size: size * 0.2, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
    }
}

/// The pace, as a small lit dot: green on pace or met, orange behind, red at risk. It blinks
/// slowly while you're behind (steady under Reduce Motion), like the notch's coach dot.
struct PaceDot: View {
    let tier: CoachGoalPacing.Tier
    let met: Bool
    var size: CGFloat = 8

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.motionPaused) private var motionPaused
    @State private var on = false

    private var behind: Bool { !met && (tier == .nudge || tier == .atRisk) }

    var body: some View {
        let color = PaceRing.color(tier, met: met)
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .shadow(color: color.opacity(behind && on ? 0.95 : 0.5), radius: behind && on ? size * 0.8 : size * 0.35)
            .opacity(behind && !on ? 0.45 : 1)
            .onAppear { blink() }
            .onChange(of: behind) { _, _ in blink() }
            .onChange(of: motionPaused) { _, _ in blink() }
            .accessibilityLabel(PaceRing.word(tier, met: met))
    }

    private func blink() {
        // Setting `on` without an animation also ends a running repeatForever.
        guard behind, !reduceMotion, !motionPaused else { on = false; return }
        withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { on = true }
    }
}
