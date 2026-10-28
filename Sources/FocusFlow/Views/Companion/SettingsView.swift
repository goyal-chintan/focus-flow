import SwiftUI
import SwiftData
import ServiceManagement
import CoreGraphics

// MARK: - Settings scene root

/// Tabs of the Settings scene (⌘,), shown in FocusFlow's own toolbar tab bar.
enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case timer
    case coach
    case distractions
    /// Shown as "Permissions". The raw value stays "integrations" so stored selections and
    /// `settingsRequestedTab` values from earlier builds still resolve.
    case integrations

    /// UserDefaults key that remembers the last selected tab.
    static let storageKey = "settingsSelectedTab"
    /// One-shot UserDefaults key: a raw tab value that opens Settings on that tab, then is cleared.
    static let requestedTabKey = "settingsRequestedTab"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .timer: "Timer"
        case .coach: "Coach"
        case .distractions: "Distractions"
        case .integrations: "Permissions"
        }
    }

    var icon: String {
        switch self {
        case .general: "gearshape"
        case .timer: "timer"
        case .coach: "brain.head.profile"
        case .distractions: "hand.raised"
        case .integrations: "lock.shield"
        }
    }

    /// Position in the tab bar (0-based). Drives the slide direction and the ⌘1–⌘5 shortcuts.
    var order: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    /// Reads and clears the one-shot `settingsRequestedTab` request. Returns nil when there is
    /// no request or the value is not a known tab (an unknown value is cleared as well).
    static func consumeRequestedTab(from defaults: UserDefaults = .standard) -> SettingsTab? {
        guard let raw = defaults.string(forKey: requestedTabKey) else { return nil }
        defaults.removeObject(forKey: requestedTabKey)
        return SettingsTab(rawValue: raw)
    }
}

/// Root of the `Settings` scene: a custom toolbar tab bar plus one content container keyed by
/// the selected tab, so tab switches cross-fade with a short directional slide. The native
/// `TabView` swaps hosting controllers and cannot animate, which is why it is not used here.
struct SettingsView: View {
    enum ScrollTarget {
        case integrations
        case domainTracking
    }

    /// The persisted selection. Tab bar clicks, ⌘1–⌘5, `settingsRequestedTab` and other views
    /// (Distractions links here) all write this; `shownTab` follows it with animation.
    @AppStorage(SettingsTab.storageKey) private var selectedTab: SettingsTab = .general
    /// The tab on screen. Changes one update after `slideDirection`, so the outgoing page
    /// already carries the new direction when it is removed.
    @State private var shownTab: SettingsTab
    @State private var pendingTab: SettingsTab?
    @State private var slideDirection: SettingsTabSlideDirection = .forward
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let initialScrollTarget: ScrollTarget?

    init(initialScrollTarget: ScrollTarget? = nil) {
        self.initialScrollTarget = initialScrollTarget
        let stored = UserDefaults.standard.string(forKey: SettingsTab.storageKey).flatMap(SettingsTab.init(rawValue:))
        _shownTab = State(initialValue: initialScrollTarget != nil ? .integrations : (stored ?? .general))
    }

