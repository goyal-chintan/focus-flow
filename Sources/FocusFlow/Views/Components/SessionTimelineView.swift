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

                if sessions.contains(where: { !($0.completed) && $0.endedAt == nil }) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(.green)
                            .frame(width: 6, height: 6)
                        TrackedLabel(
                            text: "Ongoing Session",
                            font: .system(size: 10, weight: .semibold),
                            color: .green,
                            tracking: 2.0
                        )
                    }
                    .padding(.top, 8)
                    .padding(.leading, 4)
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
                        .frame(width: 40, height: 40)
                    Image(systemName: session.project?.icon ?? "timer")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(sessionColor(session))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(session.label)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(LiquidDesignTokens.Surface.onSurface)
                        .lineLimit(1)

                    // Achievement or generated description
                    if let achievement = session.achievement, !achievement.isEmpty {
                        Text(achievement)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Text("\(Int(session.actualDuration / 60))m \(session.completed ? "completed" : "incomplete") session")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                // Time range on right
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 3) {
                        Text(session.startedAt.formatted(date: .omitted, time: .shortened))
                        Text("→")
                            .foregroundStyle(.tertiary)
                        if let end = session.endedAt {
                            Text(end.formatted(date: .omitted, time: .shortened))
                        }
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                    if let mood = session.mood {
                        Image(systemName: mood.icon)
                            .font(.system(size: 11))
                            .foregroundStyle(moodColor(mood))
                    }
                }
            }
            .padding(.vertical, 10)
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
