import SwiftUI

struct TimerRingView: View {
    let progress: Double
    let timeString: String
    let label: String
    let state: TimerState
    @State private var isBreathing = false

    private let ringSize: CGFloat = 184
    private let strokeWidth: CGFloat = 5

    var body: some View {
        ZStack {
            // Subtle background disc
            Circle()
                .fill(Color.primary.opacity(0.03))
                .frame(width: ringSize, height: ringSize)
                .scaleEffect(state == .focusing && isBreathing ? 1.06 : 1.0)
                .opacity(state == .focusing && isBreathing ? 0.7 : 1.0)

            // Track ring
            Circle()
                .stroke(Color.primary.opacity(0.06), lineWidth: strokeWidth)

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
                    style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: ringColor.opacity(0.45), radius: 10, y: 0)
                .animation(.easeInOut(duration: 0.8), value: progress)
                .animation(FFMotion.content, value: state)

            // Center text
            VStack(spacing: FFSpacing.xs) {
                Text(timeString)
                    .font(FFType.heroTimer)
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(FFMotion.control, value: timeString)

                Text(label)
                    .font(FFType.heroLabel)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(1.2)
                    .contentTransition(.interpolate)
            }
        }
        .frame(width: ringSize, height: ringSize)
        .onAppear {
            updateBreathing(for: state)
        }
        .onChange(of: state) { _, newState in
            updateBreathing(for: newState)
        }
    }

    private var ringColor: Color {
        switch state {
        case .focusing: FFColor.focus
        case .paused: FFColor.warning
        case .onBreak(let type): type == .longBreak ? FFColor.deepFocus : FFColor.success
        case .idle: .secondary.opacity(0.3)
        }
    }

    private func updateBreathing(for state: TimerState) {
        if state == .focusing {
            isBreathing = false
            withAnimation(FFMotion.breathing) {
                isBreathing = true
            }
        } else {
            withAnimation(FFMotion.control) {
                isBreathing = false
            }
        }
    }
}
