import SwiftUI

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(height: 28)

            Text(value)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .contentTransition(.numericText())
                .animation(.smooth, value: value)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}
