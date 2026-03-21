import SwiftUI
import SwiftData
import ServiceManagement

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openWindow) private var openWindow
    @Query private var allSettings: [AppSettings]
    @State private var availableCalendars: [(source: String, calendars: [(id: String, title: String)])] = []
    @State private var availableReminderLists: [(id: String, title: String, source: String)] = []
    @State private var isLoadingCalendars = false
    @State private var calendarLoadError: String?
    @State private var isLoadingReminderLists = false
    @State private var reminderLoadError: String?
    @State private var reminderAuthError: String?
    @State private var saveError: String?
    @State private var isEnablingCalendar = false
    @State private var isEnablingReminders = false
    @State private var showBlockingSheet = false

    private var settings: AppSettings {
        allSettings.first ?? AppSettings()
    }

    var body: some View {
        ScrollView {
            VStack(spacing: LiquidDesignTokens.Spacing.large) {
                durationsSection
                behaviorSection
                soundSection
                goalsSection
                blockingSection
                integrationsSection
                focusCoachSection
                aboutSection
            }
            .padding(24)
        }
        .background(.ultraThinMaterial)
        .saveErrorOverlay($saveError)
        .onAppear {
            if settings.calendarIntegrationEnabled {
                loadCalendars()
            }
            if settings.remindersIntegrationEnabled {
                loadReminderLists()
            }
        }
    }

    private var durationsSection: some View {
        LiquidGlassPanel {
            VStack(alignment: .leading, spacing: 12) {
                LiquidSectionHeader("Durations", subtitle: "Session lengths and long-break cadence")

                VStack(spacing: 10) {
                    DurationRow(
                        label: "Focus",
                        icon: "timer",
                        color: .blue,
                        minutes: Binding(
                            get: { Int(settings.focusDuration / 60) },
                            set: { settings.focusDuration = TimeInterval($0 * 60); save() }
                        ),
                        range: 5...120,
                        step: 5
                    )

                    Divider()

                    DurationRow(
                        label: "Short Break",
                        icon: "cup.and.saucer.fill",
                        color: .green,
                        minutes: Binding(
                            get: { Int(settings.shortBreakDuration / 60) },
                            set: { settings.shortBreakDuration = TimeInterval($0 * 60); save() }
                        ),
                        range: 1...30,
                        step: 1
                    )

                    Divider()

                    DurationRow(
                        label: "Long Break",
                        icon: "figure.walk",
                        color: .purple,
                        minutes: Binding(
                            get: { Int(settings.longBreakDuration / 60) },
                            set: { settings.longBreakDuration = TimeInterval($0 * 60); save() }
                        ),
                        range: 5...60,
                        step: 5
                    )

                    Divider()

                    HStack {
                        Label("Sessions before long break", systemImage: "repeat.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Stepper(
                            "\(settings.sessionsBeforeLongBreak)",
                            value: Binding(
                                get: { settings.sessionsBeforeLongBreak },
                                set: { settings.sessionsBeforeLongBreak = $0; save() }
                            ),
                            in: 2...8
                        )
                        .frame(width: 110)
                        .font(.subheadline)
                    }
                }
            }
            .padding(16)
        }
    }

    private var behaviorSection: some View {
        LiquidGlassPanel {
            VStack(alignment: .leading, spacing: 12) {
                LiquidSectionHeader("Behavior", subtitle: "Automations and startup preferences")

                VStack(spacing: 10) {
                    ToggleRow(
                        label: "Auto-start breaks",
                        icon: "play.circle.fill",
                        color: .green,
                        isOn: Binding(
                            get: { settings.autoStartBreak },
                            set: { settings.autoStartBreak = $0; save() }
                        )
                    )

                    Divider()

                    ToggleRow(
                        label: "Auto-start next session",
                        icon: "arrow.clockwise.circle.fill",
                        color: .blue,
                        isOn: Binding(
                            get: { settings.autoStartNextSession },
                            set: { settings.autoStartNextSession = $0; save() }
                        )
                    )

                    Divider()

                    ToggleRow(
                        label: "Launch at login",
                        icon: "power.circle.fill",
                        color: .orange,
                        isOn: Binding(
                            get: { settings.launchAtLogin },
                            set: {
                                settings.launchAtLogin = $0
                                save()
                                setLaunchAtLogin($0)
                            }
                        )
                    )
                }
            }
            .padding(16)
        }
    }

    private var soundSection: some View {
        LiquidGlassPanel {
            VStack(alignment: .leading, spacing: 12) {
                LiquidSectionHeader("Sound & Notifications", subtitle: "Completion chime and system alerts")

                HStack {
                    Label("Completion sound", systemImage: "speaker.wave.2.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Picker("", selection: Binding(
                        get: { settings.completionSound },
                        set: {
                            settings.completionSound = $0
                            save()
                            NSSound(named: NSSound.Name($0))?.play()
                        }
                    )) {
                        ForEach(systemSounds, id: \.self) { sound in
                            Text(sound).tag(sound)
                        }
                    }
                    .frame(width: 150)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: LiquidDesignTokens.CornerRadius.control))

                // Notification permission banner — shown when denied
                if !NotificationService.shared.isAuthorized {
                    HStack(spacing: 8) {
                        Image(systemName: "bell.slash.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Notifications are disabled")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.primary)
                            Text("FocusFlow can't alert you when sessions complete. Enable in System Settings → Notifications.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Open Settings") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!)
                        }
                        .font(.system(size: 11, weight: .medium))
                        .buttonStyle(.plain)
                        .foregroundStyle(.blue)
                    }
                    .padding(10)
                    .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(16)
        }
        .onAppear { NotificationService.shared.refreshAuthorizationStatus() }
    }

    private var aboutSection: some View {
        LiquidGlassPanel {
            VStack(spacing: 12) {
                LiquidSectionHeader("About", subtitle: "FocusFlow companion app")

                Image(systemName: "timer")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)

                VStack(spacing: 6) {
                    Text("FocusFlow")
                        .font(.system(size: 18, weight: .bold))

                    TrackedLabel(
                        text: "Tahoe Edition",
                        font: .system(size: 10, weight: .semibold),
                        color: LiquidDesignTokens.Spectral.electricBlue,
                        tracking: 2.0
                    )

                    Text("Pomodoro focus timer for macOS")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("v1.0")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(16)
        }
    }

    // MARK: - Goals

    private var goalsSection: some View {
        LiquidGlassPanel {
            VStack(alignment: .leading, spacing: 12) {
                LiquidSectionHeader("Goals", subtitle: "Daily focus targets")

                VStack(spacing: 10) {
                    HStack {
                        HStack(spacing: 8) {
                            Image(systemName: "target")
                                .foregroundStyle(.indigo)
                                .font(.system(size: 13, weight: .semibold))
                            Text("Daily Focus Goal")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text("\(Int(settings.dailyFocusGoal / 60)) min")
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.primary)
                            .frame(width: 60, alignment: .trailing)
                    }

                    Slider(
                        value: Binding(
                            get: { settings.dailyFocusGoal / 60 },
                            set: { settings.dailyFocusGoal = $0 * 60; save() }
                        ),
                        in: 30...480,
                        step: 15
                    )
                    .tint(LiquidDesignTokens.Spectral.primaryContainer)
                    .accessibilityLabel("Daily focus goal")
                    .accessibilityValue("\(Int(settings.dailyFocusGoal / 60)) minutes")

                    HStack {
                        Text("30m")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Spacer()
                        Text("8h")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(16)
        }
    }

    // MARK: - Blocking

    private var blockingSection: some View {
        LiquidGlassPanel {
            VStack(spacing: 14) {
                LiquidSectionHeader("Blocking", subtitle: "Block distracting apps and websites during focus")

                Button { showBlockingSheet = true } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "shield.checkered")
                            .font(.system(size: 14))
                            .foregroundStyle(.blue)
                        Text("Manage Blocking Profiles")
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Text("Websites are blocked via system DNS. Apps are quit when a focus session starts.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
        }
        .sheet(isPresented: $showBlockingSheet) {
            BlockingSettingsView()
        }
    }

    // MARK: - Integrations

    private var integrationsSection: some View {
        LiquidGlassPanel {
            VStack(alignment: .leading, spacing: 12) {
                LiquidSectionHeader("Integrations", subtitle: "Connect with Apple apps")

                // Calendar toggle with auth flow
                HStack(spacing: 12) {
                    Image(systemName: "calendar.badge.clock")
                        .foregroundStyle(.red)
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 20)

                    Text("Record to Calendar")
                        .font(.subheadline)

                    Spacer()

                    calendarStatusBadge

                    Toggle("", isOn: Binding(
                        get: { settings.calendarIntegrationEnabled },
                        set: { newValue in
                            if newValue {
                                Task { await enableCalendarIntegration() }
                            } else {
                                settings.calendarIntegrationEnabled = false
                                settings.selectedCalendarId = ""
                                save()
                            }
                        }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .frame(width: 44)
                    .accessibilityLabel("Record to Calendar")
                }

                if settings.calendarIntegrationEnabled {
                    calendarPickerSection

                    // Sync scope explainer
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .padding(.top, 1)
                        Text("Calendar events are created when you complete or save a focus session. Sessions logged before enabling this integration are not retroactively synced.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 4)
                }

                remindersIntegrationSection
            }
            .padding(16)
            .animation(FFMotion.section, value: settings.calendarIntegrationEnabled)
        }
    }

    @ViewBuilder
    private var calendarStatusBadge: some View {
        let status = CalendarService.shared.authStatus
        switch status {
        case .authorized:
            HStack(spacing: 4) {
                Circle().fill(.green).frame(width: 6, height: 6)
                Text("Connected")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.green)
            }
        case .denied:
            HStack(spacing: 4) {
                Circle().fill(.red).frame(width: 6, height: 6)
                Text("Denied")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.red)
            }
        case .notDetermined:
            EmptyView()
        }
    }

    private var calendarPickerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()

            if isLoadingCalendars {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Loading calendars...")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
            } else if let calendarLoadError {
                VStack(alignment: .leading, spacing: 8) {
                    Label(calendarLoadError, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.orange)

                    Button("Retry Calendar Sync") {
                        loadCalendars()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                }
            } else if availableCalendars.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No calendars found.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.tertiary)

                    Button("Reload Calendars") {
                        loadCalendars()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                }
            } else {
                HStack {
                    Label("Record sessions to", systemImage: "calendar")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Picker("", selection: Binding(
                        get: { settings.selectedCalendarId.isEmpty ? "__create_new__" : settings.selectedCalendarId },
                        set: { newValue in
                            if newValue == "__create_new__" {
                                settings.selectedCalendarId = ""
                                settings.calendarName = "FocusFlow"
                            } else {
                                settings.selectedCalendarId = newValue
                                // Find the title for this calendar
                                for group in availableCalendars {
                                    if let cal = group.calendars.first(where: { $0.id == newValue }) {
                                        settings.calendarName = cal.title
                                        break
                                    }
                                }
                            }
                            save()
                        }
                    )) {
                        ForEach(availableCalendars, id: \.source) { group in
                            Section(group.source) {
                                ForEach(group.calendars, id: \.id) { cal in
                                    Text(cal.title).tag(cal.id)
                                }
                            }
                        }
                        Divider()
                        Text("Create \"FocusFlow\" Calendar").tag("__create_new__")
                    }
                    .frame(maxWidth: 220)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: LiquidDesignTokens.CornerRadius.control))
            }

            // Discoverability hint — where to find events
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.top, 1)
                Text("Sessions appear with a 🎯 prefix in your selected calendar. Open Apple Calendar and make sure your calendar is checked in the sidebar.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 4)
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    @ViewBuilder
    private var remindersStatusBadge: some View {
        let status = RemindersService.shared.authStatus
        switch status {
        case .authorized:
            HStack(spacing: 4) {
                Circle().fill(.green).frame(width: 6, height: 6)
                Text("Connected")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.green)
            }
        case .denied:
            HStack(spacing: 4) {
                Circle().fill(.red).frame(width: 6, height: 6)
                Text("Denied")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.red)
            }
        case .notDetermined:
            EmptyView()
        }
    }

    private var remindersIntegrationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()

            HStack(spacing: 12) {
                Image(systemName: "checklist")
                    .foregroundStyle(.blue)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 20)

                Text("Sync Reminders")
                    .font(.subheadline)

                Spacer()

                remindersStatusBadge

                Toggle("", isOn: Binding(
                    get: { settings.remindersIntegrationEnabled },
                    set: { newValue in
                        if newValue {
                            Task { await enableRemindersIntegration() }
                        } else {
                            settings.remindersIntegrationEnabled = false
                            settings.selectedReminderListId = ""
                            reminderAuthError = nil
                            save()
                        }
                    }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .frame(width: 44)
                .accessibilityLabel("Sync Reminders")
            }

            if settings.remindersIntegrationEnabled {
                reminderPickerSection
            }

            if let reminderAuthError {
                Label(reminderAuthError, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.orange)
            }

            if let reminderLoadError {
                Label(reminderLoadError, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.orange)
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var reminderPickerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isLoadingReminderLists {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Loading reminder lists...")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
            } else if availableReminderLists.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No reminder lists found.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.tertiary)

                    Button("Reload Reminder Lists") {
                        loadReminderLists()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                }
            } else {
                HStack {
                    Label("Default list for new reminders", systemImage: "list.bullet")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Picker("", selection: Binding(
                        get: { settings.selectedReminderListId },
                        set: {
                            settings.selectedReminderListId = $0
                            save()
                        }
                    )) {
                        ForEach(availableReminderLists, id: \.id) { list in
                            Text(list.title).tag(list.id)
                        }
                    }
                    .frame(maxWidth: 200)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: LiquidDesignTokens.CornerRadius.control))

                Text("All incomplete reminders from every list are shown in the Calendar tab.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 4)
            }
        }
    }

    private func enableCalendarIntegration() async {
        guard !isEnablingCalendar else { return }
        isEnablingCalendar = true
        defer { isEnablingCalendar = false }
        let wasCompanionVisible = isCompanionVisible
        _ = await CalendarService.shared.requestAccess()
        let isAuthorized = CalendarService.shared.authStatus == .authorized
        if isAuthorized {
            settings.calendarIntegrationEnabled = true
            calendarLoadError = nil
            save()
            loadCalendars()
        } else {
            settings.calendarIntegrationEnabled = false
            availableCalendars = []
            calendarLoadError = "FocusFlow needs Calendar access. Enable it in System Settings → Privacy & Security → Calendars."
            save()
        }
        await ensureCompanionWindowIfNeeded(wasVisible: wasCompanionVisible)
    }

    private func loadCalendars() {
        guard settings.calendarIntegrationEnabled else {
            isLoadingCalendars = false
            calendarLoadError = nil
            availableCalendars = []
            return
        }
        guard CalendarService.shared.authStatus == .authorized else {
            isLoadingCalendars = false
            availableCalendars = []
            calendarLoadError = "Calendar permission is not granted."
            return
        }
        isLoadingCalendars = true
        calendarLoadError = nil
        availableCalendars = CalendarService.shared.availableCalendars()
        isLoadingCalendars = false
        if availableCalendars.isEmpty {
            calendarLoadError = "No writable calendars found in your connected accounts."
        }
    }

    private func loadReminderLists() {
        guard settings.remindersIntegrationEnabled else {
            isLoadingReminderLists = false
            reminderLoadError = nil
            availableReminderLists = []
            return
        }
        guard RemindersService.shared.authStatus == .authorized else {
            isLoadingReminderLists = false
            availableReminderLists = []
            reminderLoadError = "Reminders permission is not granted."
            return
        }
        isLoadingReminderLists = true
        reminderLoadError = nil
        availableReminderLists = RemindersService.shared.reminderLists()
        isLoadingReminderLists = false
        if availableReminderLists.isEmpty {
            reminderLoadError = "No reminder lists are available for this account."
            return
        }

        let selectedId = settings.selectedReminderListId
        let isSelectedListValid = !selectedId.isEmpty && availableReminderLists.contains(where: { $0.id == selectedId })
        if !isSelectedListValid, let first = availableReminderLists.first {
            settings.selectedReminderListId = first.id
            save()
        }
    }

    private func enableRemindersIntegration() async {
        guard !isEnablingReminders else { return }
        isEnablingReminders = true
        defer { isEnablingReminders = false }
        let wasCompanionVisible = isCompanionVisible
        _ = await RemindersService.shared.requestAccess()
        let isAuthorized = RemindersService.shared.authStatus == .authorized
        if isAuthorized {
            settings.remindersIntegrationEnabled = true
            reminderAuthError = nil
            reminderLoadError = nil
            save()
            loadReminderLists()
        } else {
            reminderAuthError = "FocusFlow needs Reminders access. Enable it in System Settings → Privacy & Security → Reminders."
            settings.remindersIntegrationEnabled = false
            availableReminderLists = []
            save()
        }
        await ensureCompanionWindowIfNeeded(wasVisible: wasCompanionVisible)
    }

    private var isCompanionVisible: Bool {
        NSApp.windows.contains { window in
            guard !(window is NSPanel) else { return false }
            if window.identifier?.rawValue == "stats" { return window.isVisible }
            return window.title == "FocusFlow" && window.isVisible
        }
    }

    @MainActor
    private func ensureCompanionWindowIfNeeded(wasVisible: Bool) async {
        guard wasVisible else { return }
        try? await Task.sleep(for: .milliseconds(80))
        guard !isCompanionVisible else { return }
        openWindow(id: "stats")
    }

    // MARK: - Focus Coach

    private var focusCoachSection: some View {
        LiquidGlassPanel {
            VStack(alignment: .leading, spacing: 12) {
                LiquidSectionHeader("Focus Coach", subtitle: "Gentle nudges to stay productive")

                // What it does — clear explanation before controls
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "brain.head.profile.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.indigo.opacity(0.8))
                        .padding(.top, 1)
                    Text("When you've been idle at your Mac without starting a session, FocusFlow sends a notification nudge to get you back into deep work.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)

                ToggleRow(
                    label: "Anti-procrastination nudges",
                    icon: "brain.head.profile.fill",
                    color: .indigo,
                    isOn: Binding(
                        get: { settings.antiProcrastinationEnabled },
                        set: { settings.antiProcrastinationEnabled = $0; save() }
                    )
                )

                if settings.antiProcrastinationEnabled {
                    HStack {
                        HStack(spacing: 8) {
                            Image(systemName: "clock.badge.exclamationmark")
                                .foregroundStyle(.indigo)
                                .font(.system(size: 13, weight: .semibold))
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Nudge after idle time")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text("Counts down when no session is active")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                            }
                        }

                        Spacer()

                        Stepper(
                            "\(settings.antiProcrastinationThresholdMinutes) min",
                            value: Binding(
                                get: { settings.antiProcrastinationThresholdMinutes },
                                set: { settings.antiProcrastinationThresholdMinutes = $0; save() }
                            ),
                            in: 2...15
                        )
                        .frame(width: 145)
                        .font(.subheadline)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(16)
            .animation(FFMotion.section, value: settings.antiProcrastinationEnabled)
        }
    }

    private func save() {
        saveWithFeedback(modelContext, errorBinding: $saveError)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        if enabled {
            try? SMAppService.mainApp.register()
        } else {
            try? SMAppService.mainApp.unregister()
        }
    }

    private let systemSounds = [
        "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero",
        "Morse", "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink"
    ]
}

private struct DurationRow: View {
    let label: String
    let icon: String
    let color: Color
    @Binding var minutes: Int
    let range: ClosedRange<Int>
    let step: Int

    var body: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .font(.system(size: 13, weight: .semibold))
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Stepper(
                "\(minutes) min",
                value: $minutes,
                in: range,
                step: step
            )
            .frame(width: 145)
            .font(.subheadline)
        }
    }
}

private struct ToggleRow: View {
    let label: String
    let icon: String
    let color: Color
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .font(.system(size: 13, weight: .semibold))
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch)
    }
}
