import SwiftUI

struct TimerRingView: View {
    @Environment(FFDesignTokens.self) private var tokens
    let progress: Double
    let timeString: String
    let label: String
    let state: TimerState
    @State private var isBreathing = false

    var body: some View {
        let r = tokens.ring

        return ZStack {
            // Subtle background disc
            Circle()
                .fill(Color.primary.opacity(r.backgroundDiscOpacity))
                .frame(width: r.size, height: r.size)
                .scaleEffect(state == .focusing && isBreathing ? 1.06 : 1.0)
                .opacity(state == .focusing && isBreathing ? 0.7 : 1.0)

            // Track ring
            Circle()
                .stroke(Color.primary.opacity(r.trackOpacity), lineWidth: r.strokeWidth)

            // Progress arc with glow
            Circle()
                .trim(from: 0, to: max(0.001, progress))
                .stroke(
                    AngularGradient(
                        colors: [
                            ringColor.opacity(0.3),
                            ringColor,
                            ringColor.opacity(0.5)
                        ],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: r.strokeWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: ringColor.opacity(r.glowOpacity), radius: r.glowRadius, y: 0)
                .animation(.easeInOut(duration: 0.8), value: progress)
                .animation(tokens.motion.content, value: state)

            // Center text
            VStack(spacing: tokens.spacing.xs) {
                Text(timeString)
                    .font(r.timerFont)
                    .monospacedDigit()
                    .tracking(r.digitTracking)
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(tokens.motion.control, value: timeString)

                Text(label)
                    .font(r.labelFont)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(r.labelTracking)
                    .contentTransition(.interpolate)
            }
        }
        .frame(width: r.size, height: r.size)
        .onAppear {
            updateBreathing(for: state)
        }
        .onChange(of: state) { _, newState in
            updateBreathing(for: newState)
        }
    }

    private var ringColor: Color {
        switch state {
        case .focusing: tokens.color.focus
        case .paused: tokens.color.warning
        case .onBreak(let type): type == .longBreak ? tokens.color.deepFocus : tokens.color.success
        case .idle: .secondary.opacity(0.3)
        }
    }

    private func updateBreathing(for state: TimerState) {
        if state == .focusing {
            isBreathing = false
            withAnimation(tokens.motion.breathing) {
                isBreathing = true
            }
        } else {
            withAnimation(tokens.motion.control) {
                isBreathing = false
            }
        }
    }
}
