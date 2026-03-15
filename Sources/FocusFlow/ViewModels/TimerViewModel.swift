import Foundation
import SwiftData

enum TimerState: Equatable {
    case idle
    case focusing
    case paused
    case onBreak(SessionType)
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
        guard let settings else { return }
        let duration = settings.focusDuration
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
    }

    func resume() {
        guard state == .paused else { return }
        state = .focusing
        startTimer()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
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
        currentSession = nil

        if wasType == .focus {
            completedFocusSessions += 1
            loadTodayStats()
            NotificationService.shared.sendFocusComplete(sound: settings?.completionSound ?? "Glass")
            if settings?.autoStartBreak == true {
                startBreak()
            } else {
                state = .idle
            }
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
}
