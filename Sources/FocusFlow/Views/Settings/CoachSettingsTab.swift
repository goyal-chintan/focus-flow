import SwiftUI
import SwiftData

/// Settings → Coach. Style and prompt budget first, then the existing before/during-session
/// controls, then the user's own motivation: "My why" and this week's priorities.
struct CoachSettingsTab: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(TimerViewModel.self) private var timerVM
    @Query private var allSettings: [AppSettings]
    @Query(filter: #Predicate<Project> { !$0.archived }, sort: \Project.createdAt) private var projects: [Project]
    @ObservedObject private var notificationService = NotificationService.shared

    @State private var saveError: String?
    @State private var showAdvanced = false
    @State private var isRequestingNotifications = false
    /// Shown after a switch to Gentle or Data while the pause screen is still on.
    @State private var showPauseScreenOffer = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var settings: AppSettings { allSettings.first ?? AppSettings() }
    private var bind: SettingsBinder {
        SettingsBinder(settings: settings) { saveWithFeedback(modelContext, errorBinding: $saveError) }
    }

    var body: some View {
        Form {
            styleSection
            promptsSection
            beforeSessionSection
            duringSessionSection
            rescueSection
            advancedSection
            myWhySection
            WeeklyPrioritiesSection(projects: projects, saveError: $saveError)
            debugSection
        }
        .formStyle(.grouped)
        .saveErrorOverlay($saveError)
    }

    // MARK: Style

    private var styleSection: some View {
        Section {
            Picker("Coaching style", selection: bind(\.coachStyle, onSet: styleDidChange)) {
                ForEach(CoachStyle.allCases, id: \.self) { style in
                    Text(style.displayName).tag(style)
                }
            }
            .pickerStyle(.segmented)

            CoachStylePreviewCard(
                style: settings.coachStyle,
                projectName: projects.first?.name ?? "your project"
            )

            if showPauseScreenOffer {
                pauseScreenOfferRow
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
        } header: {
            Text("Style")
        }
    }

    /// Offers, never forces, to turn the pause screen off when the user picks a softer style
    /// (the pause screen defaults off for Gentle and Data; rescue-loop design §3).
    private var pauseScreenOfferRow: some View {
        LabeledContent {
            HStack(spacing: 6) {
                Button("Keep On") {
                    setPauseScreenOffer(visible: false)
                }
                Button("Turn Off") {
                    settings.coachPauseScreenEnabled = false
                    save()
                    setPauseScreenOffer(visible: false)
                }
                .keyboardShortcut(.defaultAction)
            }
            .fixedSize()
        } label: {
            Text("Pause screen is on. Turn off for this style?")
        }
        .accessibilityIdentifier("settings.coach.pauseScreenOffer")
    }

    private func styleDidChange(_ style: CoachStyle) {
        setPauseScreenOffer(visible: Self.shouldOfferPauseScreenOff(style: style, pauseScreenEnabled: settings.coachPauseScreenEnabled))
    }

    private func setPauseScreenOffer(visible: Bool) {
        guard showPauseScreenOffer != visible else { return }
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.28)) {
            showPauseScreenOffer = visible
        }
    }

    /// Gentle and Data default the pause screen off, so offer to turn it off when it is on.
    static func shouldOfferPauseScreenOff(style: CoachStyle, pauseScreenEnabled: Bool) -> Bool {
        pauseScreenEnabled && style != .challenger
    }

    // MARK: Rescue

    /// Lengths offered for the one-click starter block.
    static let starterBlockChoices = [2, 5, 10]

    /// Snaps a stored length to the nearest offered choice, so the picker never shows blank.
    static func starterBlockChoice(for minutes: Int) -> Int {
        starterBlockChoices.min { abs($0 - minutes) < abs($1 - minutes) } ?? 5
    }

    private var rescueSection: some View {
        Section {
            Toggle("Show drift time in the menu bar", isOn: bind(\.coachShowDriftInMenuBar))

            Toggle(isOn: Binding(
                get: { settings.coachPauseScreenEnabled },
                set: { newValue in
                    settings.coachPauseScreenEnabled = newValue
                    save()
                    if !newValue { setPauseScreenOffer(visible: false) }
                }
            )) {
                Text("Pause screen when I spiral in a focus window")
                Text("A calm full-screen pause with one button to start 5 minutes. Never a lock.")
            }

            Picker("Starter block", selection: Binding(
                get: { Self.starterBlockChoice(for: settings.coachStarterBlockMinutes) },
                set: { settings.coachStarterBlockMinutes = $0; save() }
            )) {
                ForEach(Self.starterBlockChoices, id: \.self) { minutes in
                    Text("\(minutes) min").tag(minutes)
                }
            }

            Toggle("⌃⌥Space starts a starter block", isOn: bind(\.coachGlobalHotkeyEnabled))
        } header: {
            Text("Rescue")
        }
    }

    // MARK: Prompts

    private var promptsSection: some View {
        Section {
            Toggle("On-screen prompts", isOn: bind(\.coachOnScreenPromptsEnabled))

            Toggle("Also send notifications", isOn: Binding(
                get: { settings.coachNotificationsEnabled },
                set: { newValue in
                    settings.coachNotificationsEnabled = newValue
                    save()
                    if newValue {
                        requestNotificationPermission()
                    }
                }
            ))
            .disabled(isRequestingNotifications)

            if settings.coachNotificationsEnabled && notificationService.authorizationState == .denied {
                LabeledContent("Notifications are off for FocusFlow.") {
                    Button("Open System Settings") {
                        SystemSettingsLink.notifications()
                    }
                }
                .foregroundStyle(.secondary)
            }

            SettingsStepperRow(
                title: "Max prompts per day",
                valueText: "\(min(max(settings.coachMaxPromptsPerDay, 1), 6))",
                value: Binding(
                    get: { min(max(settings.coachMaxPromptsPerDay, 1), 6) },
                    set: { settings.coachMaxPromptsPerDay = $0; save() }
                ),
                range: 1...6
            )

            LabeledContent("Quiet hours") {
                HStack(spacing: 6) {
                    DatePicker(
                        "Quiet hours start",
                        selection: bind.minuteOfDay(\.coachQuietStartMinute),
                        displayedComponents: .hourAndMinute
                    )
                    .labelsHidden()
                    Text("to")
                        .foregroundStyle(.secondary)
                    DatePicker(
                        "Quiet hours end",
                        selection: bind.minuteOfDay(\.coachQuietEndMinute),
                        displayedComponents: .hourAndMinute
                    )
                    .labelsHidden()
                }
                .fixedSize()
            }
        } header: {
            Text("Prompts")
        } footer: {
            Text("No prompts during quiet hours.")
                .foregroundStyle(.secondary)
        }
    }

    private func requestNotificationPermission() {
        guard !isRequestingNotifications else { return }
        isRequestingNotifications = true
        Task { @MainActor in
            _ = await notificationService.requestPermission()
            isRequestingNotifications = false
            restoreSettingsWindow()
        }
    }

    // MARK: Existing coach controls

    private var beforeSessionSection: some View {
        Section {
            Toggle("Remind me to start", isOn: bind(\.antiProcrastinationEnabled))

            if settings.antiProcrastinationEnabled {
                SettingsStepperRow(
                    title: "First reminder after",
                    valueText: settingsMinutesText(settings.antiProcrastinationThresholdMinutes),
                    value: bind(\.antiProcrastinationThresholdMinutes),
                    range: 2...15
                )
                Toggle("Show the starter card", isOn: bind(\.coachIdleStarterEnabled))
            }
        } header: {
            Text("Before a session")
        }
    }

    private var duringSessionSection: some View {
        Section {
            Toggle("Coach me during sessions", isOn: bind(\.coachRealtimeEnabled))

            if settings.coachRealtimeEnabled {
                Picker("Escalation", selection: bind(\.coachInterventionMode)) {
                    ForEach(FocusCoachInterventionMode.allCases, id: \.rawValue) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                Toggle("Ask why I stopped or drifted", isOn: bind(\.coachReasonPromptsEnabled))
                SettingsStepperRow(
                    title: "Snooze for",
                    valueText: settingsMinutesText(settings.coachDefaultSnoozeMinutes),
                    value: bind(\.coachDefaultSnoozeMinutes),
                    range: 5...30,
                    step: 5
                )
            }
        } header: {
            Text("During a session")
        } footer: {
            if settings.coachRealtimeEnabled {
                Text(escalationFooter)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var advancedSection: some View {
        if settings.coachRealtimeEnabled {
            Section {
                DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                    SettingsStepperRow(
                        title: "Prompts per session",
                        valueText: "\(settings.coachPromptBudgetPerSession)",
                        value: bind(\.coachPromptBudgetPerSession),
                        range: 1...8
                    )
                    SettingsStepperRow(
                        title: "Strong prompts per session",
                        valueText: "\(settings.coachMaxStrongPromptsPerSession)",
                        value: bind(\.coachMaxStrongPromptsPerSession),
                        range: 1...6
                    )
                    Toggle("Bring FocusFlow to the front for strong prompts", isOn: bind(\.coachBringAppToFrontOnStrongPrompt))
                    Toggle("Open the menu bar panel for strong prompts", isOn: bind(\.coachAutoOpenPopoverOnStrongPrompt))
                    Toggle("Allow “Skip this check”", isOn: bind(\.coachAllowSkipAction))
                }
            }
        }
    }

    private var escalationFooter: String {
        switch settings.coachInterventionMode {
        case .balanced: "Balanced is the calmest."
        case .adaptiveStrict: "Adaptive Strict escalates faster when you drift."
        case .sessionRescue: "Session Rescue focuses on getting you back into the session."
        }
    }

    // MARK: My why

    private static let maxWhyLines = 5

    private var myWhySection: some View {
        Section {
            TextEditor(text: Binding(
                get: { settings.coachMyWhyText },
                set: { newValue in
                    settings.coachMyWhyText = Self.limitedWhyText(newValue)
                    save()
                }
            ))
            .font(.body)
            .scrollContentBackground(.hidden)
            .frame(height: 92)
            .overlay(alignment: .topLeading) {
                if settings.coachMyWhyText.isEmpty {
                    Text("Ship the side project by December")
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
            .accessibilityLabel("My why")
        } header: {
            HStack {
                Text("My why")
                Spacer()
                Text("\(settings.coachMyWhyLines.count)/\(Self.maxWhyLines) lines")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        } footer: {
            Text("One reason per line. Challenger quotes these back to you.")
                .foregroundStyle(.secondary)
        }
    }

    /// Keeps at most five lines.
    static func limitedWhyText(_ text: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count > maxWhyLines else { return text }
        return lines.prefix(maxWhyLines).joined(separator: "\n")
    }

    // MARK: Debug

    @ViewBuilder
    private var debugSection: some View {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "FocusFlowShowCoachDebug") == true {
            Section {
                LabeledContent("Window strength", value: "\(Int(timerVM.latestWorkIntentScore * 100))%")
                LabeledContent("Pacing pressure", value: "\(Int(timerVM.latestDriftScore * 100))%")
                LabeledContent("Work-intent signals", value: joinedSignals(timerVM.latestWorkIntentActiveSignals))
                LabeledContent("Drift signals", value: joinedSignals(timerVM.latestDriftActiveSignals))
                LabeledContent("Last suppression", value: timerVM.lastIdleStarterSuppressionReason?.debugLabel ?? "none")
            } header: {
                Text("Outside-session signal debug")
            }
        }
        #endif
    }

    private func joinedSignals(_ signals: [String]) -> String {
        signals.isEmpty ? "none" : signals.joined(separator: ", ")
    }

    private func save() {
        saveWithFeedback(modelContext, errorBinding: $saveError)
    }
}

// MARK: - Style preview

/// A sample prompt in the chosen style (copy from the coach v2 design §4.1).
struct CoachStylePreviewCard: View {
    let style: CoachStyle
    let projectName: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var symbol: String {
        switch style {
        case .gentle: "leaf"
        case .data: "chart.bar"
        case .challenger: "flame"
        }
    }

    /// Real composer output for a sample mid-day state: a five-day streak, one block done, 43 of 120 minutes.
    private var composed: CoachComposedMessage {
        CoachMessageComposer.compose(CoachComposerInput(
            style: style,
            trigger: .startNudge,
            facts: CoachFacts(streakDays: 5, hasHistory: true, sessionsToday: 1, doneMinutesToday: 43, goalMinutes: 120),
            target: CoachStartTarget(minutes: 25, name: projectName)
        ))
    }

    private var headline: String { composed.hook }

    private var message: String { composed.detail?.text ?? composed.primaryTitle }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.accentColor.opacity(0.14)))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(headline)
                    .font(.body.weight(.semibold))
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .id(style)
            .transition(.opacity)
        }
        .padding(.vertical, 4)
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: style)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Preview: \(headline) \(message)")
    }
}
