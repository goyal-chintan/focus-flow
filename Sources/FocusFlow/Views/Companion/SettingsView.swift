import SwiftUI
import SwiftData
import ServiceManagement

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allSettings: [AppSettings]

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
                integrationsSection
                focusCoachSection
                aboutSection
            }
            .padding(24)
        }
        .background(.ultraThinMaterial)
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
                LiquidSectionHeader("Sound", subtitle: "Choose the completion chime")

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
            }
            .padding(16)
        }
    }

    private var aboutSection: some View {
        LiquidGlassPanel {
            VStack(spacing: 12) {
                LiquidSectionHeader("About", subtitle: "FocusFlow companion app")

                Image(systemName: "timer")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(.tint)

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
                }

                if settings.calendarIntegrationEnabled {
                    calendarPickerSection
                }
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

    @State private var availableCalendars: [(source: String, calendars: [(id: String, title: String)])] = []

    private var calendarPickerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()

            Text("Select which calendar to record sessions to:")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            if availableCalendars.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Loading calendars...")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                .onAppear { loadCalendars() }
            } else {
                ForEach(availableCalendars, id: \.source) { group in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(group.source)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.tertiary)
                            .textCase(.uppercase)
                            .padding(.top, 4)

                        ForEach(group.calendars, id: \.id) { cal in
                            calendarRow(cal, isSelected: settings.selectedCalendarId == cal.id)
                        }
                    }
                }

                // Option to create a dedicated FocusFlow calendar
                Divider()
                calendarRow((id: "__create_new__", title: "Create \"FocusFlow\" Calendar"),
                            isSelected: settings.selectedCalendarId.isEmpty || settings.selectedCalendarId == "__create_new__")
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func calendarRow(_ cal: (id: String, title: String), isSelected: Bool) -> some View {
        Button {
            if cal.id == "__create_new__" {
                settings.selectedCalendarId = ""
                settings.calendarName = "FocusFlow"
            } else {
                settings.selectedCalendarId = cal.id
                settings.calendarName = cal.title
            }
            save()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(isSelected ? .blue : .secondary)

                Text(cal.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)

                Spacer()
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func enableCalendarIntegration() async {
        let granted = await CalendarService.shared.requestAccess()
        if granted {
            settings.calendarIntegrationEnabled = true
            save()
            loadCalendars()
        }
    }

    private func loadCalendars() {
        availableCalendars = CalendarService.shared.availableCalendars()
    }

    // MARK: - Focus Coach

    private var focusCoachSection: some View {
        LiquidGlassPanel {
            VStack(alignment: .leading, spacing: 12) {
                LiquidSectionHeader("Focus Coach", subtitle: "Gentle nudges to stay productive")

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
                            Text("Nudge after")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
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
        try? modelContext.save()
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
