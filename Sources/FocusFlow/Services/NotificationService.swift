import UserNotifications
import AppKit
import Combine

@MainActor
final class NotificationService: ObservableObject {
    enum AuthorizationState: Equatable {
        case notDetermined
        case denied
        case authorized
    }

    static let shared = NotificationService()
    private init() {}

    @Published private(set) var authorizationState: AuthorizationState = .notDetermined
    var isAuthorized: Bool { authorizationState == .authorized }

    private var canUseUserNotificationsAPI: Bool {
        if NSClassFromString("XCTestCase") != nil {
            return false
        }
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return false
        }
        if Bundle.main.bundleURL.path.contains("/Xcode.app/Contents/Developer/usr/bin") {
            return false
        }
        return Bundle.main.bundleIdentifier != nil
    }

    nonisolated static func authorizationState(for status: UNAuthorizationStatus) -> AuthorizationState {
        switch status {
        case .authorized, .provisional:
            return .authorized
        case .denied:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .denied
        }
    }

    @discardableResult
    func requestPermission() async -> AuthorizationState {
        guard canUseUserNotificationsAPI else {
            print("[NotificationService] No bundle identifier — notifications unavailable")
            authorizationState = .denied
            return .denied
        }
        if authorizationState == .denied {
            return .denied
        }

        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, error in
                if let error {
                    print("[NotificationService] Auth request failed: \(error.localizedDescription)")
                }
                continuation.resume()
            }
        }

        let state: AuthorizationState = await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                continuation.resume(returning: Self.authorizationState(for: settings.authorizationStatus))
            }
        }

        authorizationState = state
        return state
    }

    /// Refresh cached auth status — call from Settings on appear.
    func refreshAuthorizationStatus() {
        guard canUseUserNotificationsAPI else {
            authorizationState = .denied
            return
        }
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            let state = Self.authorizationState(for: settings.authorizationStatus)
            DispatchQueue.main.async {
                self?.authorizationState = state
            }
        }
    }

    func sendFocusComplete(sessionMinutes: Int = 0, sessionLabel: String = "", streak: Int = 0, dailyProgress: Int = 0, sound: String) {
        let title: String
        let body: String
        if streak >= 3 {
            title = "🔥 \(streak)-session streak!"
            body = sessionMinutes > 0 ? "Your \(streak)-day streak is running. \(sessionMinutes)m of \(sessionLabel.isEmpty ? "focus" : sessionLabel) banked." : "Your \(streak)-day streak is running. Ready to protect it?"
        } else if sessionMinutes >= 45 {
            title = "Deep work complete 💪"
            body = "\(sessionMinutes) minutes of \(sessionLabel.isEmpty ? "focused work" : sessionLabel) — that's serious output. Break time."
        } else if dailyProgress >= 80 {
            title = "Almost there!"
            body = "One block left to hit your goal for today."
        } else {
            title = "Focus session done"
            body = sessionMinutes > 0 ? "\(sessionMinutes)m of \(sessionLabel.isEmpty ? "focus" : sessionLabel) logged. Break time." : "Break time. Session saved."
        }
        send(title: title, body: body, sound: sound)
    }

    func sendBreakComplete(sessionCount: Int = 0, dailyGoalMinutes: Int = 120, completedMinutes: Int = 0, sound: String) {
        let remaining = max(0, dailyGoalMinutes - completedMinutes)
        let title: String
        let body: String
        if remaining <= 0 {
            title = "Daily goal hit! 🎯"
            body = "You've completed your \(dailyGoalMinutes)m focus goal for today. Nice work."
        } else if sessionCount >= 3 {
            title = "Session \(sessionCount + 1) loading…"
            body = "You've protected \(sessionCount) blocks today. \(remaining)m left — start another?"
        } else {
            title = "Break's over — \(remaining)m to go"
            body = "You've done \(completedMinutes)m of your \(dailyGoalMinutes)m goal. Ready for the next block?"
        }
        send(title: title, body: body, sound: sound)
    }

    func sendSessionCompletePrompt(duration: TimeInterval, label: String, sound: String) {
        NSSound(named: NSSound.Name(sound))?.play()
        guard canUseUserNotificationsAPI, authorizationState == .authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = "Focus Session Complete!"
        content.body = "\(Int(duration / 60)) min of \(label) — tap the timer to review and log."
        content.sound = .default
        let request = UNNotificationRequest(identifier: "session-complete", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("[NotificationService] Failed to deliver notification: \(error.localizedDescription)")
            }
        }
    }

    func sendPauseWarning(minutes: Int) {
        NSSound(named: NSSound.Name("Bottle"))?.play()
        guard canUseUserNotificationsAPI, authorizationState == .authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = "Pause getting long"
        content.body = "You've been paused for \(minutes) minutes. Ready to get back to it?"
        content.sound = .default
        let request = UNNotificationRequest(identifier: "pause-warning", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("[NotificationService] Failed to deliver notification: \(error.localizedDescription)")
            }
        }
    }

    func sendPauseCritical(minutes: Int) {
        NSSound(named: NSSound.Name("Sosumi"))?.play()
        guard canUseUserNotificationsAPI, authorizationState == .authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = "Long pause!"
        content.body = "You've been paused for \(minutes) minutes. Consider resuming or ending the session."
        content.sound = UNNotificationSound.defaultCritical
        let request = UNNotificationRequest(identifier: "pause-critical", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("[NotificationService] Failed to deliver notification: \(error.localizedDescription)")
            }
        }
    }

    func sendBreakWarning(minutes: Int) {
        NSSound(named: NSSound.Name("Bottle"))?.play()
        guard canUseUserNotificationsAPI, authorizationState == .authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = "Break getting long"
        content.body = "You've been on break for \(minutes) minutes. Ready to get back to focusing?"
        content.sound = .default
        let request = UNNotificationRequest(identifier: "break-warning", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("[NotificationService] Failed to deliver notification: \(error.localizedDescription)")
            }
        }
    }

    func sendBreakCritical(minutes: Int) {
        NSSound(named: NSSound.Name("Sosumi"))?.play()
        guard canUseUserNotificationsAPI, authorizationState == .authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = "Break hit \(minutes) minutes"
        content.body = "Your \(minutes)-minute break is well past planned. Jump back in?"
        content.sound = UNNotificationSound.defaultCritical
        let request = UNNotificationRequest(identifier: "break-critical", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("[NotificationService] Failed to deliver notification: \(error.localizedDescription)")
            }
        }
    }

    private func send(title: String, body: String, sound: String) {
        NSSound(named: NSSound.Name(sound))?.play()
        guard canUseUserNotificationsAPI else { return }
        guard authorizationState == .authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("[NotificationService] Failed to deliver notification: \(error.localizedDescription)")
            }
        }
    }

    func sendGenericNotification(title: String, body: String, sound: String) {
        send(title: title, body: body, sound: sound)
    }

    // MARK: - Actionable coach check-in (B4)

    /// Called on the main actor when the user acts on a coach notification. Wired by TimerViewModel.
    var onCoachNotificationResponse: ((CoachNotificationResponse) -> Void)?

    /// Installs the notification delegate and the coach category with Start / Snooze actions.
    /// Safe to call more than once.
    func registerCoachNotificationHandling() {
        guard canUseUserNotificationsAPI else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = CoachNotificationDelegate.shared
        center.setNotificationCategories([Self.coachCheckInCategory])
    }

    nonisolated static var coachCheckInCategory: UNNotificationCategory {
        let start = UNNotificationAction(
            identifier: CoachNotificationResponse.startActionIdentifier,
            title: "Start focus",
            options: []
        )
        let snooze = UNNotificationAction(
            identifier: CoachNotificationResponse.snoozeActionIdentifier,
            title: "Snooze",
            options: []
        )
        return UNNotificationCategory(
            identifier: CoachNotificationResponse.categoryIdentifier,
            actions: [start, snooze],
            intentIdentifiers: [],
            options: []
        )
    }

    /// Sends the idle-starter check-in with actionable Start / Snooze buttons.
    func sendCoachCheckIn(title: String, body: String, sound: String) {
        NSSound(named: NSSound.Name(sound))?.play()
        guard canUseUserNotificationsAPI, authorizationState == .authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = CoachNotificationResponse.categoryIdentifier
        let request = UNNotificationRequest(identifier: "focus-coach-checkin", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("[NotificationService] Failed to deliver notification: \(error.localizedDescription)")
            }
        }
    }

    func handleCoachNotificationResponse(_ response: CoachNotificationResponse) {
        onCoachNotificationResponse?(response)
    }
}