    var body: some View {
        SettingsTabContainer(
            tab: shownTab,
            direction: slideDirection,
            reduceMotion: reduceMotion,
            initialScrollTarget: initialScrollTarget
        )
        .background {
            SettingsTabShortcuts(selection: $selectedTab)
        }
        .navigationTitle(shownTab.title)
        .toolbar {
            ToolbarItem(placement: .principal) {
                SettingsTabBar(selection: shownTab) { selectedTab = $0 }
            }
            .sharedBackgroundVisibility(.hidden)
        }
        .onChange(of: selectedTab) { _, newValue in
            requestShow(newValue)
        }
        .onChange(of: pendingTab) { _, newValue in
            // Second step: the direction is already applied to the outgoing page.
            guard let newValue else { return }
            pendingTab = nil
            shownTab = newValue
        }
        .onAppear {
            if initialScrollTarget != nil {
                selectedTab = .integrations
            } else if selectedTab != shownTab {
                shownTab = selectedTab
            }
            applyRequestedTabIfNeeded()
        }
        // Settings may already be open when the weekly-priorities invite writes the request.
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            applyRequestedTabIfNeeded()
        }
    }

    /// First step of a tab switch: set the slide direction, then show the tab on the next update.
    private func requestShow(_ tab: SettingsTab) {
        guard tab != shownTab else { return }
        slideDirection = SettingsTabSlideDirection(from: shownTab, to: tab)
        pendingTab = tab
    }

    /// Opens the tab a caller requested through `settingsRequestedTab` (the weekly-priorities
    /// invite writes "coach"), then clears the key so the request happens once. The switch goes
    /// through `selectedTab`, so it animates like a click.
    private func applyRequestedTabIfNeeded() {
        guard let requested = SettingsTab.consumeRequestedTab() else { return }
        selectedTab = requested
    }

    // MARK: Domain tracking recovery (pure logic, unit tested)

    static func hasValidCapturedBrowserDomains(in entries: [AppUsageEntry]) -> Bool {
        entries.contains { entry in
            CompanionAnalyticsBuilder.validPersistedDomainHost(for: entry.bundleIdentifier) != nil
            && (entry.duringFocusSeconds > 0 || entry.outsideFocusSeconds > 0)
        }
    }

    static func domainTrackingRecoveryState(
        collectRawDomains: Bool,
        hasCapturedBrowserDomains: Bool,
        frontmostBundleIdentifier: String?,
        screenRecordingAccess: Bool,
        automationStatusProvider: (String?) -> PermissionHealthStatus?
    ) -> DomainTrackingRecoveryState? {
        if collectRawDomains == false {
            return .disabled
        }

        guard !hasCapturedBrowserDomains else { return nil }

        if let frontmostBundleId = frontmostBundleIdentifier,
           AppUsageEntry.isBrowserBundleIdentifier(frontmostBundleId) {
            if BrowserDomainResolver.supports(bundleIdentifier: frontmostBundleId) {
                if automationStatusProvider(frontmostBundleId) != .ready {
                    return .automationUnavailable
                }
            } else if !screenRecordingAccess {
                return .screenRecordingUnavailable
            }
        }

        return .awaitingFirstCapture
    }
}

// MARK: - Tab content

/// The content of one Settings tab. Used by the scene and by the evidence renders.
struct SettingsTabContent: View {
    let tab: SettingsTab
    var initialScrollTarget: SettingsView.ScrollTarget? = nil

    var body: some View {
        switch tab {
        case .general: GeneralSettingsTab()
        case .timer: TimerSettingsTab()
        case .coach: CoachSettingsTab()
        case .distractions: DistractionsView()
        case .integrations: IntegrationsSettingsTab(initialScrollTarget: initialScrollTarget)
        }
    }
}

// MARK: - Shared helpers

enum SystemSettingsLink {
    static func open(_ urlString: String) {
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    static func notifications() { open("x-apple.systempreferences:com.apple.Notifications-Settings") }
    static func calendars() { open("x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") }
    static func reminders() { open("x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders") }
    static func automation() { open("x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") }
    static func screenRecording() { open("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") }
}

/// Brings the Settings window back to the front after a system permission prompt took focus.
@MainActor
func restoreSettingsWindow() {
    NSApplication.shared.activate(ignoringOtherApps: true)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
        if let window = NSApp.windows.first(where: {
            $0.isVisible && ($0.identifier?.rawValue.localizedCaseInsensitiveContains("settings") == true)
        }) {
            window.makeKeyAndOrderFront(nil)
        }
    }
}

// MARK: - General

