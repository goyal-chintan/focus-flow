import SwiftUI

struct SessionTimelineView: View {
    let sessions: [FocusSession]
    @State private var editingSession: FocusSession? = nil

    var body: some View {
        if sessions.isEmpty {
            emptyState
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                    sessionRow(session, isLast: index == sessions.count - 1)

                    if index != sessions.count - 1 {
                        Divider()
                            .padding(.leading, 24)
                            .padding(.vertical, 8)
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

    private func sessionRow(_ session: FocusSession, isLast: Bool) -> some View {
        Button {
            editingSession = session
        } label: {
            HStack(alignment: .top, spacing: 10) {
                timelineIndicator(session: session, isLast: isLast)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(session.label)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)

                        if session.completed {
                            Label("Done", systemImage: "checkmark.circle.fill")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.green)
                                .labelStyle(.iconOnly)
                        }

                        Spacer(minLength: 0)

                        if let mood = session.mood {
                            Image(systemName: mood.icon)
                                .font(.caption)
                                .foregroundStyle(moodColor(mood))
                        }
                    }

                    HStack(spacing: 6) {
                        Text(session.startedAt.formatted(date: .omitted, time: .shortened))
                        Text("·")
                        Text("\(Int(session.actualDuration / 60))m")
                            .monospacedDigit()

                        if !session.completed {
                            Text("· stopped early")
                                .foregroundStyle(.orange)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }

    private func timelineIndicator(session: FocusSession, isLast: Bool) -> some View {
        VStack(spacing: 0) {
            Circle()
                .fill(session.completed ? Color.green : Color.orange)
                .frame(width: 9, height: 9)

            if !isLast {
                Rectangle()
                    .fill(.tertiary.opacity(0.4))
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)
                    .padding(.vertical, 3)
            }
        }
        .frame(width: 14)
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
