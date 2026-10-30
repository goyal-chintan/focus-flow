import SwiftUI
import SwiftData

/// Settings → Coach (screen audit 2026-10-28). Four groups: the style, starting, the limits the
/// learner never crosses, and during a block. What v5 learns (when to ask, which size) has no knob;
/// weekly priorities are retired in favour of goals and daily tasks.
struct CoachSettingsTab: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(TimerViewModel.self) private var timerVM
    @Query private var allSettings: [AppSettings]
    @Query(filter: #Predicate<Project> { !$0.archived }, sort: \Project.createdAt) private var projects: [Project]
    @ObservedObject private var notificationService = NotificationService.shared

    @State private var saveError: String?
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
            startingSection
            limitsSection
            duringSessionSection
            myWhySection
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
                projectName: projects.min { ($0.priorityRank ?? .max) < ($1.priorityRank ?? .max) }?.name ?? "your #1",
                lever: GoalDataBuilder.levers(timerVM.historyReaderActiveGoals(), now: Date()).first?.action,
                suggestedMinutes: timerVM.startLadderRecommendation().minutes
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

    // MARK: Starting

    private var startingSection: some View {
        Section {
            // One switch for the whole start loop: start prompts and the start card.
            Toggle(isOn: Binding(
                get: { settings.antiProcrastinationEnabled && settings.coachIdleStarterEnabled },
                set: { newValue in
                    settings.antiProcrastinationEnabled = newValue
                    settings.coachIdleStarterEnabled = newValue
                    save()
                }
            )) {
                Text("Help me start")
                Text("Asks only when you're at your desk, and offers 5, 15 or 25 minutes.")
            }

            Toggle("⌃⌥Space starts a block from anywhere", isOn: bind(\.coachGlobalHotkeyEnabled))

            Toggle(isOn: Binding(
                get: { settings.coachPauseScreenEnabled },
                set: { newValue in
                    settings.coachPauseScreenEnabled = newValue
                    save()
                    if !newValue { setPauseScreenOffer(visible: false) }
                }
            )) {
                Text("Pause screen when I spiral in a focus window")
                Text("A calm full-screen pause with one button to start a short block. Never a lock.")
            }

            Toggle("Show drift time in the menu bar", isOn: bind(\.coachShowDriftInMenuBar))
        } header: {
            Text("Starting")
        } footer: {
            Text("The coach learns when to ask and which size to offer. See Insights → Is the coach getting you started?")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Prompts

    private var limitsSection: some View {
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
            Text("Limits")
        } footer: {
            Text("The coach learns inside these limits. It never goes past them, and stays quiet during quiet hours.")
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

    // MARK: During a block

    private var duringSessionSection: some View {
        Section {
            Toggle("Coach me during blocks", isOn: bind(\.coachRealtimeEnabled))

            if settings.coachRealtimeEnabled {
                SettingsStepperRow(
                    title: "Snooze for",
                    valueText: settingsMinutesText(settings.coachDefaultSnoozeMinutes),
                    value: bind(\.coachDefaultSnoozeMinutes),
                    range: 5...30,
                    step: 5
                )
            }
        } header: {
            Text("During a block")
        } footer: {
            Text("Nudges you back when a distraction takes over a block. Distractions decides which apps and sites count.")
                .foregroundStyle(.secondary)
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
            Text("One reason per line. The coach quotes them back to you when you need a push.")
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

/// What this style would say to you now: the real composer, fed your #1 project and today's lever,
/// with the same 5 · 15 · 25 choice the start card shows (v4 §3.3: start prompts never cite the daily goal).
struct CoachStylePreviewCard: View {
    let style: CoachStyle
    let projectName: String
    var lever: String?
    var suggestedMinutes: Int = 15

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var symbol: String {
        switch style {
        case .gentle: "leaf"
        case .data: "chart.bar"
        case .challenger: "flame"
        }
    }

    private var composed: CoachComposedMessage {
        var facts = CoachFacts(streakDays: 5, hasHistory: true, sessionsToday: 1)
        facts.lever = lever
        var target = CoachStartTarget(minutes: suggestedMinutes, name: projectName)
        target.taskTitle = lever
        return CoachMessageComposer.compose(CoachComposerInput(style: style, trigger: .startNudge, facts: facts, target: target))
    }

    private var headline: String { composed.hook }

    private var message: String { composed.detail?.text ?? lever.map { "Next: \($0)" } ?? "Start on \(projectName)." }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.accentColor.opacity(0.14)))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(headline)
                    .font(.body.weight(.semibold))
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    ForEach(CoachBlockSizeLadder.sizes, id: \.self) { minutes in
                        Text("\(minutes) min")
                            .font(.caption.weight(minutes == suggestedMinutes ? .semibold : .regular))
                            .foregroundStyle(minutes == suggestedMinutes ? Color.white : Color.primary)
                            .padding(.horizontal, 9)
                            .frame(height: 20)
                            .background(Capsule().fill(minutes == suggestedMinutes ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.primary.opacity(0.07))))
                    }
                    Text("Not now, because…").font(.caption).foregroundStyle(.secondary)
                }
                .padding(.top, 2)
                .accessibilityHidden(true)
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
