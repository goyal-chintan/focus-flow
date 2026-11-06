import SwiftUI

/// The goal ring (restored 6 Nov 2026 after phase 5 took it out): today's own work against the
/// day's target, coloured by pace so one glance says ahead or behind. Green: met or on pace.
/// Orange: behind. Red: at risk. While behind it breathes softly (still under Reduce Motion).
struct PaceRing: View {
    let done: TimeInterval
    let target: TimeInterval
    let tier: CoachGoalPacing.Tier
    var size: CGFloat = 64
    var lineWidth: CGFloat = 6
    /// Inside the ring: "50m / of 2h" (popover) or the percent (Today).
    var showsTime = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathe = false

    private var fraction: Double { target > 0 ? min(1, done / target) : 0 }
    private var isMet: Bool { target > 0 && done >= target }

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

    private var isBehind: Bool { !isMet && (tier == .nudge || tier == .atRisk) }

    var body: some View {
        let tint = Self.color(tier, met: isMet)
        ZStack {
            Circle().stroke(Color.primary.opacity(0.1), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, fraction))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if isBehind {
                Circle()
                    .stroke(tint.opacity(breathe ? 0.05 : 0.35), lineWidth: lineWidth * 2.2)
                    .scaleEffect(breathe ? 1.06 : 1)
                    .accessibilityHidden(true)
            }
            center(tint)
        }
        .frame(width: size, height: size)
        .onAppear { startBreathing() }
        .onChange(of: isBehind) { _, _ in startBreathing() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Self.word(tier, met: isMet)): \(FFFormat.duration(done)) of \(FFFormat.duration(target))")
    }

    @ViewBuilder
    private func center(_ tint: Color) -> some View {
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

    private func startBreathing() {
        guard isBehind, !reduceMotion else { breathe = false; return }
        withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { breathe = true }
    }
}
