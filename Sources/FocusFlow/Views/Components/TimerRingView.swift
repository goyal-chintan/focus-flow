import SwiftUI

struct TimerRingView: View {
    let progress: Double
    let timeString: String
    let label: String
    let state: TimerState

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.05))
                .frame(width: 188, height: 188)

            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: 14)

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
                    style: StrokeStyle(lineWidth: 14, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.8), value: progress)

            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                .frame(width: 156, height: 156)

            VStack(spacing: FFSpacing.xs) {
                Text(timeString)
                    .font(FFType.heroTimer)
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText(countsDown: true))

                Text(label)
                    .font(FFType.heroLabel)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(1.8)
            }
        }
        .frame(width: 220, height: 220)
    }

    private var ringColor: Color {
        switch state {
        case .focusing: FFColor.focus
        case .paused: FFColor.warning
        case .onBreak(let type): type == .longBreak ? FFColor.deepFocus : FFColor.success
        case .idle: .secondary.opacity(0.3)
        }
    }
}
