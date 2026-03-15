import SwiftUI

struct TimerRingView: View {
    let progress: Double
    let timeString: String
    let label: String
    let state: TimerState

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: 6)

            Circle()
                .trim(from: 0, to: max(0.001, progress))
                .stroke(ringColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.8), value: progress)

            VStack(spacing: 4) {
                Text(timeString)
                    .font(.system(size: 44, weight: .ultraLight, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))

                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(1.5)
            }
        }
        .frame(width: 170, height: 170)
    }

    private var ringColor: Color {
        switch state {
        case .focusing: .blue
        case .paused: .blue.opacity(0.4)
        case .onBreak(let type): type == .longBreak ? .purple : .green
        case .idle: .secondary.opacity(0.3)
        }
    }
}
