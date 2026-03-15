import SwiftUI

struct SessionTimelineView: View {
    let sessions: [FocusSession]
    @State private var editingSession: FocusSession? = nil

    var body: some View {
        if sessions.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "timer")
                    .font(.largeTitle)
                    .foregroundStyle(.tertiary)
                Text("No sessions yet today")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        } else {
            LazyVStack(spacing: 0) {
                ForEach(sessions) { session in
                    Button {
                        editingSession = session
                    } label: {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(session.completed ? Color.green : Color.orange)
                                .frame(width: 8, height: 8)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.label)
                                    .font(.subheadline.weight(.medium))
                                HStack(spacing: 6) {
                                    Text(session.startedAt.formatted(date: .omitted, time: .shortened))
                                    Text("\u{00B7}")
                                    Text("\(Int(session.actualDuration / 60))m")
                                    if !session.completed {
                                        Text("\u{00B7} stopped early")
                                            .foregroundStyle(.orange)
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }

                            if let mood = session.mood {
                                Image(systemName: mood.icon)
                                    .font(.caption2)
                                    .foregroundStyle(moodColor(mood))
                            }

                            Spacer()

                            if session.completed {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.caption)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)

                    if session.id != sessions.last?.id {
                        Divider()
                            .padding(.leading, 20)
                    }
                }
            }
            .sheet(item: $editingSession) { session in
                SessionEditView(session: session)
            }
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