private struct GeneralSettingsTab: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(TimerViewModel.self) private var timerVM
    @Query private var allSettings: [AppSettings]
    @State private var saveError: String?
    @State private var loginItemStatus: SMAppService.Status = SMAppService.mainApp.status
    @State private var loginItemError: String?

    private var settings: AppSettings { allSettings.first ?? AppSettings() }
    private var bind: SettingsBinder {
        SettingsBinder(settings: settings) { saveWithFeedback(modelContext, errorBinding: $saveError) }
    }

    var body: some View {
        Form {
            Section {
                Toggle("Open FocusFlow at login", isOn: Binding(
                    get: { loginItemStatus == .enabled || loginItemStatus == .requiresApproval },
                    set: { setLaunchAtLogin($0) }
                ))

                if loginItemStatus == .requiresApproval {
                    LabeledContent("macOS needs your approval in Login Items.") {
                        Button("Open Login Items") {
                            SMAppService.openSystemSettingsLoginItems()
                        }
                    }
                }

                if let loginItemError {
                    Text(loginItemError)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Startup")
            }

            Section {
                LabeledContent {
                    Button("Show the welcome tour") { timerVM.openOnboarding?() }
                } label: {
                    Text("Welcome tour")
                    Text("Pick your #1, a goal and a coach style again. Takes a minute.")
                }
            } header: {
                Text("Getting started")
            }

            Section {
                Toggle("Show FocusFlow around the notch", isOn: Binding(
                    get: { timerVM.isNotchCompanionEnabled },
                    set: { timerVM.setNotchCompanionEnabled($0) }
                ))
            } header: {
                Text("Notch")
            } footer: {
                Text("A ring and the time beside the notch. Hover it for controls, today's lever and one-click starts. Without a notch it sits at the top of the screen.")
                    .foregroundStyle(.secondary)
            }

            Section {
                SettingsStepperRow(
                    title: "Personal focus goal",
                    valueText: settingsGoalText(minutes: focusGoalMinutes),
                    value: Binding(
                        get: { focusGoalMinutes },
                        set: { newValue in
                            settings.dailyFocusGoal = TimeInterval(newValue * 60)
                            // Stretch always sits at or above the personal goal.
                            if settings.dailyStretchGoal < settings.dailyFocusGoal {
                                settings.dailyStretchGoal = settings.dailyFocusGoal
                            }
                            save()
                        }
                    ),
                    range: 30...480,
                    step: 15
                )
                SettingsStepperRow(
                    title: "Stretch goal",
                    valueText: settingsGoalText(minutes: stretchGoalMinutes),
                    value: Binding(
                        get: { stretchGoalMinutes },
                        set: { settings.dailyStretchGoal = TimeInterval($0 * 60); save() }
                    ),
                    range: max(30, focusGoalMinutes)...600,
                    step: 15
                )
            } header: {
                Text("Daily goals")
            } footer: {
                Text("Stretch is the bonus target once the personal goal is met.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Resume after a short sleep", isOn: bind(\.autoResumeOnWake))

                if settings.autoResumeOnWake {
                    SettingsStepperRow(
                        title: "Short sleep is under",
                        valueText: settingsMinutesText(settings.autoResumeThresholdSeconds / 60),
                        value: Binding(
                            get: { settings.autoResumeThresholdSeconds / 60 },
                            set: { settings.autoResumeThresholdSeconds = $0 * 60; save() }
                        ),
                        range: 1...10
                    )
                }

                SettingsStepperRow(
                    title: "End the session after sleeping",
                    valueText: settingsMinutesText(settings.autoStopOnSleepThresholdMinutes),
                    value: bind(\.autoStopOnSleepThresholdMinutes),
                    range: 5...240,
                    step: 5
                )
            } header: {
                Text("Sleep")
            } footer: {
                Text(sleepFooter)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .saveErrorOverlay($saveError)
        .onAppear(perform: refreshLoginItemStatus)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshLoginItemStatus()
        }
    }

    private var focusGoalMinutes: Int { Int(settings.dailyFocusGoal / 60) }
    private var stretchGoalMinutes: Int { max(Int(settings.dailyStretchGoal / 60), focusGoalMinutes) }

    private var sleepFooter: String {
        if settings.autoResumeOnWake {
            return "Sessions pause while your Mac sleeps, resume after a short sleep and end after a long one."
        }
        return "Sessions pause while your Mac sleeps and end after a long sleep."
    }

    private func save() {
        saveWithFeedback(modelContext, errorBinding: $saveError)
    }

    private func refreshLoginItemStatus() {
        loginItemStatus = SMAppService.mainApp.status
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginItemError = nil
        } catch {
            loginItemError = "Couldn't change the login item: \(error.localizedDescription)"
        }
        refreshLoginItemStatus()
        settings.launchAtLogin = loginItemStatus == .enabled || loginItemStatus == .requiresApproval
        save()
    }
}

