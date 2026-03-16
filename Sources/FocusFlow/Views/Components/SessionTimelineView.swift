import SwiftUI

struct SessionTimelineView: View {
    let sessions: [FocusSession]
    @State private var editingSession: FocusSession? = nil

    var body: some View {
        if sessions.isEmpty {
            PremiumSurface(style: .inset, alignment: .center) {
                Image(systemName: "timer")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(.tertiary)
                Text("No sessions yet today")
                    .font(FFType.callout)
                    .foregroundStyle(.secondary)
                Text("Sessions you complete today will appear here.")
                    .font(FFType.meta)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        } else {
            LazyVStack(spacing: FFSpacing.sm) {
                ForEach(sessions) { session in
                    Button {
                        editingSession = session
                    } label: {
                        HStack(spacing: FFSpacing.md) {
                            Circle()
                                .fill(session.completed ? FFColor.success : FFColor.warning)
                                .frame(width: 10, height: 10)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(session.label)
                                    .font(FFType.body.weight(.medium))
                                HStack(spacing: FFSpacing.xs) {
                                    Text(session.startedAt.formatted(date: .omitted, time: .shortened))
                                    Text("\u{00B7}")
                                    Text("\(Int(session.actualDuration / 60))m")
                                    if !session.completed {
                                        Text("\u{00B7} stopped early")
                                            .foregroundStyle(FFColor.warning)
                                    }
                                }
                                .font(FFType.meta)
                                .foregroundStyle(.secondary)
                            }

                            if let mood = session.mood {
                                Image(systemName: mood.icon)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(moodColor(mood))
                            }

                            Spacer()

                            if session.completed {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(FFColor.success)
                                    .font(.system(size: 14, weight: .semibold))
                            }
                        }
                        .padding(.horizontal, FFSpacing.md)
                        .padding(.vertical, FFSpacing.sm)
                        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: FFRadius.card, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .sheet(item: $editingSession) { session in
                SessionEditView(session: session)
            }
        }
    }

    private func moodColor(_ mood: FocusMood) -> Color {
        switch mood {
        case .distracted: FFColor.warning
        case .neutral: .secondary
        case .focused: FFColor.focus
        case .deepFocus: FFColor.deepFocus
        }
    }
}
