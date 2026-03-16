import SwiftUI

struct TimerRingView: View {
    let progress: Double
    let timeString: String
    let label: String
    let state: TimerState
    @State private var isBreathing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.05))
                .frame(width: 164, height: 164)
                .scaleEffect(state == .focusing && isBreathing ? 1.04 : 1.0)
                .opacity(state == .focusing && isBreathing ? 0.85 : 1.0)

            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: 12)

            Circle()
                .trim(from: 0, to: max(0.001, progress))
                .stroke(
                    AngularGradient(
                        colors: [
                            ringColor.opacity(0.35),
                            ringColor,
                            ringColor.opacity(0.55)
                        ],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.8), value: progress)
                .animation(FFMotion.section, value: state)

            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                .frame(width: 136, height: 136)

            VStack(spacing: FFSpacing.xs) {
                Text(timeString)
                    .font(.system(size: 44, weight: .ultraLight, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(FFMotion.control, value: timeString)

                Text(label)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(1.5)
                    .contentTransition(.interpolate)
            }
        }
        .frame(width: 184, height: 184)
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
