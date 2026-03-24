import SwiftUI
import SwiftData
import OSLog
import AppKit
import EventKit

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
    @State private var reminderSaveError: String?
    @State private var editingReminder: RemindersService.ReminderItem?
    @State private var reminderDraftTitle = ""
    @State private var reminderDraftNotes = ""
    @State private var reminderDraftDueDate: Date = Date()
    @State private var showReminderEditor = false
    @State private var showCreateReminder = false
    @State private var reminderLoadTask: Task<Void, Never>?
    @State private var completingReminderId: String? = nil
    @State private var deletingReminderId: String? = nil
    @State private var reminderToConfirmDelete: RemindersService.ReminderItem? = nil
    @State private var needsReminderRefresh = false
    @State private var isRefreshingReminders = false
    @State private var showDaySessions: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var calendar: Calendar { Calendar.current }
    private var settings: AppSettings? { allSettings.first }
    private static let logger = Logger(subsystem: "FocusFlow", category: "CalendarTabView")

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerSection
                monthGridSection
                    .animation(reduceMotion ? nil : FFMotion.section, value: selectedDate)
                    .animation(reduceMotion ? nil : FFMotion.section, value: displayedMonth)
                dayDetailSection
                remindersSection
            }
            .padding(24)
        }
        .background(Color.clear)
        .onAppear {
            Self.logger.debug("Calendar tab appeared. remindersEnabled=\(self.settings?.remindersIntegrationEnabled == true, privacy: .public) selectedListEmpty=\(self.settings?.selectedReminderListId.isEmpty ?? true, privacy: .public)")
        }
        // Reload when EventKit store changes (e.g., user adds/edits reminders in Reminders.app,
        // or when permission is just granted — EventKit posts this automatically).
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in
            guard settings?.remindersIntegrationEnabled == true else { return }
            // Mark that a refresh is needed; the periodic timer will pick it up
            needsReminderRefresh = true
        }
        .task(id: settings?.remindersIntegrationEnabled) {
            guard settings?.remindersIntegrationEnabled == true else { return }
            // Periodic graceful refresh every 30 seconds
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { break }
                guard settings?.remindersIntegrationEnabled == true else { break }
                if needsReminderRefresh {
                    needsReminderRefresh = false
                    await refreshRemindersGracefully()
                }
            }
        }
        .task { await loadReminders() }
        .onChange(of: settings?.remindersIntegrationEnabled) { _, _ in
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
                        withAnimation(reduceMotion ? .linear(duration: 0.01) : FFMotion.section) {
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
                        withAnimation(reduceMotion ? .linear(duration: 0.01) : FFMotion.section) {
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
                        withAnimation(reduceMotion ? .linear(duration: 0.01) : FFMotion.section) {
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
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.bottom, 8)

                // Day grid
                let weeks = monthWeeks
                ForEach(weeks.indices, id: \.self) { weekIdx in
                    HStack(spacing: 2) {
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
                    .frame(width: 7, height: 7)
            } else {
                Color.clear.frame(width: 7, height: 7)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LiquidDesignTokens.Spectral.primaryContainer)
                    .shadow(color: LiquidDesignTokens.Spectral.primaryContainer.opacity(0.3), radius: 6)
            } else if isToday {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LiquidDesignTokens.Spectral.primaryContainer.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(LiquidDesignTokens.Spectral.primaryContainer.opacity(0.6), lineWidth: 2)
                    )
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(reduceMotion ? .linear(duration: 0.01) : FFMotion.control) {
                selectedDate = date
            }
        }
        .accessibilityLabel("\(date.formatted(.dateTime.month(.wide).day())), \(hasSessions ? "\(Int(focusMinutes)) minutes focused" : "no sessions")")
    }

    private func intensityColor(_ progress: Double) -> Color {
        let p = min(max(progress.isFinite ? progress : 0, 0), 1)
        if p >= 1.0 { return Color.green }
        if p >= 0.5 { return Color.green.opacity(0.7) }
        return Color.green.opacity(0.4)
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
                    VStack(alignment: .leading, spacing: 0) {
                        Button {
                            withAnimation(reduceMotion ? .linear(duration: 0.01) : FFMotion.section) {
                                showDaySessions.toggle()
                            }
                        } label: {
                            HStack(spacing: 0) {
                                dayCompactSummary(sessions)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                                    .rotationEffect(.degrees(showDaySessions ? 90 : 0))
                                    .animation(reduceMotion ? nil : FFMotion.control, value: showDaySessions)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(showDaySessions ? "Collapse sessions" : "Expand sessions")

                        if showDaySessions {
                            SessionTimelineView(sessions: sessions)
                                .padding(.top, 8)
                                .transition(.opacity)
                        }
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
                    HStack(spacing: 6) {
                        // Manual refresh button — important after granting OS permissions
                        Button {
                            reminderLoadTask?.cancel()
                            reminderLoadTask = Task { @MainActor in await loadRemindersInternal() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11, weight: .semibold))
                                .frame(width: 30, height: 30)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                        .disabled(!(settings?.remindersIntegrationEnabled ?? false) || isLoadingReminders)
                        .overlay {
                            if isRefreshingReminders {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                        .accessibilityLabel("Refresh reminders")
                        .help("Refresh reminders")

                        Button {
                            reminderDraftTitle = ""
                            reminderDraftNotes = ""
                            reminderDraftDueDate = selectedDate
                            reminderSaveError = nil
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
                } else if reminders.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "checklist")
                            .font(.system(size: 18, weight: .light))
                            .foregroundStyle(.tertiary)
                        Text("No incomplete reminders")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                } else {
                    VStack(spacing: 12) {
                        // Past due + today
                        let pastAndToday = remindersInGroup(.pastAndToday)
                        if !pastAndToday.isEmpty {
                            reminderGroupSection("Due Today", items: pastAndToday, labelColor: .orange)
                        }
                        // Upcoming (future due date)
                        let upcoming = remindersInGroup(.upcoming)
                        if !upcoming.isEmpty {
                            reminderGroupSection("Upcoming", items: upcoming, labelColor: .secondary)
                        }
                        // No due date
                        let noDate = remindersInGroup(.noDate)
                        if !noDate.isEmpty {
                            reminderGroupSection("No Due Date", items: noDate, labelColor: .secondary)
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    private enum ReminderGroup { case pastAndToday, upcoming, noDate }

    private func remindersInGroup(_ group: ReminderGroup) -> [RemindersService.ReminderItem] {
        let today = Calendar.current.startOfDay(for: Date())
        guard let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today) else { return [] }
        switch group {
        case .pastAndToday:
            return reminders.filter {
                guard let due = $0.dueDate else { return false }
                return due < tomorrow
            }.sorted { ($0.dueDate ?? .distantPast) < ($1.dueDate ?? .distantPast) }
        case .upcoming:
            return reminders.filter {
                guard let due = $0.dueDate else { return false }
                return due >= tomorrow
            }.sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
        case .noDate:
            return reminders.filter { $0.dueDate == nil }
                .sorted { $0.title < $1.title }
        }
    }

    @ViewBuilder
    private func reminderGroupSection(
        _ title: String,
        items: [RemindersService.ReminderItem],
        labelColor: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            TrackedLabel(
                text: title.uppercased(),
                font: .system(size: 10, weight: .bold),
                color: labelColor,
                tracking: 1.4
            )
            VStack(spacing: 6) {
                ForEach(items, id: \.id) { reminder in
                    reminderRow(reminder)
                }
            }
        }
    }

    private var remindersSubtitle: String {
        guard settings?.remindersIntegrationEnabled == true else { return "Sync Apple Reminders into your planning flow" }
        if reminders.isEmpty { return "No incomplete reminders" }
        let overdue = remindersInGroup(.pastAndToday).count
        if overdue > 0 { return "\(overdue) due today · \(reminders.count) total" }
        return "\(reminders.count) incomplete reminder\(reminders.count == 1 ? "" : "s")"
    }

    private func reminderRow(_ reminder: RemindersService.ReminderItem) -> some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(reduceMotion ? .linear(duration: 0.01) : .spring(response: 0.3, dampingFraction: 0.6)) {
                    completingReminderId = reminder.id
                }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(400))
                    let didComplete = RemindersService.shared.completeReminder(identifier: reminder.id)
                    guard didComplete else {
                        completingReminderId = nil
                        reminderSaveError = "Could not complete reminder."
                        return
                    }
                    withAnimation(reduceMotion ? .linear(duration: 0.01) : .easeInOut(duration: 0.3)) {
                        reminders.removeAll { $0.id == reminder.id }
                    }
                    needsReminderRefresh = true
                    completingReminderId = nil
                }
            } label: {
                Image(systemName: completingReminderId == reminder.id ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(completingReminderId == reminder.id ? .green : .secondary)
                    .scaleEffect(completingReminderId == reminder.id ? 1.2 : 1.0)
            }
            .buttonStyle(.plain)
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
                        Text(formattedReminderDate(due))
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
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .background(Color.white.opacity(0.04))
        .cornerRadius(8)
        .transition(.asymmetric(insertion: .identity, removal: .slide.combined(with: .opacity)))
        .contextMenu {
            Button(role: .destructive) {
                reminderToConfirmDelete = reminder
            } label: {
                Label("Delete Reminder", systemImage: "trash")
            }
        }
        .confirmationDialog(
            "Delete \"\(reminderToConfirmDelete?.title ?? "")\"?",
            isPresented: Binding(
                get: { reminderToConfirmDelete?.id == reminder.id },
                set: { if !$0 { reminderToConfirmDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                guard let target = reminderToConfirmDelete else { return }
                reminderToConfirmDelete = nil
                Task { @MainActor in
                    let didDelete = RemindersService.shared.deleteReminder(identifier: target.id)
                    if didDelete {
                        withAnimation(reduceMotion ? .linear(duration: 0.01) : .easeInOut(duration: 0.3)) {
                            reminders.removeAll { $0.id == target.id }
                        }
                    } else {
                        reminderSaveError = "Could not delete reminder."
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                reminderToConfirmDelete = nil
            }
        } message: {
            Text("This will permanently delete the reminder from Apple Reminders.")
        }
    }

    @ViewBuilder
    private func reminderEditorSheet(isCreating: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text(isCreating ? "New Reminder" : "Edit Reminder")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Button {
                    showReminderEditor = false
                    showCreateReminder = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel")
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 20)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Title field
                    VStack(alignment: .leading, spacing: 6) {
                        Text("TITLE")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .kerning(1.5)

                        TextField("e.g. Review pull requests", text: $reminderDraftTitle)
                            .textFieldStyle(.plain)
                            .font(.system(size: 15))
                            .padding(12)
                            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 10))
                    }

                    // Notes field
                    VStack(alignment: .leading, spacing: 6) {
                        Text("NOTES")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .kerning(1.5)

                        ZStack(alignment: .topLeading) {
                            if reminderDraftNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text("Add details (optional)")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.tertiary)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 14)
                                    .allowsHitTesting(false)
                            }
                            TextEditor(text: $reminderDraftNotes)
                                .scrollContentBackground(.hidden)
                                .font(.system(size: 14))
                                .frame(minHeight: 72, maxHeight: 120)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                        }
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 10))
                    }

                    // Due date
                    VStack(alignment: .leading, spacing: 6) {
                        Text("DUE DATE")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .kerning(1.5)

                        DatePicker("", selection: $reminderDraftDueDate, displayedComponents: [.date, .hourAndMinute])
                            .datePickerStyle(.compact)
                            .labelsHidden()
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }

            // Action buttons
            Divider().opacity(0.3)

            // Error banner
            if let reminderSaveError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.system(size: 12))
                    Text(reminderSaveError)
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .transition(.opacity)
            }

            HStack(spacing: 12) {
                Spacer()
                Button("Cancel") {
                    showReminderEditor = false
                    showCreateReminder = false
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)

                Button(isCreating ? "Add Reminder" : "Save Changes") {
                    Task { @MainActor in
                        if isCreating {
                            let id = RemindersService.shared.createReminder(
                                title: reminderDraftTitle,
                                notes: reminderDraftNotes.isEmpty ? nil : reminderDraftNotes,
                                dueDate: reminderDraftDueDate,
                                listId: settings?.selectedReminderListId
                            )
                            guard id != nil else {
                                reminderSaveError = "Could not create reminder. Check Reminders permission in System Settings."
                                return
                            }
                            showReminderEditor = false
                            showCreateReminder = false
                            reminderSaveError = nil
                            // Brief settle delay so EventKit can commit before we re-fetch.
                            try? await Task.sleep(for: .milliseconds(400))
                            await loadRemindersInternal()
                            return
                        }

                        guard let editingReminder else { return }
                        let ok = RemindersService.shared.updateReminder(
                            identifier: editingReminder.id,
                            title: reminderDraftTitle,
                            notes: reminderDraftNotes.isEmpty ? nil : reminderDraftNotes,
                            dueDate: reminderDraftDueDate
                        )
                        guard ok else {
                            reminderSaveError = "Could not update reminder."
                            return
                        }
                        showReminderEditor = false
                        showCreateReminder = false
                        reminderSaveError = nil
                        try? await Task.sleep(for: .milliseconds(400))
                        await loadRemindersInternal()
                    }
                }
                .buttonStyle(.glassProminent)
                .tint(.blue)
                .buttonBorderShape(.capsule)
                .disabled(reminderDraftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .frame(width: 400)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
        let safeMinutes = minutes.isFinite ? max(0, minutes) : 0
        let totalMinutes = Int(safeMinutes.rounded(.down))
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
            let safeDuration = session.actualDuration.isFinite ? max(0, session.actualDuration) : 0
            let sessionEnd = session.endedAt ?? session.startedAt.addingTimeInterval(safeDuration)
            return sessionEnd > dayStart && session.startedAt < dayEnd
        }.sorted { $0.startedAt < $1.startedAt }
    }

    private func focusMinutesForDay(_ date: Date) -> Double {
        let dayStart = calendar.startOfDay(for: date)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return 0 }
        let total = allSessions.filter { $0.type == .focus }.reduce(0.0) { sum, session in
            let safeDuration = session.actualDuration.isFinite ? max(0, session.actualDuration) : 0
            let sessionEnd = session.endedAt ?? session.startedAt.addingTimeInterval(safeDuration)
            guard sessionEnd > dayStart && session.startedAt < dayEnd else { return sum }
            let overlapStart = max(session.startedAt, dayStart)
            let overlapEnd = min(sessionEnd, dayEnd)
            let increment = max(0, overlapEnd.timeIntervalSince(overlapStart)) / 60
            guard increment.isFinite else { return sum }
            let next = sum + increment
            return next.isFinite ? next : sum
        }
        return total.isFinite ? total : 0
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

    /// Formats a reminder due date intelligently:
    /// - If the time is midnight (00:00), show date only (the reminder has no specific time)
    /// - If today, show just the time
    /// - Otherwise show short date + time
    private func formattedReminderDate(_ date: Date) -> String {
        let cal = Calendar.current
        let comps = cal.dateComponents([.hour, .minute], from: date)
        let isMidnight = comps.hour == 0 && comps.minute == 0
        let isToday = cal.isDateInToday(date)
        let isTomorrow = cal.isDateInTomorrow(date)

        if isMidnight {
            if isToday { return "Today" }
            if isTomorrow { return "Tomorrow" }
            return date.formatted(.dateTime.month(.abbreviated).day())
        }
        if isToday { return date.formatted(.dateTime.hour().minute()) }
        if isTomorrow { return "Tomorrow \(date.formatted(.dateTime.hour().minute()))" }
        return date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }


    private func refreshRemindersGracefully() async {
        isRefreshingReminders = true
        defer { isRefreshingReminders = false }
        let fetched = await RemindersService.shared.fetchIncompleteReminders(
            listId: settings?.selectedReminderListId
        )
        guard !Task.isCancelled else { return }

        let oldIds = Set(reminders.map(\.id))
        let newIds = Set(fetched.map(\.id))

        // Only animate if there are actual changes
        if oldIds != newIds {
            withAnimation(reduceMotion ? .linear(duration: 0.01) : .easeInOut(duration: 0.3)) {
                reminders = fetched
            }
        } else {
            // No visible change — update silently (e.g., due date changes)
            reminders = fetched
        }
    }

    private func loadReminders() async {
        reminderLoadTask?.cancel()
        reminderLoadTask = Task { @MainActor in
            await loadRemindersInternal()
        }
        await reminderLoadTask?.value
    }

    @MainActor private func loadRemindersInternal() async {
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
        defer { isLoadingReminders = false }
        let fetched = await RemindersService.shared.fetchIncompleteReminders(
            listId: settings?.selectedReminderListId
        )
        guard !Task.isCancelled else {
            Self.logger.debug("loadReminders cancelled before state update")
            return
        }
        reminders = fetched
        Self.logger.debug("loadReminders success: fetched=\(fetched.count, privacy: .public)")
    }
}
