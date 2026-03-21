import SwiftUI
import SwiftData
import OSLog
import AppKit

struct CalendarTabView: View {
    private struct MonthDayCell: Identifiable {
        let id: Int
        let date: Date?
    }

    @Query(sort: \FocusSession.startedAt) private var allSessions: [FocusSession]
    @Query private var allSettings: [AppSettings]
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var displayedMonth: Date = Date()
    @State private var reminders: [RemindersService.ReminderItem] = []
    @State private var isLoadingReminders = false
    @State private var remindersError: String?
    @State private var editingReminder: RemindersService.ReminderItem?
    @State private var reminderDraftTitle = ""
    @State private var reminderDraftNotes = ""
    @State private var reminderDraftDueDate: Date = Date()
    @State private var showReminderEditor = false
    @State private var showCreateReminder = false
    @State private var reminderLoadTask: Task<Void, Never>?

    private var calendar: Calendar { Calendar.current }
    private var settings: AppSettings? { allSettings.first }
    private static let logger = Logger(subsystem: "FocusFlow", category: "CalendarTabView")

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerSection
                monthGridSection
                dayDetailSection
                remindersSection
            }
            .padding(24)
        }
        .background(.ultraThinMaterial)
        .onAppear {
            Self.logger.debug("Calendar tab appeared. remindersEnabled=\(self.settings?.remindersIntegrationEnabled == true, privacy: .public) selectedListEmpty=\(self.settings?.selectedReminderListId.isEmpty ?? true, privacy: .public)")
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            reminderLoadTask?.cancel()
            reminderLoadTask = Task { @MainActor in await loadRemindersInternal() }
        }
        .animation(FFMotion.section, value: selectedDate)
        .animation(FFMotion.section, value: displayedMonth)
        .task { await loadReminders() }
        .onChange(of: settings?.selectedReminderListId) { _, _ in
            reminderLoadTask?.cancel()
            reminderLoadTask = Task { @MainActor in await loadRemindersInternal() }
        }
        .onChange(of: settings?.remindersIntegrationEnabled) { _, _ in
            reminderLoadTask?.cancel()
            reminderLoadTask = Task { @MainActor in await loadRemindersInternal() }
        }
        .onChange(of: selectedDate) { _, _ in
            reminderLoadTask?.cancel()
            reminderLoadTask = Task { @MainActor in await loadRemindersInternal() }
        }
        .sheet(isPresented: $showReminderEditor) {
            reminderEditorSheet(isCreating: false)
        }
        .sheet(isPresented: $showCreateReminder) {
            reminderEditorSheet(isCreating: true)
        }
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
                            shiftDisplayedMonth(by: -1)
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 30, height: 30)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Previous month")

                    Text(displayedMonth.formatted(.dateTime.month(.wide).year()))
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .frame(minWidth: 140)

                    Button {
                        withAnimation(FFMotion.section) {
                            shiftDisplayedMonth(by: 1)
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 30, height: 30)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Next month")

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
                    .accessibilityLabel("Go to today")
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
                    ForEach(Array(calendar.shortWeekdaySymbols.enumerated()), id: \.offset) { _, day in
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
                        ForEach(weeks[weekIdx]) { cell in
                            if let date = cell.date {
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
        let focusMinutes = sanitizedMinutes(focusMinutesForDay(date))
        let hasSessions = focusMinutes > 0
        let goalProgress = goalProgress(forFocusMinutes: focusMinutes)
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
        let safeProgress = progress.isFinite ? max(0, progress) : 0
        if safeProgress >= 1.0 { return Color(hex: 0x3DA86A) }
        if safeProgress >= 0.5 { return Color(hex: 0x3DA86A).opacity(0.6) }
        return Color(hex: 0x3DA86A).opacity(0.3)
    }

    // MARK: - Calendar Math

    private var monthWeeks: [[MonthDayCell]] {
        guard let firstOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: displayedMonth)),
              let range = calendar.range(of: .day, in: .month, for: firstOfMonth) else {
            return []
        }
        let firstWeekday = calendar.component(.weekday, from: firstOfMonth) - calendar.firstWeekday
        let offset = (firstWeekday + 7) % 7

        var weeks = [[MonthDayCell]]()
        var currentWeek = [MonthDayCell]()
        var nextCellID = 0

        // Leading blanks
        for _ in 0..<offset {
            currentWeek.append(MonthDayCell(id: nextCellID, date: nil))
            nextCellID += 1
        }

        for day in range {
            let date = calendar.date(byAdding: .day, value: day - 1, to: firstOfMonth)
            currentWeek.append(MonthDayCell(id: nextCellID, date: date))
            nextCellID += 1
            if currentWeek.count == 7 {
                weeks.append(currentWeek)
                currentWeek = []
            }
        }

        // Trailing blanks
        if !currentWeek.isEmpty {
            while currentWeek.count < 7 {
                currentWeek.append(MonthDayCell(id: nextCellID, date: nil))
                nextCellID += 1
            }
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
                    let progress = goalProgress(forFocusMinutes: focusMinutesForDay(selectedDate))
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
                        Text("\(Int((progress * 100).rounded()))%")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 44, height: 44)
                }

                let sessions = sessionsForDay(selectedDate)
                if sessions.isEmpty {
                    emptyDayView
                } else {
                    DisclosureGroup {
                        SessionTimelineView(sessions: sessions)
                            .padding(.top, 8)
                    } label: {
                        dayCompactSummary(sessions)
                    }
                }
            }
            .padding(16)
        }
    }

    // MARK: - Reminders Section

    private var remindersSection: some View {
        LiquidGlassPanel {
            VStack(alignment: .leading, spacing: 12) {
                LiquidSectionHeader("Reminders", subtitle: remindersSubtitle) {
                    Button {
                        reminderDraftTitle = ""
                        reminderDraftNotes = ""
                        reminderDraftDueDate = selectedDate
                        showCreateReminder = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 30, height: 30)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .disabled(!(settings?.remindersIntegrationEnabled ?? false))
                    .accessibilityLabel("Create reminder")
                }

                if !(settings?.remindersIntegrationEnabled ?? false) {
                    Label("Enable Reminders in Settings to sync and manage tasks here.", systemImage: "info.circle")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 6)
                } else if isLoadingReminders {
                    ProgressView("Loading reminders...")
                        .padding(.vertical, 8)
                } else if let remindersError {
                    Label(remindersError, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.orange)
                } else if remindersForSelectedDate.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "checklist")
                            .font(.system(size: 18, weight: .light))
                            .foregroundStyle(.tertiary)
                        Text("No reminders due for this day")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                } else {
                    VStack(spacing: 8) {
                        ForEach(remindersForSelectedDate, id: \.id) { reminder in
                            reminderRow(reminder)
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    private var remindersSubtitle: String {
        guard settings?.remindersIntegrationEnabled == true else { return "Sync Apple Reminders into your planning flow" }
        let count = remindersForSelectedDate.count
        if count == 0 { return "No reminders due on selected day" }
        return "\(count) reminder\(count == 1 ? "" : "s") due"
    }

    private var remindersForSelectedDate: [RemindersService.ReminderItem] {
        var seen = Set<String>()
        return reminders
            .filter {
                guard let due = $0.dueDate else { return false }
                return calendar.isDate(due, inSameDayAs: selectedDate)
            }
            .filter { seen.insert($0.id).inserted }
            .sorted {
                let lhs = $0.dueDate ?? .distantFuture
                let rhs = $1.dueDate ?? .distantFuture
                if lhs != rhs { return lhs < rhs }
                return $0.title < $1.title
            }
    }

    private func reminderRow(_ reminder: RemindersService.ReminderItem) -> some View {
        HStack(spacing: 10) {
            Button {
                _ = RemindersService.shared.completeReminder(identifier: reminder.id)
                Task { await loadReminders() }
            } label: {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 16, weight: .regular))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.green)
            .accessibilityLabel("Mark reminder complete")

            VStack(alignment: .leading, spacing: 2) {
                Text(reminder.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                HStack(spacing: 6) {
                    Text(reminder.list)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    if let due = reminder.dueDate {
                        Text(due.formatted(.dateTime.hour().minute()))
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                    }
                }
            }

            Spacer()

            Button {
                editingReminder = reminder
                reminderDraftTitle = reminder.title
                reminderDraftNotes = reminder.notes
                reminderDraftDueDate = reminder.dueDate ?? selectedDate
                showReminderEditor = true
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Edit reminder")
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func reminderEditorSheet(isCreating: Bool) -> some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Reminder title", text: $reminderDraftTitle)
                }
                Section("Notes") {
                    TextField("Details", text: $reminderDraftNotes, axis: .vertical)
                        .lineLimit(3...6)
                }
                Section("Due") {
                    DatePicker("Due Date", selection: $reminderDraftDueDate, displayedComponents: [.date, .hourAndMinute])
                }
            }
            .navigationTitle(isCreating ? "New Reminder" : "Edit Reminder")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showReminderEditor = false
                        showCreateReminder = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if isCreating {
                            _ = RemindersService.shared.createReminder(
                                title: reminderDraftTitle,
                                notes: reminderDraftNotes.isEmpty ? nil : reminderDraftNotes,
                                dueDate: reminderDraftDueDate,
                                listId: settings?.selectedReminderListId
                            )
                        } else if let editingReminder {
                            _ = RemindersService.shared.updateReminder(
                                identifier: editingReminder.id,
                                title: reminderDraftTitle,
                                notes: reminderDraftNotes.isEmpty ? nil : reminderDraftNotes,
                                dueDate: reminderDraftDueDate
                            )
                        }
                        showReminderEditor = false
                        showCreateReminder = false
                        Task { await loadReminders() }
                    }
                    .disabled(reminderDraftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .frame(minWidth: 460, minHeight: 360)
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

    private func dayCompactSummary(_ sessions: [FocusSession]) -> some View {
        HStack(spacing: 16) {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.green)
                Text("\(sessions.count) session\(sessions.count == 1 ? "" : "s")")
                    .font(.system(size: 13, weight: .medium))
            }

            HStack(spacing: 4) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.blue)
                Text(formatFocusDuration(focusMinutesForDay(selectedDate)))
                    .font(.system(size: 13, weight: .medium))
            }

            Spacer()
        }
    }

    private func formatFocusDuration(_ minutes: Double) -> String {
        let totalMinutes = Int(minutes)
        let hours = totalMinutes / 60
        let mins = totalMinutes % 60
        if hours > 0 { return "\(hours)h \(mins)m" }
        return "\(mins)m"
    }

    // MARK: - Data Helpers

    private func sessionsForDay(_ date: Date) -> [FocusSession] {
        let dayStart = calendar.startOfDay(for: date)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return [] }
        return allSessions.filter { session in
            let sessionEnd = session.endedAt ?? session.startedAt.addingTimeInterval(session.actualDuration)
            return sessionEnd > dayStart && session.startedAt < dayEnd
        }.sorted { $0.startedAt < $1.startedAt }
    }

    private func focusMinutesForDay(_ date: Date) -> Double {
        let dayStart = calendar.startOfDay(for: date)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return 0 }
        return allSessions.filter { $0.type == .focus }.reduce(0.0) { sum, session in
            let sessionEnd = session.endedAt ?? session.startedAt.addingTimeInterval(session.actualDuration)
            guard sessionEnd > dayStart && session.startedAt < dayEnd else { return sum }
            let overlapStart = max(session.startedAt, dayStart)
            let overlapEnd = min(sessionEnd, dayEnd)
            return sum + max(0, overlapEnd.timeIntervalSince(overlapStart)) / 60
        }
    }

    private func shiftDisplayedMonth(by monthDelta: Int) {
        guard let shifted = calendar.date(byAdding: .month, value: monthDelta, to: displayedMonth) else { return }
        displayedMonth = shifted
    }



    private func goalProgress(forFocusMinutes minutes: Double) -> Double {
        let rawGoal = allSettings.first?.dailyFocusGoal ?? 7200
        let normalizedGoal = rawGoal.isFinite && rawGoal >= 60 ? rawGoal : 7200
        let ratio = (minutes * 60) / normalizedGoal
        guard ratio.isFinite else { return 0 }
        return min(1.0, max(0, ratio))
    }

    private func sanitizedMinutes(_ minutes: Double) -> Double {
        guard minutes.isFinite else { return 0 }
        return max(0, minutes)
    }


    private func loadReminders() async {
        reminderLoadTask?.cancel()
        reminderLoadTask = Task { @MainActor in
            await loadRemindersInternal()
        }
        await reminderLoadTask?.value
    }

    private func loadRemindersInternal() async {
        guard settings?.remindersIntegrationEnabled == true else {
            reminders = []
            remindersError = nil
            isLoadingReminders = false
            Self.logger.debug("loadReminders skipped: integration disabled")
            return
        }
        guard RemindersService.shared.authStatus == .authorized else {
            remindersError = "Reminders permission is not granted."
            reminders = []
            isLoadingReminders = false
            Self.logger.error("loadReminders failed: reminders permission missing")
            return
        }
        isLoadingReminders = true
        remindersError = nil
        let listId = settings?.selectedReminderListId.isEmpty == true ? nil : settings?.selectedReminderListId
        let dayStart = calendar.startOfDay(for: selectedDate)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
            remindersError = "Unable to resolve selected date."
            reminders = []
            isLoadingReminders = false
            Self.logger.error("loadReminders failed: invalid day boundary")
            return
        }
        let fetched = await RemindersService.shared.fetchIncompleteReminders(
            listId: listId,
            dueDateStarting: dayStart,
            dueDateEnding: dayEnd
        )
        guard !Task.isCancelled else {
            Self.logger.debug("loadReminders cancelled before state update")
            return
        }
        reminders = fetched
        Self.logger.debug(
            "loadReminders success: fetched=\(fetched.count, privacy: .public) selectedDate=\(dayStart.timeIntervalSince1970, privacy: .public) listIdProvided=\(listId != nil, privacy: .public)"
        )
        isLoadingReminders = false
    }
}
