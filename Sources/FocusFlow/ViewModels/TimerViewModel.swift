import Foundation
import SwiftUI
import SwiftData

enum TimerState: Equatable {
    case idle
    case focusing
    case paused
    case onBreak(SessionType)
}

enum PostCompletionAction {
    case continueFocusing
    case takeBreak
    case endSession
}

@MainActor
@Observable
final class TimerViewModel {
    // MARK: - State
    var state: TimerState = .idle
    var remainingSeconds: TimeInterval = 0
    var totalSeconds: TimeInterval = 0
    var completedFocusSessions: Int = 0
    var selectedProject: Project?
    var customLabel: String = ""

    // MARK: - Custom Duration
    var selectedMinutes: Int = 25

    var focusDuration: TimeInterval {
        TimeInterval(max(5, selectedMinutes) * 60)
    }

    // MARK: - Pause Tracking
    var pauseStartTime: Date? = nil
    var pauseElapsed: TimeInterval = 0
    private var pauseTimer: Timer? = nil

    var pauseTimeString: String {
        let mins = Int(pauseElapsed) / 60
        let secs = Int(pauseElapsed) % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    enum PauseWarningLevel {
        case normal      // < 2 min
        case warning     // 2-5 min
        case critical    // > 5 min

        var color: Color {
            switch self {
            case .normal: return .secondary
            case .warning: return .orange
            case .critical: return .red
            }
        }
    }

    var pauseWarningLevel: PauseWarningLevel {
        if pauseElapsed > 300 { return .critical }
        if pauseElapsed > 120 { return .warning }
        return .normal
    }

    var pauseWarningMessage: String {
        switch pauseWarningLevel {
        case .normal:   return "Deep work momentum is fading..."
        case .warning:  return "2 min paused — focus is slipping away"
        case .critical: return "5+ min paused — consider restarting"
        }
    }

    // MARK: - Start Error Feedback
    var startError: String? = nil

    // MARK: - Save Error Feedback
    var saveError: String? = nil

    // MARK: - Session Completion
    var showSessionComplete: Bool = false
    /// True when user manually stopped mid-session (vs natural timer completion).
    var isManualStop: Bool = false
    var hasStaleBlocking: Bool = false
    var lastCompletedDuration: TimeInterval? = nil
    var lastCompletedLabel: String? = nil
    private(set) var lastCompletedSession: FocusSession? = nil

    // MARK: - Overtime
    var isOvertime: Bool = false
    var overtimeSeconds: Int = 0

    /// True when the completed session was a focus session (not a break).
    var isFocusOvertime: Bool { isOvertime && lastCompletedSession?.type == .focus }
    /// True when the completed session was a break (break ran past its duration).
    var isBreakOvertime: Bool { isOvertime && lastCompletedSession?.type != .focus }

    // MARK: - Today Stats
    var todayFocusTime: TimeInterval = 0
    var todaySessionCount: Int = 0

    // MARK: - Day Boundary
    private var currentDay: Date = Calendar.current.startOfDay(for: Date())
    private var midnightTimer: Timer?

    // MARK: - Window Callback
    /// Set by FocusFlowApp to open the session-complete window from any context
    var openCompletionWindow: (() -> Void)?

    // MARK: - Private
    private var timer: Timer?
    private var modelContext: ModelContext?
    private var currentSession: FocusSession?
    private(set) var settings: AppSettings?

    // MARK: - Computed
    var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        if isOvertime {
            // During overtime, progress exceeds 1.0 — used by TimerRingView for overtime ring fill
            return 1.0 + (Double(overtimeSeconds) / totalSeconds)
        }
        return 1 - (remainingSeconds / totalSeconds)
    }

