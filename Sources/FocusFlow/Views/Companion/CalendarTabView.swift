import SwiftUI
import SwiftData

struct CalendarTabView: View {
    @Query(sort: \FocusSession.startedAt) private var allSessions: [FocusSession]
    @Query private var allSettings: [AppSettings]
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var displayedMonth: Date = Date()

    private var calendar: Calendar { Calendar.current }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerSection
                monthGridSection
                dayDetailSection
            }
            .padding(24)
        }
        .background(.ultraThinMaterial)
        .animation(FFMotion.section, value: selectedDate)
        .animation(FFMotion.section, value: displayedMonth)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Calendar")
                    .font(.system(size: 42, weight: .light))
                    .foregroundStyle(LiquidDesignTokens.Surface.onSurface)

                Spacer()

                // Month navigation
                HStack(spacing: 12) {
                    Button {
                        withAnimation(FFMotion.section) {
                            displayedMonth = calendar.date(byAdding: .month, value: -1, to: displayedMonth)!
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 30, height: 30)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Text(displayedMonth.formatted(.dateTime.month(.wide).year()))
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .frame(minWidth: 140)

                    Button {
                        withAnimation(FFMotion.section) {
                            displayedMonth = calendar.date(byAdding: .month, value: 1, to: displayedMonth)!
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 30, height: 30)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        withAnimation(FFMotion.section) {
                            displayedMonth = Date()
                            selectedDate = calendar.startOfDay(for: Date())
                        }
                    } label: {
                        Text("Today")
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                }
            }

            if calendarSyncEnabled {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.icloud.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.green)
                    Text("Syncing to \(calendarName)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var calendarSyncEnabled: Bool {
        allSettings.first?.calendarIntegrationEnabled ?? false
    }

    private var calendarName: String {
        allSettings.first?.calendarName ?? "FocusFlow"
    }

    // MARK: - Month Grid

    private var monthGridSection: some View {
        LiquidGlassPanel {
            VStack(spacing: 0) {
                // Day-of-week headers
                HStack(spacing: 0) {
                    ForEach(calendar.shortWeekdaySymbols, id: \.self) { day in
                        Text(day)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.bottom, 8)

                // Day grid
                let weeks = monthWeeks
                ForEach(weeks.indices, id: \.self) { weekIdx in
                    HStack(spacing: 0) {
                        ForEach(weeks[weekIdx], id: \.self) { date in
                            if let date {
                                dayCell(date)
                            } else {
                                Color.clear
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    private func dayCell(_ date: Date) -> some View {
        let isToday = calendar.isDateInToday(date)
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
        let focusMinutes = focusMinutesForDay(date)
        let hasSessions = focusMinutes > 0
        let dailyGoal = allSettings.first?.dailyFocusGoal ?? 7200
        let goalProgress = min(1.0, (focusMinutes * 60) / dailyGoal)
        let isCurrentMonth = calendar.isDate(date, equalTo: displayedMonth, toGranularity: .month)

        return VStack(spacing: 3) {
            Text("\(calendar.component(.day, from: date))")
                .font(.system(size: 13, weight: isToday ? .bold : .medium, design: .rounded))
                .foregroundStyle(
                    isSelected ? AnyShapeStyle(.white) :
                    isToday ? AnyShapeStyle(LiquidDesignTokens.Spectral.primaryContainer) :
                    isCurrentMonth ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary)
                )

            // Focus intensity dot
            if hasSessions {
                Circle()
                    .fill(intensityColor(goalProgress))
                    .frame(width: 6, height: 6)
            } else {
                Color.clear.frame(width: 6, height: 6)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LiquidDesignTokens.Spectral.primaryContainer)
            } else if isToday {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(LiquidDesignTokens.Spectral.primaryContainer.opacity(0.4), lineWidth: 1.5)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(FFMotion.control) {
                selectedDate = date
            }
        }
        .accessibilityLabel("\(date.formatted(.dateTime.month(.wide).day())), \(hasSessions ? "\(Int(focusMinutes)) minutes focused" : "no sessions")")
    }

    private func intensityColor(_ progress: Double) -> Color {
        if progress >= 1.0 { return Color(hex: 0x3DA86A) }
        if progress >= 0.5 { return Color(hex: 0x3DA86A).opacity(0.6) }
        return Color(hex: 0x3DA86A).opacity(0.3)
    }

    // MARK: - Calendar Math

    private var monthWeeks: [[Date?]] {
        let firstOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: displayedMonth))!
        let range = calendar.range(of: .day, in: .month, for: firstOfMonth)!
        let firstWeekday = calendar.component(.weekday, from: firstOfMonth) - calendar.firstWeekday
        let offset = (firstWeekday + 7) % 7

        var weeks = [[Date?]]()
        var currentWeek = [Date?]()

        // Leading blanks
        for _ in 0..<offset {
            currentWeek.append(nil)
        }

        for day in range {
            let date = calendar.date(byAdding: .day, value: day - 1, to: firstOfMonth)!
            currentWeek.append(date)
            if currentWeek.count == 7 {
                weeks.append(currentWeek)
                currentWeek = []
            }
        }

        // Trailing blanks
        if !currentWeek.isEmpty {
            while currentWeek.count < 7 { currentWeek.append(nil) }
            weeks.append(currentWeek)
        }

        return weeks
    }

    // MARK: - Day Detail

    private var dayDetailSection: some View {
        LiquidGlassPanel {
            VStack(alignment: .leading, spacing: 16) {
                // Day header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(selectedDate.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                            .font(.system(size: 18, weight: .semibold, design: .rounded))

                        let mins = focusMinutesForDay(selectedDate)
                        Text(mins > 0 ? "\(Int(mins))m focused · \(sessionsForDay(selectedDate).count) session\(sessionsForDay(selectedDate).count == 1 ? "" : "s")" : "No focus sessions")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // Goal progress ring
                    let dailyGoal = allSettings.first?.dailyFocusGoal ?? 7200
                    let progress = min(1.0, (focusMinutesForDay(selectedDate) * 60) / dailyGoal)
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.08), lineWidth: 4)
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(
                                progress >= 1.0 ? Color(hex: 0x3DA86A) : LiquidDesignTokens.Spectral.primaryContainer,
                                style: StrokeStyle(lineWidth: 4, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                        Text("\(Int(progress * 100))%")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 44, height: 44)
                }

                let sessions = sessionsForDay(selectedDate)
                if sessions.isEmpty {
                    emptyDayView
                } else {
                    sessionTimeline(sessions)
                    achievementsForDay(sessions)
                }
            }
            .padding(16)
        }
    }

    private var emptyDayView: some View {
        VStack(spacing: 8) {
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(.tertiary)
            Text("No sessions recorded")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private func sessionTimeline(_ sessions: [FocusSession]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            TrackedLabel(text: "Timeline", tracking: 1.8)
                .padding(.bottom, 8)

            ForEach(sessions, id: \.id) { session in
                HStack(spacing: 10) {
                    // Time column
                    VStack(spacing: 2) {
                        Text(session.startedAt.formatted(.dateTime.hour().minute()))
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        if let end = session.endedAt {
                            Text(end.formatted(.dateTime.hour().minute()))
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(.tertiary)
                                .monospacedDigit()
                        }
                    }
                    .frame(width: 50, alignment: .trailing)

                    // Timeline bar
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(session.type == .focus ?
                              LiquidDesignTokens.Spectral.primaryContainer :
                              Color(hex: 0x3DA86A))
                        .frame(width: 3, height: 36)

                    // Session info
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(session.label)
                                .font(.system(size: 13, weight: .semibold))

                            if session.completed {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.green)
                            }
                        }

                        Text("\(Int(session.actualDuration / 60))m · \(session.type.displayName)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // Mood indicator
                    if let mood = session.mood {
                        Image(systemName: moodIcon(mood))
                            .font(.system(size: 12))
                            .foregroundStyle(moodColor(mood))
                    }
                }
                .padding(.vertical, 6)
            }
        }
    }

    private func achievementsForDay(_ sessions: [FocusSession]) -> some View {
        let achievements = sessions
            .compactMap(\.achievement)
            .filter { !$0.isEmpty }
            .flatMap { $0.components(separatedBy: .newlines) }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        return Group {
            if !achievements.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    TrackedLabel(text: "Achievements", tracking: 1.8)
                        .padding(.bottom, 4)

                    ForEach(Array(achievements.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                                .padding(.top, 2)
                            Text(item)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Data Helpers

    private func sessionsForDay(_ date: Date) -> [FocusSession] {
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
        return allSessions.filter { session in
            let sessionEnd = session.endedAt ?? session.startedAt.addingTimeInterval(session.actualDuration)
            return sessionEnd > dayStart && session.startedAt < dayEnd
        }.sorted { $0.startedAt < $1.startedAt }
    }

    private func focusMinutesForDay(_ date: Date) -> Double {
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
        return allSessions.filter { $0.type == .focus }.reduce(0.0) { sum, session in
            let sessionEnd = session.endedAt ?? session.startedAt.addingTimeInterval(session.actualDuration)
            guard sessionEnd > dayStart && session.startedAt < dayEnd else { return sum }
            let overlapStart = max(session.startedAt, dayStart)
            let overlapEnd = min(sessionEnd, dayEnd)
            return sum + max(0, overlapEnd.timeIntervalSince(overlapStart)) / 60
        }
    }

    private func moodIcon(_ mood: FocusMood) -> String {
        switch mood {
        case .distracted: "cloud.fog.fill"
        case .neutral: "minus.circle"
        case .focused: "scope"
        case .deepFocus: "sparkles"
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
