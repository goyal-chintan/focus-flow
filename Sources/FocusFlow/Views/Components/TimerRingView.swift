import SwiftUI

struct TimerRingView: View {
    let progress: Double
    let timeString: String
    let label: String
    let state: TimerState

    var body: some View {
        ZStack {
            // Track ring
            Circle()
                .stroke(lineWidth: 10)
                .foregroundStyle(.quaternary)

            // Progress ring
            Circle()
                .trim(from: 0, to: max(0, min(1, progress)))
                .stroke(
                    ringGradient,
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.smooth(duration: 0.9), value: progress)

            // Center content
            VStack(spacing: 6) {
                Text(timeString)
                    .font(.system(size: 42, weight: .thin, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.smooth, value: timeString)

                Text(label.uppercased())
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
                    .animation(.smooth, value: label)
            }
        }
        .frame(width: 180, height: 180)
    }

    private var ringColor: Color {
        switch state {
        case .focusing: .blue
        case .paused: .blue.opacity(0.5)
        case .onBreak(let type):
            type == .longBreak ? .purple : .green
        case .idle: .secondary
        }
    }

    private var ringGradient: AngularGradient {
        let color = ringColor
        return AngularGradient(
            colors: [color.opacity(0.4), color],
            center: .center,
            startAngle: .degrees(-90),
            endAngle: .degrees(-90 + 360 * max(0, min(1, progress)))
        )
    }
}