/// What the user did with a coach check-in notification.
enum CoachNotificationResponse: Equatable, Sendable {
    case startFocus
    case snooze
    /// Default tap on the notification body.
    case open

    static let categoryIdentifier = "FOCUS_COACH_CHECKIN"
    static let startActionIdentifier = "FOCUS_COACH_START"
    static let snoozeActionIdentifier = "FOCUS_COACH_SNOOZE"

    /// Maps a delivered response to a coach response. Returns nil for other notifications and
    /// for the system dismiss action.
    init?(categoryIdentifier: String, actionIdentifier: String) {
        guard categoryIdentifier == Self.categoryIdentifier else { return nil }
        switch actionIdentifier {
        case Self.startActionIdentifier:
            self = .startFocus
        case Self.snoozeActionIdentifier:
            self = .snooze
        case UNNotificationDefaultActionIdentifier:
            self = .open
        default:
            return nil
        }
    }
}

/// Routes notification responses to `NotificationService` and shows banners while the app is
/// frontmost. Without a delegate macOS drops action taps (bug B4).
final class CoachNotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = CoachNotificationDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let mapped = CoachNotificationResponse(
            categoryIdentifier: response.notification.request.content.categoryIdentifier,
            actionIdentifier: response.actionIdentifier
        ) else { return }
        await MainActor.run {
            NotificationService.shared.handleCoachNotificationResponse(mapped)
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
