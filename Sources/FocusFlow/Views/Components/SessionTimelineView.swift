import SwiftUI

struct SessionTimelineView: View {
    let sessions: [FocusSession]
    @State private var editingSession: FocusSession? = nil

    var body: some View {
        if sessions.isEmpty {
            emptyState
        } else {
            VStack(spacing: 0) {
                ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                    sessionRow(session)

                    if index != sessions.count - 1 {
                        Divider()
                            .padding(.leading, 52)
                            .padding(.vertical, 2)
                    }
                }
            }
            .sheet(item: $editingSession) { session in
                SessionEditView(session: session)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "timer")
                .font(.title2)
                .foregroundStyle(.tertiary)
            Text("No sessions yet today")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
    }

    private func sessionRow(_ session: FocusSession) -> some View {
        Button {
            editingSession = session
        } label: {
            HStack(spacing: 12) {
                // Project icon badge
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(sessionColor(session).opacity(0.15))
                        .frame(width: 38, height: 38)
                    Image(systemName: session.project?.icon ?? "timer")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(sessionColor(session))
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(session.label)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(LiquidDesignTokens.Surface.onSurface)
                            .lineLimit(1)

                        if session.completed {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(.green)
                        }
                    }

                    HStack(spacing: 4) {
                        Text(session.startedAt.formatted(date: .omitted, time: .shortened))
                        if let end = session.endedAt {
                            Text("–")
                            Text(end.formatted(date: .omitted, time: .shortened))
                        }
                        Text("·")
                        Text("\(Int(session.actualDuration / 60))m")
                            .monospacedDigit()

                        if !session.completed {
                            Text("· incomplete")
                                .foregroundStyle(.orange)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                if let mood = session.mood {
                    Image(systemName: mood.icon)
                        .font(.system(size: 12))
                        .foregroundStyle(moodColor(mood))
                        .padding(.trailing, 4)
                }

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func sessionColor(_ session: FocusSession) -> Color {
        if let colorName = session.project?.color {
            return colorFromName(colorName)
        }
        return .blue
    }

    private func colorFromName(_ name: String) -> Color {
        switch name {
        case "blue": .blue
        case "indigo": .indigo
        case "purple": .purple
        case "pink": .pink
        case "red": .red
        case "orange": .orange
        case "yellow": .yellow
        case "green": .green
        case "teal": .teal
        case "mint": .mint
        default: .blue
        }
    }

    private func moodColor(_ mood: FocusMood) -> Color {
        switch mood {
        case .distracted: .orange
        case .neutral: .secondary
        case .focused: .blue
        case .deepFocus: .purple
        }
    }
}