// MARK: - Timer

private struct TimerSettingsTab: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allSettings: [AppSettings]
    @State private var saveError: String?

    private var settings: AppSettings { allSettings.first ?? AppSettings() }
    private var bind: SettingsBinder {
        SettingsBinder(settings: settings) { saveWithFeedback(modelContext, errorBinding: $saveError) }
    }

    var body: some View {
        Form {
            Section {
                durationRow("Focus", keyPath: \.focusDuration, range: 5...120, step: 5)
                durationRow("Short break", keyPath: \.shortBreakDuration, range: 1...30, step: 1)
                durationRow("Long break", keyPath: \.longBreakDuration, range: 5...60, step: 5)
                SettingsStepperRow(
                    title: "Sessions before a long break",
                    valueText: "\(settings.sessionsBeforeLongBreak)",
                    value: bind(\.sessionsBeforeLongBreak),
                    range: 2...8
                )
            } header: {
                Text("Durations")
            }

            Section {
                LabeledContent("Completion sound") {
                    HStack(spacing: 6) {
                        Picker("Completion sound", selection: bind(\.completionSound, onSet: playSound)) {
                            ForEach(Self.systemSounds, id: \.self) { sound in
                                Text(sound).tag(sound)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()

                        Button {
                            playSound(settings.completionSound)
                        } label: {
                            Image(systemName: "play.fill")
                        }
                        .buttonStyle(.borderless)
                        .help("Play sound")
                        .accessibilityLabel("Play completion sound")
                    }
                }
            } header: {
                Text("Sound")
            }
        }
        .formStyle(.grouped)
        .saveErrorOverlay($saveError)
    }

    private func durationRow(
        _ title: String,
        keyPath: ReferenceWritableKeyPath<AppSettings, TimeInterval>,
        range: ClosedRange<Int>,
        step: Int
    ) -> some View {
        let minutes = Int(settings[keyPath: keyPath] / 60)
        return SettingsStepperRow(
            title: title,
            valueText: settingsMinutesText(minutes),
            value: Binding(
                get: { Int(settings[keyPath: keyPath] / 60) },
                set: { settings[keyPath: keyPath] = TimeInterval($0 * 60); saveWithFeedback(modelContext, errorBinding: $saveError) }
            ),
            range: range,
            step: step
        )
    }

    private func playSound(_ name: String) {
        NSSound(named: NSSound.Name(name))?.play()
    }

    static let systemSounds = [
        "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero",
        "Morse", "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink"
    ]
}

// MARK: - Permissions (calendar, reminders, browser domains)

private struct IntegrationsSettingsTab: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allSettings: [AppSettings]
    @Query(sort: \AppUsageEntry.date) private var appUsageEntries: [AppUsageEntry]
    @StateObject private var notificationService = NotificationService.shared

    @State private var availableCalendars: [(source: String, calendars: [(id: String, title: String)])] = []
    @State private var availableReminderLists: [(id: String, title: String, source: String)] = []
    @State private var calendarLoadError: String?
    @State private var reminderLoadError: String?
    @State private var reminderAuthError: String?
    @State private var isRequestingNotificationPermission = false
    @State private var isEnablingCalendar = false
    @State private var isEnablingReminders = false
    @State private var saveError: String?
    @State private var permissionHealthRows: [PermissionHealthRow] = []
    @State private var permissionHealthRefreshToken = 0

    let initialScrollTarget: SettingsView.ScrollTarget?

    private var settings: AppSettings { allSettings.first ?? AppSettings() }
    private var bind: SettingsBinder {
        SettingsBinder(settings: settings) { saveWithFeedback(modelContext, errorBinding: $saveError) }
    }

    var body: some View {
        ScrollViewReader { proxy in
            Form {
                permissionsSection
                calendarSection
                    .id("calendar")
                remindersSection
                    .id("reminders")
                browserDomainsSection
                    .id("domainTracking")
            }
            .formStyle(.grouped)
            .saveErrorOverlay($saveError)
            .onAppear {
                refreshPermissionHealth()
                if settings.calendarIntegrationEnabled {
                    loadCalendars()
                }
                if settings.remindersIntegrationEnabled {
                    loadReminderLists()
                }
                if initialScrollTarget == .domainTracking {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        proxy.scrollTo("domainTracking", anchor: .top)
                    }
                }
            }
            // When EventStoreManager auto-disables integration flags because
            // TCC permissions were revoked, refresh the calendar/reminder lists
            // so the UI reflects the actual state immediately.
            .onReceive(NotificationCenter.default.publisher(for: EventStoreManager.permissionsDidChange)) { _ in
                availableCalendars = []
                availableReminderLists = []
                calendarLoadError = nil
                reminderLoadError = nil
                reminderAuthError = nil
                refreshPermissionHealth()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                refreshPermissionHealth()
            }
        }
    }

    // MARK: Permissions

    /// Calendar and Reminders permissions are shown inside their own sections, so each
    /// permission appears exactly once on this tab.
    private var permissionsSection: some View {
        Section {
            ForEach(permissionHealthRows.filter { $0.kind != .calendar && $0.kind != .reminders }) { row in
                permissionRow(row)
            }
        } header: {
            Text("Permissions")
        }
    }

    private func permissionRow(_ row: PermissionHealthRow) -> some View {
        LabeledContent {
            Button(row.actionTitle) {
                handlePermissionAction(row.action)
            }
            .disabled(row.action == .requestNotifications && isRequestingNotificationPermission)
            .accessibilityIdentifier(permissionActionIdentifier(for: row.kind))
            .accessibilityLabel(permissionActionLabel(for: row.kind))
        } label: {
            Text("\(Text(Image(systemName: "circle.fill")).foregroundStyle(permissionTint(for: row.status)).font(.system(size: 8))) \(row.title)")
                .accessibilityLabel("\(row.title), \(row.status.title)")
            Text(row.message)
            ForEach(row.detailLines, id: \.self) { detail in
                Text(detail)
            }
        }
    }

    private func permissionRow(kind: PermissionHealthRow.Kind) -> PermissionHealthRow? {
        permissionHealthRows.first { $0.kind == kind }
    }

    private func permissionTint(for status: PermissionHealthStatus) -> Color {
        switch status {
        case .ready: .green
        case .needsAction: .orange
        case .notRequested: .secondary
        case .unavailable: .secondary
        }
    }

    private func permissionActionIdentifier(for kind: PermissionHealthRow.Kind) -> String {
        switch kind {
        case .notifications: "settings.permissionHealth.notifications.action"
        case .calendar: "settings.permissionHealth.calendar.action"
        case .reminders: "settings.permissionHealth.reminders.action"
        case .automation: "settings.permissionHealth.automation.action"
        case .screenRecording: "settings.permissionHealth.screenRecording.action"
        }
    }

    private func permissionActionLabel(for kind: PermissionHealthRow.Kind) -> String {
        switch kind {
        case .notifications: "Review notification permission"
        case .calendar: "Review Calendar permission"
        case .reminders: "Review Reminders permission"
        case .automation: "Review browser Automation permission"
        case .screenRecording: "Review Screen Recording permission"
        }
    }

    private func handlePermissionAction(_ action: PermissionHealthAction) {
        switch action {
        case .requestNotifications:
            guard !isRequestingNotificationPermission else { return }
            isRequestingNotificationPermission = true
            Task { @MainActor in
                _ = await notificationService.requestPermission()
                isRequestingNotificationPermission = false
                refreshPermissionHealth()
                restoreSettingsWindow()
            }
        case .openNotificationSettings:
            SystemSettingsLink.notifications()
        case .requestCalendarPermission:
            Task { @MainActor in
                _ = await CalendarService.shared.requestAccess()
                refreshPermissionHealth()
                restoreSettingsWindow()
            }
        case .openCalendarSettings:
            SystemSettingsLink.calendars()
        case .requestRemindersPermission:
            Task { @MainActor in
                _ = await RemindersService.shared.requestAccess()
                refreshPermissionHealth()
                restoreSettingsWindow()
            }
        case .openRemindersSettings:
            SystemSettingsLink.reminders()
        case .openIntegrationsSection:
            // The Calendar and Reminders sections are on this tab already.
            break
        case .openAutomationSettings:
            SystemSettingsLink.automation()
        case .openScreenRecordingSettings:
            SystemSettingsLink.screenRecording()
        }
    }

    /// Shows the Calendar/Reminders permission row inside its integration section
    /// when access is missing. When access is granted the toggle alone is enough.
    @ViewBuilder
    private func inlinePermissionRow(kind: PermissionHealthRow.Kind) -> some View {
        if let row = permissionRow(kind: kind),
           row.status != .ready,
           row.action != .openIntegrationsSection {
            permissionRow(row)
        }
    }

    private func refreshPermissionHealth() {
        notificationService.refreshAuthorizationStatus()
        permissionHealthRefreshToken += 1
        let refreshToken = permissionHealthRefreshToken
        let calendarIntegrationEnabled = settings.calendarIntegrationEnabled
        let remindersIntegrationEnabled = settings.remindersIntegrationEnabled
        let service = PermissionHealthService()
        let targets = service.installedAutomationTargets()

        permissionHealthRows = service.rows(
            calendarIntegrationEnabled: calendarIntegrationEnabled,
            remindersIntegrationEnabled: remindersIntegrationEnabled,
            automationProbeInProgress: !targets.isEmpty
        )

        guard !targets.isEmpty else { return }

        DispatchQueue.global(qos: .utility).async {
            let statuses = BrowserAutomationPermissionProbe.statuses(for: targets)
            DispatchQueue.main.async {
                guard refreshToken == permissionHealthRefreshToken else { return }
                permissionHealthRows = PermissionHealthService().rows(
                    calendarIntegrationEnabled: calendarIntegrationEnabled,
                    remindersIntegrationEnabled: remindersIntegrationEnabled,
                    automationStatuses: statuses
                )
            }
        }
    }

    // MARK: Calendar

    private var calendarSection: some View {
        Section {
            Toggle("Record sessions to Calendar", isOn: Binding(
                get: { settings.calendarIntegrationEnabled },
                set: { newValue in
                    if newValue {
                        Task { @MainActor in await enableCalendarIntegration() }
                    } else {
                        settings.calendarIntegrationEnabled = false
                        settings.selectedCalendarId = ""
                        save()
                        refreshPermissionHealth()
                    }
                }
            ))
            .disabled(isEnablingCalendar)

            inlinePermissionRow(kind: .calendar)

            if settings.calendarIntegrationEnabled {
                if let calendarLoadError {
                    LabeledContent(calendarLoadError) {
                        Button("Reload") { loadCalendars() }
                    }
                } else {
                    Picker("Calendar", selection: Binding(
                        get: { settings.selectedCalendarId.isEmpty ? "__create_new__" : settings.selectedCalendarId },
                        set: { newValue in
                            if newValue == "__create_new__" {
                                settings.selectedCalendarId = ""
                                settings.calendarName = "FocusFlow"
                            } else {
                                settings.selectedCalendarId = newValue
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
                        Text("New “FocusFlow” calendar").tag("__create_new__")
                    }
                }
            }
        } header: {
            Text("Calendar")
        } footer: {
            if settings.calendarIntegrationEnabled {
                Text("Completed and saved sessions appear with a 🎯 prefix. Earlier sessions aren't added.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @MainActor private func enableCalendarIntegration() async {
        guard !isEnablingCalendar else { return }
        isEnablingCalendar = true
        defer { isEnablingCalendar = false }
        _ = await CalendarService.shared.requestAccess()
        if CalendarService.shared.authStatus == .authorized {
            settings.calendarIntegrationEnabled = true
            calendarLoadError = nil
            save()
            loadCalendars()
        } else {
            settings.calendarIntegrationEnabled = false
            availableCalendars = []
            save()
        }
        refreshPermissionHealth()
        restoreSettingsWindow()
    }

    private func loadCalendars() {
        guard settings.calendarIntegrationEnabled else {
            calendarLoadError = nil
            availableCalendars = []
            return
        }
        guard CalendarService.shared.authStatus == .authorized else {
            availableCalendars = []
            calendarLoadError = "Calendar permission is not granted."
            return
        }
        calendarLoadError = nil
        availableCalendars = CalendarService.shared.availableCalendars()
        if availableCalendars.isEmpty {
            calendarLoadError = "No writable calendars found."
        }
    }

    // MARK: Reminders

    private var remindersSection: some View {
        Section {
            Toggle("Sync Reminders", isOn: Binding(
                get: { settings.remindersIntegrationEnabled },
                set: { newValue in
                    if newValue {
                        Task { @MainActor in await enableRemindersIntegration() }
                    } else {
                        settings.remindersIntegrationEnabled = false
                        settings.selectedReminderListId = ""
                        reminderAuthError = nil
                        save()
                        refreshPermissionHealth()
                    }
                }
            ))
            .disabled(isEnablingReminders)

            inlinePermissionRow(kind: .reminders)

            if let reminderAuthError {
                Text(reminderAuthError)
                    .foregroundStyle(.secondary)
            }

            if settings.remindersIntegrationEnabled {
                if let reminderLoadError {
                    LabeledContent(reminderLoadError) {
                        Button("Reload") { loadReminderLists() }
                    }
                } else {
                    Picker("List for new reminders", selection: bind(\.selectedReminderListId)) {
                        ForEach(availableReminderLists, id: \.id) { list in
                            Text(list.title).tag(list.id)
                        }
                    }
                }
            }
        } header: {
            Text("Reminders")
        } footer: {
            if settings.remindersIntegrationEnabled {
                Text("The Calendar tab shows incomplete reminders from every list.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func loadReminderLists() {
        guard settings.remindersIntegrationEnabled else {
            reminderLoadError = nil
            availableReminderLists = []
            return
        }
        guard RemindersService.shared.authStatus == .authorized else {
            availableReminderLists = []
            reminderLoadError = "Reminders permission is not granted."
            return
        }
        reminderLoadError = nil
        availableReminderLists = RemindersService.shared.reminderLists()
        if availableReminderLists.isEmpty {
            reminderLoadError = "No reminder lists found."
            return
        }

        let selectedId = settings.selectedReminderListId
        let isSelectedListValid = !selectedId.isEmpty && availableReminderLists.contains(where: { $0.id == selectedId })
        if !isSelectedListValid, let first = availableReminderLists.first {
            settings.selectedReminderListId = first.id
            save()
        }
    }

    @MainActor private func enableRemindersIntegration() async {
        guard !isEnablingReminders else { return }
        isEnablingReminders = true
        defer { isEnablingReminders = false }
        _ = await RemindersService.shared.requestAccess()
        if RemindersService.shared.authStatus == .authorized {
            settings.remindersIntegrationEnabled = true
            reminderAuthError = nil
            reminderLoadError = nil
            save()
            loadReminderLists()
        } else {
            reminderAuthError = "FocusFlow needs Reminders access."
            settings.remindersIntegrationEnabled = false
            availableReminderLists = []
            save()
        }
        refreshPermissionHealth()
        restoreSettingsWindow()
    }

    // MARK: Browser domains

    private var hasCapturedBrowserDomains: Bool {
        SettingsView.hasValidCapturedBrowserDomains(in: appUsageEntries)
    }

    private var domainTrackingRecoveryState: DomainTrackingRecoveryState? {
        SettingsView.domainTrackingRecoveryState(
            collectRawDomains: settings.coachCollectRawDomains,
            hasCapturedBrowserDomains: hasCapturedBrowserDomains,
            frontmostBundleIdentifier: AppUsageTracker.shared.currentFrontmostBundleId,
            screenRecordingAccess: CGPreflightScreenCaptureAccess(),
            automationStatusProvider: PermissionHealthService.automationStatus(for:)
        )
    }

    private var browserDomainsSection: some View {
        Section {
            Toggle("Collect website domains", isOn: bind(\.coachCollectRawDomains))

            if let state = domainTrackingRecoveryState, state != .disabled {
                domainTrackingRecoveryRow(for: state)
            }
        } header: {
            Text("Browser domains")
        } footer: {
            Text("When off, FocusFlow still tracks frontmost apps and categories. Existing saved domain history stays on this device, but FocusFlow stops collecting and using website domains for new labels and coaching.")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func domainTrackingRecoveryRow(for state: DomainTrackingRecoveryState) -> some View {
        LabeledContent {
            switch state {
            case .automationUnavailable:
                Button("Open Automation Settings") {
                    SystemSettingsLink.automation()
                }
                .accessibilityIdentifier("settings.domainTracking.openAutomationSettings")
                .accessibilityLabel("Open Automation privacy settings")
            case .screenRecordingUnavailable:
                Button("Open Screen Recording Settings") {
                    SystemSettingsLink.screenRecording()
                }
                .accessibilityIdentifier("settings.domainTracking.openScreenRecordingSettings")
                .accessibilityLabel("Open Screen Recording privacy settings")
            case .disabled, .awaitingFirstCapture:
                EmptyView()
            }
        } label: {
            Text(state.title)
            Text(state.message)
        }
    }

    private func save() {
        saveWithFeedback(modelContext, errorBinding: $saveError)
    }
}

// MARK: - Domain tracking recovery copy

enum DomainTrackingRecoveryState: Equatable {
    private static let supportedBrowserList = "Safari, Chrome, Arc, Edge, Brave, or Opera"

    case disabled
    case automationUnavailable
    case awaitingFirstCapture
    case screenRecordingUnavailable

    var title: String {
        switch self {
        case .disabled:
            return "Detailed domains are off"
        case .automationUnavailable:
            return "Browser access needs approval"
        case .awaitingFirstCapture:
            return "Waiting for the first browser domain"
        case .screenRecordingUnavailable:
            return "Browser titles are unavailable"
        }
    }

    var message: String {
        switch self {
        case .disabled:
            return "Turn this on only if you want website-level labels and coaching context for supported browsers. Until then, FocusFlow keeps app-level tracking only."
        case .automationUnavailable:
            return "FocusFlow reads supported browsers through macOS Automation first. If macOS has not asked yet, revisit the site and approve browser access. If you already denied it, open Automation Settings and re-enable FocusFlow for your browser."
        case .awaitingFirstCapture:
            return "FocusFlow hasn't captured a valid browser domain yet. Visit a site in \(Self.supportedBrowserList) and keep it frontmost for a moment. FocusFlow reads supported browsers through macOS Automation first. If a browser does not expose a tab URL, Screen Recording lets FocusFlow fall back to browser titles."
        case .screenRecordingUnavailable:
            return "Screen Recording is off, so FocusFlow can't recover domains from browser title fallback when a browser doesn't expose a tab URL. Enable it, then revisit the site."
        }
    }
}