    var timeString: String {
        let minutes = Int(remainingSeconds) / 60
        let seconds = Int(remainingSeconds) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var overtimeTimeString: String {
        let mins = overtimeSeconds / 60
        let secs = overtimeSeconds % 60
        return String(format: "+%02d:%02d", mins, secs)
    }

    var isRunning: Bool {
        switch state {
        case .focusing, .onBreak: return true
        default: return false
        }
    }

    var isBlockingActive: Bool { BlockingService.shared.isActive }

    var sessionLabel: String {
        selectedProject?.name ?? (customLabel.isEmpty ? "Focus" : customLabel)
    }

    var sessionsBeforeLongBreak: Int {
        settings?.sessionsBeforeLongBreak ?? 4
    }

    // MARK: - Setup
    private var isConfigured = false

    func configure(modelContext: ModelContext) {
        guard !isConfigured else { return }
        isConfigured = true
        self.modelContext = modelContext
        log("configure() called")
        loadSettings()
        log("settings loaded: \(settings != nil)")
        seedDefaultProfiles()
        loadTodayStats()
        cleanupOrphanedSessions()
        // Don't call BlockingService.cleanupIfNeeded() here — it prompts for
        // admin password if stale /etc/hosts entries exist, which is jarring on
        // app launch. Instead, cleanup happens in deactivateBlocking().
        // Refresh notification authorization on the main actor so the Settings
        // banner accurately reflects whether notifications are enabled.
        Task { @MainActor in
            NotificationService.shared.refreshAuthorizationStatus()
        }
        if BlockingHelper.isBlockingActive() {
            hasStaleBlocking = true
            log("WARNING: Stale website blocking detected from previous crash")
        }
        scheduleMidnightRefresh()
        // Refresh today-total whenever a session is manually logged from the Companion window.
        NotificationCenter.default.addObserver(forName: .focusSessionLoggedManually, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.loadTodayStats()
            }
        }
        // Start app usage tracking and nudge timer at launch (not deferred to popover open)
        AppUsageTracker.shared.start(timerVM: self, modelContext: modelContext)
        log("configure() complete")
    }

    func ensureConfigured(modelContext: ModelContext) {
        if !isConfigured {
            configure(modelContext: modelContext)
        }
    }

