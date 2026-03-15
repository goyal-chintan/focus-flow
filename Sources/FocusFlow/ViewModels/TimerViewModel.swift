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
        return String(format: "%d:%02d", mins, secs)
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

    // MARK: - Session Completion
    var showSessionComplete: Bool = false
    var lastCompletedDuration: TimeInterval? = nil
    var lastCompletedLabel: String? = nil
    private var lastCompletedSession: FocusSession? = nil

    // MARK: - Today Stats
    var todayFocusTime: TimeInterval = 0
    var todaySessionCount: Int = 0

    // MARK: - Private
    private var timer: Timer?
    private var modelContext: ModelContext?
    private var currentSession: FocusSession?
    private(set) var settings: AppSettings?

    // MARK: - Computed
    var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        return 1 - (remainingSeconds / totalSeconds)
    }

    var timeString: String {
        let minutes = Int(remainingSeconds) / 60
        let seconds = Int(remainingSeconds) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var isRunning: Bool {
        switch state {
        case .focusing, .onBreak: return true
        default: return false
        }
    }

    var sessionLabel: String {
        selectedProject?.name ?? (customLabel.isEmpty ? "Focus" : customLabel)
    }

    var sessionsBeforeLongBreak: Int {
        settings?.sessionsBeforeLongBreak ?? 4
    }

    // MARK: - Setup
    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
        loadSettings()
        loadTodayStats()
    }

    private func loadSettings() {
        let descriptor = FetchDescriptor<AppSettings>()
        settings = try? modelContext?.fetch(descriptor).first
        if settings == nil {
            let newSettings = AppSettings()
            modelContext?.insert(newSettings)
            try? modelContext?.save()
            settings = newSettings
        }
        if let settings {
            selectedMinutes = Int(settings.focusDuration / 60)
        }
    }

    func loadTodayStats() {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let predicate = #Predicate<FocusSession> {
            $0.startedAt >= startOfDay
        }
        let descriptor = FetchDescriptor<FocusSession>(predicate: predicate)
        guard let sessions = try? modelContext?.fetch(descriptor) else { return }
        let focusSessions = sessions.filter { $0.type == .focus }
        todaySessionCount = focusSessions.filter { $0.completed }.count
        todayFocusTime = focusSessions.reduce(0) { $0 + $1.actualDuration }
        // Keep in-memory count in sync with persisted completed sessions
        completedFocusSessions = todaySessionCount
    }

    // MARK: - Actions
    func startFocus() {
        guard settings != nil else { return }
        let duration = focusDuration
        guard duration >= 300 else { return } // Min 5 minutes
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
        startTimer()
    }

    func startBreak() {
        guard let settings else { return }
        let isLongBreak = completedFocusSessions > 0
            && (completedFocusSessions % settings.sessionsBeforeLongBreak) == 0
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
        guard state == .focusing else { return }
        timer?.invalidate()
        timer = nil
        state = .paused
        pauseStartTime = Date()
        pauseElapsed = 0
        startPauseTimer()
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
        currentSession?.endedAt = Date()
        currentSession?.completed = false
        try? modelContext?.save()
        currentSession = nil
        state = .idle
        remainingSeconds = 0
        totalSeconds = 0
        loadTodayStats()
    }

    func skipBreak() {
        timer?.invalidate()
        timer = nil
        currentSession?.endedAt = Date()
        currentSession?.completed = false
        try? modelContext?.save()
        currentSession = nil
        state = .idle
        remainingSeconds = 0
        totalSeconds = 0
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
        guard remainingSeconds > 0 else { return }
        remainingSeconds -= 1
        if remainingSeconds <= 0 {
            timerCompleted()
        }
    }

    @MainActor
    private func timerCompleted() {
        timer?.invalidate()
        timer = nil

        currentSession?.endedAt = Date()
        currentSession?.completed = true
        try? modelContext?.save()

        let wasType = currentSession?.type
        let lastSession = currentSession
        currentSession = nil

        if wasType == .focus {
            completedFocusSessions += 1
            loadTodayStats()
            NotificationService.shared.sendFocusComplete(sound: settings?.completionSound ?? "Glass")
            // Don't auto-start break — show completion view instead
            lastCompletedDuration = lastSession?.duration
            lastCompletedLabel = lastSession?.label
            lastCompletedSession = lastSession
            showSessionComplete = true
            state = .idle
        } else {
            loadTodayStats()
            NotificationService.shared.sendBreakComplete(sound: settings?.completionSound ?? "Glass")
            if settings?.autoStartNextSession == true {
                startFocus()
            } else {
                state = .idle
            }
        }
    }

    // MARK: - Reflection

    func saveReflection(mood: FocusMood?, achievement: String?, splits: [TimeSplitView.SplitEntry]? = nil) {
        guard let session = lastCompletedSession else { return }
        session.mood = mood
        session.achievement = achievement

        // Save splits if provided
        if let splits, !splits.isEmpty, splits.count > 1 {
            for split in splits {
                let timeSplit = TimeSplit(
                    project: split.project,
                    customLabel: split.customLabel.isEmpty ? nil : split.customLabel,
                    duration: TimeInterval(split.minutes * 60)
                )
                timeSplit.session = session
                modelContext?.insert(timeSplit)
            }
        }

        try? modelContext?.save()
    }

    func continueAfterCompletion(action: PostCompletionAction) {
        showSessionComplete = false
        lastCompletedSession = nil

        switch action {
        case .continueFocusing:
            startFocus()
        case .takeBreak:
            startBreak()
        case .endSession:
            state = .idle
            loadTodayStats()
        }
    }
}