    /// Schedules a timer to fire at midnight to refresh today's stats
    private func scheduleMidnightRefresh() {
        midnightTimer?.invalidate()
        let calendar = Calendar.current
        guard let nextMidnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date())) else { return }
        let interval = nextMidnight.timeIntervalSinceNow + 1 // 1 sec after midnight

        let t = Timer(fire: Date().addingTimeInterval(interval), interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.handleDayChange()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        midnightTimer = t
    }

    @MainActor
    private func handleDayChange() {
        currentDay = Calendar.current.startOfDay(for: Date())
        completedFocusSessions = 0
        loadTodayStats()
        // Schedule next midnight refresh
        scheduleMidnightRefresh()
    }

    private func cleanupOrphanedSessions() {
        let predicate = #Predicate<FocusSession> { $0.endedAt == nil }
        let descriptor = FetchDescriptor<FocusSession>(predicate: predicate)
        guard let orphans = try? modelContext?.fetch(descriptor) else { return }
        for session in orphans {
            let elapsed = Date().timeIntervalSince(session.startedAt)
            if elapsed < 60 {
                // Delete sessions with less than 1 minute — not worth keeping
                modelContext?.delete(session)
            } else {
                // Cap the duration at what was planned
                session.endedAt = session.startedAt.addingTimeInterval(min(elapsed, session.duration))
                session.completed = false
            }
        }
        saveContext()
    }

    private func loadSettings() {
        let descriptor = FetchDescriptor<AppSettings>()
        settings = try? modelContext?.fetch(descriptor).first
        if settings == nil {
            let newSettings = AppSettings()
            modelContext?.insert(newSettings)
            saveContext()
            settings = newSettings
        }
        if let settings {
            selectedMinutes = Int(settings.focusDuration / 60)
            if selectedProject == nil,
               let lastId = settings.lastUsedProjectId,
               let uuid = UUID(uuidString: lastId) {
                let descriptor = FetchDescriptor<Project>(predicate: #Predicate { $0.id == uuid && !$0.archived })
                selectedProject = try? modelContext?.fetch(descriptor).first
            }
        }
    }

    func loadTodayStats() {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        // Fetch sessions that overlap with today (handles cross-midnight)
        let descriptor = FetchDescriptor<FocusSession>()
        guard let allSessions = try? modelContext?.fetch(descriptor) else { return }
        let focusSessions = allSessions.filter { session in
            guard session.type == .focus else { return false }
            let sessionEnd = session.endedAt ?? session.startedAt.addingTimeInterval(session.actualDuration)
            return sessionEnd > startOfDay && session.startedAt < tomorrow
        }
        todaySessionCount = focusSessions.filter(\.completed).count
        // Attribute only today's portion of each session
        todayFocusTime = focusSessions.reduce(0) { sum, session in
            let sessionEnd = session.endedAt ?? session.startedAt.addingTimeInterval(session.actualDuration)
            let overlapStart = max(session.startedAt, startOfDay)
            let overlapEnd = min(sessionEnd, tomorrow)
            return sum + max(0, overlapEnd.timeIntervalSince(overlapStart))
        }
        completedFocusSessions = todaySessionCount
    }

    // MARK: - Actions
    func startFocus() {
        startError = nil
        guard settings != nil, !isOvertime else {
            log("startFocus: settings nil or overtime, aborting")
            startError = settings == nil ? "Settings not loaded. Please restart the app." : "Complete the current session first."
            return
        }
        guard state == .idle else {
            log("startFocus: not idle (state=\(state)), aborting")
            startError = "A session is already in progress."
            return
        }
        let duration = focusDuration
        guard duration >= 300 else {
            log("startFocus: duration \(duration) < 300, aborting")
            startError = "Minimum session duration is 5 minutes."
            return
        }
        log("startFocus: duration=\(duration), project=\(selectedProject?.name ?? "none")")
        totalSeconds = duration
        remainingSeconds = duration
        state = .focusing

        let session = FocusSession(
            type: .focus,
            duration: duration,
            project: selectedProject,
            customLabel: customLabel.isEmpty ? nil : customLabel
        )
        modelContext?.insert(session)
        currentSession = session
        if let project = selectedProject {
            settings?.lastUsedProjectId = project.id.uuidString
        }
        startTimer()
        // Project-based blocking only: activate if selected project has a profile.
        activateBlocking()
    }

    private func log(_ msg: String) {
        let path = "/tmp/focusflow_debug.log"
        let entry = "[\(Date())] \(msg)\n"
        if FileManager.default.fileExists(atPath: path) {
            if let handle = FileHandle(forWritingAtPath: path) {
                handle.seekToEndOfFile()
                handle.write(entry.data(using: .utf8)!)
                handle.closeFile()
            }
        } else {
            try? entry.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    /// Saves the model context, logging errors. Non-critical saves (cleanup, stats refresh)
    /// use this to avoid disrupting the user.
    private func saveContext(caller: String = #function) {
        do {
            try modelContext?.save()
        } catch {
            log("Save failed in \(caller): \(error.localizedDescription)")
            saveError = error.localizedDescription
            // Auto-clear after 5 seconds
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(5))
                if self?.saveError == error.localizedDescription {
                    self?.saveError = nil
                }
            }
        }
    }

    func startBreak() {
        guard let settings, !isOvertime else { return }
        // Guard against zero/negative sessionsBeforeLongBreak to prevent division-by-zero
        let sessionsPerCycle = max(1, settings.sessionsBeforeLongBreak)
        let isLongBreak = completedFocusSessions > 0
            && (completedFocusSessions % sessionsPerCycle) == 0
        let type: SessionType = isLongBreak ? .longBreak : .shortBreak
        let duration = isLongBreak ? settings.longBreakDuration : settings.shortBreakDuration

        totalSeconds = duration
        remainingSeconds = duration
        state = .onBreak(type)

        let session = FocusSession(type: type, duration: duration)
        modelContext?.insert(session)
        currentSession = session
        startTimer()
    }

    func pause() {
        guard state == .focusing, !isOvertime else { return }
        timer?.invalidate()
        timer = nil
        state = .paused
        pauseStartTime = Date()
        pauseElapsed = 0
        startPauseTimer()
    }

    /// Maximum single session duration: 4 hours (prevents runaway extension)
    private static let maxSessionSeconds: TimeInterval = 4 * 60 * 60

    func extendTimer(by seconds: TimeInterval = 300) {
        guard state == .focusing, !isOvertime else { return }
        // Don't allow reducing below 60 seconds remaining
        if seconds < 0 && remainingSeconds + seconds < 60 { return }
        // Don't allow extending beyond 4-hour ceiling
        if seconds > 0 && totalSeconds + seconds > Self.maxSessionSeconds { return }
        remainingSeconds += seconds
        totalSeconds += seconds
        currentSession?.duration += seconds
    }

    /// True when -5min button can act (more than 5m + 60s buffer remaining)
    var canReduceTime: Bool {
        state == .focusing && !isOvertime && remainingSeconds > 360
    }

    /// True when +5min button can act (not at the 4-hour ceiling)
    var canExtendTime: Bool {
        state == .focusing && !isOvertime && totalSeconds + 300 <= Self.maxSessionSeconds
    }

    func resume() {
        guard state == .paused else { return }
        pauseTimer?.invalidate()
        pauseTimer = nil
        pauseStartTime = nil
        pauseElapsed = 0
        state = .focusing
        startTimer()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        pauseTimer?.invalidate()
        pauseTimer = nil
        pauseStartTime = nil
        pauseElapsed = 0
        isOvertime = false
        overtimeSeconds = 0
        isManualStop = false
        showSessionComplete = false
        if let session = currentSession {
            session.endedAt = Date()
            session.completed = false
            // Delete sessions with less than 1 minute of actual focus
            if session.actualDuration < 60 {
                modelContext?.delete(session)
            }
            saveContext()
        }
        loadTodayStats()
        deactivateBlocking()
        currentSession = nil
        state = .idle
        remainingSeconds = 0
        totalSeconds = 0
    }

    /// Routes a mid-session stop through SessionCompleteWindow so the user
    /// can record mood, achievement, and splits before the session is finalised.
    /// Only used when the session is long enough to be worth reflecting on (≥60s).
    func stopForReflection() {
        log("stopForReflection called, currentSession=\(currentSession != nil)")
        guard let session = currentSession else {
            stop()   // nothing to save
            return
        }
        // Too short to be worth a reflection window — just discard
        let elapsed = Date().timeIntervalSince(session.startedAt)
        log("stopForReflection: elapsed=\(elapsed)s, openCompletionWindow set=\(openCompletionWindow != nil)")
        if elapsed < 60 {
            abandonSession()
            return
        }
        timer?.invalidate()
        timer = nil
        pauseTimer?.invalidate()
        pauseTimer = nil
        pauseStartTime = nil
        pauseElapsed = 0

        session.endedAt = Date()
        session.completed = false
        saveContext()

        lastCompletedDuration = session.duration
        lastCompletedLabel = session.label
        lastCompletedSession = session
        currentSession = nil

        isManualStop = true
        isOvertime = false
        overtimeSeconds = 0
        state = .idle
        remainingSeconds = 0
        totalSeconds = 0

        showSessionComplete = true
        openCompletionWindow?()
        log("stopForReflection: showSessionComplete=\(showSessionComplete), openCompletionWindow called")
    }

    /// Called from SessionCompleteWindow "Discard" button after a manual stop.
    /// Deletes the session that was provisionally saved by stopForReflection().
    func discardManualStop() {
        if let session = lastCompletedSession {
            modelContext?.delete(session)
            saveContext()
        }
        isManualStop = false
        showSessionComplete = false
        lastCompletedSession = nil
        lastCompletedDuration = nil
        lastCompletedLabel = nil
        loadTodayStats()
    }

    /// Called when SessionComplete window is closed without explicit action.
    /// Preserves the session (doesn't delete it) and resets UI state.
    func preserveManualStop() {
        isManualStop = false
        showSessionComplete = false
        lastCompletedSession = nil
        lastCompletedDuration = nil
        lastCompletedLabel = nil
        loadTodayStats()
    }

    func abandonSession() {
        timer?.invalidate()
        timer = nil
        pauseTimer?.invalidate()
        pauseTimer = nil
        pauseStartTime = nil
        pauseElapsed = 0

        isOvertime = false
        overtimeSeconds = 0
        isManualStop = false
        showSessionComplete = false
        if let session = currentSession {
            modelContext?.delete(session)
            saveContext()
        }
        loadTodayStats()
        deactivateBlocking()
        currentSession = nil
        state = .idle
        remainingSeconds = 0
        totalSeconds = 0
    }

    func skipBreak() {
        timer?.invalidate()
        timer = nil
        isOvertime = false
        overtimeSeconds = 0
        showSessionComplete = false
        currentSession?.endedAt = Date()
        currentSession?.completed = false
        saveContext()
        currentSession = nil
        state = .idle
        remainingSeconds = 0
        totalSeconds = 0
        loadTodayStats()
    }

    // MARK: - Blocking
    var blockUntilGoalMet: Bool = false

    private func activateBlocking() {
        log("activateBlocking called")
        if let profile = selectedProject?.blockProfile {
            log("Using project-specific profile: \(profile.name)")
            BlockingService.shared.activate(profile: profile)
            return
        }
        log("No blocking profile assigned to selected project; skipping blocking.")
    }

    private func deactivateBlocking() {
        guard BlockingService.shared.isActive else { return }
        // If block-until-goal is enabled, keep blocking until daily goal is met
        if blockUntilGoalMet {
            let goal = settings?.dailyFocusGoal ?? 7200
            if todayFocusTime < goal {
                log("Block-until-goal: \(Int(todayFocusTime))s < \(Int(goal))s goal — keeping blocks active")
                return
            }
        }
        BlockingService.shared.deactivate()
        hasStaleBlocking = false
    }

    // MARK: - Timer
    private func startTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func startPauseTimer() {
        pauseTimer?.invalidate()
        pauseTimer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tickPause()
            }
        }
        RunLoop.main.add(pauseTimer!, forMode: .common)
    }

    @MainActor
    private func tickPause() {
        guard let pauseStartTime else { return }
        pauseElapsed = Date().timeIntervalSince(pauseStartTime)

        // Send notifications at thresholds
        if Int(pauseElapsed) == 120 { // 2 min
            NotificationService.shared.sendPauseWarning(minutes: 2)
        } else if Int(pauseElapsed) == 300 { // 5 min
            NotificationService.shared.sendPauseCritical(minutes: 5)
        }
    }

    @MainActor
    private func tick() {
        if isOvertime {
            overtimeSeconds += 1
            currentSession?.endedAt = Date()
            if overtimeSeconds % 30 == 0 {
                saveContext()
            }
            loadTodayStats()
            return
        }
        guard remainingSeconds > 0 else { return }
        remainingSeconds -= 1

        // Break duration monitoring — send warnings for long breaks
        if case .onBreak = state, let session = currentSession {
            let breakElapsed = Date().timeIntervalSince(session.startedAt)
            let breakElapsedInt = Int(breakElapsed)
            if breakElapsedInt == 120 {
                NotificationService.shared.sendBreakWarning(minutes: 2)
            } else if breakElapsedInt == 300 {
                NotificationService.shared.sendBreakCritical(minutes: 5)
            }
        }

        if remainingSeconds <= 0 {
            Task { @MainActor in
                await timerCompleted()
            }
        }
    }

    @MainActor
    private func timerCompleted() async {
        // Don't invalidate timer — continues for overtime
        currentSession?.endedAt = Date()
        currentSession?.completed = true
        saveContext()

        let wasType = currentSession?.type

        // Capture completion info
        lastCompletedDuration = currentSession?.duration
        lastCompletedLabel = currentSession?.label
        lastCompletedSession = currentSession

        if wasType == .focus {
            completedFocusSessions += 1
            let sound = settings?.completionSound ?? "Glass"
            let label = currentSession?.label ?? "Focus"
            let duration = currentSession?.duration ?? 0
            NotificationService.shared.sendSessionCompletePrompt(duration: duration, label: label, sound: sound)

            // Calendar integration
            if settings?.calendarIntegrationEnabled == true, let session = currentSession {
                let calName = settings?.calendarName ?? "FocusFlow"
                let calId = settings?.selectedCalendarId
                let eventId = CalendarService.shared.createEvent(
                    title: session.label,
                    startDate: session.startedAt,
                    endDate: session.endedAt ?? Date(),
                    notes: session.achievement,
                    calendarName: calName,
                    calendarId: (calId?.isEmpty ?? true) ? nil : calId
                )
                session.calendarEventId = eventId
                saveContext()
            }
        } else {
            NotificationService.shared.sendBreakComplete(sound: settings?.completionSound ?? "Glass")
        }

        // Enter overtime — timer keeps running, counting up
        // State goes idle so popover doesn't show pause/stop
        loadTodayStats()
        isOvertime = true
        overtimeSeconds = 0
        remainingSeconds = 0
        state = .idle
        showSessionComplete = true
        openCompletionWindow?()
    }

    // MARK: - Reflection

    @MainActor
    func saveReflection(
        mood: FocusMood?,
        achievement: String?,
        reminderIdsToComplete: [String] = [],
        splits: [TimeSplitView.SplitEntry]? = nil
    ) async {
        guard let session = lastCompletedSession else { return }
        session.mood = mood
        session.achievement = achievement

        // Save splits if provided — skip zero/negative durations to prevent stat corruption
        if let splits, !splits.isEmpty, splits.count > 1 {
            for split in splits {
                let splitSeconds = TimeInterval(split.minutes * 60)
                guard splitSeconds > 0 else { continue }
                let timeSplit = TimeSplit(
                    project: split.project,
                    customLabel: split.customLabel.isEmpty ? nil : split.customLabel,
                    duration: splitSeconds
                )
                timeSplit.session = session
                modelContext?.insert(timeSplit)
            }
        }

        if !reminderIdsToComplete.isEmpty {
            for reminderId in reminderIdsToComplete {
                let ok = RemindersService.shared.completeReminder(identifier: reminderId)
                if !ok {
                    print("[TimerViewModel] Failed to complete reminder: \(reminderId)")
                }
            }
        }

        if let eventId = session.calendarEventId, !eventId.isEmpty {
            var noteLines: [String] = []
            if let achievement, !achievement.isEmpty {
                noteLines.append("Achievements:")
                for line in achievement
                    .components(separatedBy: .newlines)
                    .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
                    .filter({ !$0.isEmpty }) {
                    noteLines.append("• \(line)")
                }
            }
            if !reminderIdsToComplete.isEmpty {
                noteLines.append("")
                noteLines.append("Completed reminders: \(reminderIdsToComplete.count)")
            }
            let duration = Int(session.actualDuration / 60)
            noteLines.append("")
            noteLines.append("Duration: \(duration) minutes")
            noteLines.append("Recorded by FocusFlow")
            _ = CalendarService.shared.updateEvent(
                eventId: eventId,
                title: session.label,
                notes: noteLines.joined(separator: "\n"),
                startDate: session.startedAt,
                endDate: session.endedAt ?? Date()
            )
        }

        saveContext()
    }

    private func seedDefaultProfiles() {
        let descriptor = FetchDescriptor<BlockProfile>()
        let existing = (try? modelContext?.fetch(descriptor)) ?? []
        guard existing.isEmpty else { return }
        let social = BlockProfile(
            name: "Social Media",
            websites: ["youtube.com", "x.com", "twitter.com", "reddit.com", "instagram.com", "facebook.com", "tiktok.com"]
        )
        let fullFocus = BlockProfile(
            name: "Full Focus",
            websites: ["youtube.com", "x.com", "twitter.com", "reddit.com", "instagram.com", "facebook.com", "tiktok.com", "news.ycombinator.com", "netflix.com", "twitch.tv"],
            apps: ["com.tinyspeck.slackmacgap", "com.hnc.Discord", "ph.telegra.Telegraph", "net.whatsapp.WhatsApp"],
            mutedApps: ["com.tinyspeck.slackmacgap", "com.hnc.Discord"]
        )
        modelContext?.insert(social)
        modelContext?.insert(fullFocus)
        saveContext()
    }

    func continueAfterCompletion(action: PostCompletionAction) {
        // Stop overtime timer
        timer?.invalidate()
        timer = nil
        isOvertime = false
        overtimeSeconds = 0

        // Final save of session endedAt (includes overtime)
        if let session = currentSession ?? lastCompletedSession {
            session.endedAt = Date()
            saveContext()
        }
        loadTodayStats()

        showSessionComplete = false
        isManualStop = false

        switch action {
        case .continueFocusing:
            startFocus()
        case .takeBreak:
            startBreak()
        case .endSession:
            deactivateBlocking()
            state = .idle
            loadTodayStats()
        }

        currentSession = nil
        lastCompletedSession = nil
    }
}
