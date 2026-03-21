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

    func requestPermission() {
        guard Bundle.main.bundleIdentifier != nil else {
            print("[NotificationService] No bundle identifier — notifications unavailable")
            authorizationState = .denied
            return
        }
        if authorizationState == .denied {
            refreshAuthorizationStatus()
            return
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] _, error in
            if let error {
                print("[NotificationService] Auth request failed: \(error.localizedDescription)")
            }
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                let state = Self.authorizationState(for: settings.authorizationStatus)
                DispatchQueue.main.async {
                    self?.authorizationState = state
                }
            }
        }
    }

    /// Refresh cached auth status — call from Settings on appear.
    func refreshAuthorizationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            let state = Self.authorizationState(for: settings.authorizationStatus)
            DispatchQueue.main.async {
                self?.authorizationState = state
            }
        }
    }

    func sendFocusComplete(sound: String) {
        send(title: "Focus session complete!", body: "Great work! Time for a break.", sound: sound)
    }

    func sendBreakComplete(sound: String) {
        send(title: "Break's over!", body: "Ready to focus again?", sound: sound)
    }

    func sendSessionCompletePrompt(duration: TimeInterval, label: String, sound: String) {
        NSSound(named: NSSound.Name(sound))?.play()
        guard Bundle.main.bundleIdentifier != nil else { return }
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
        guard Bundle.main.bundleIdentifier != nil else { return }
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
        guard Bundle.main.bundleIdentifier != nil else { return }
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
        guard Bundle.main.bundleIdentifier != nil else { return }
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
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = "Long break!"
        content.body = "You've been on break for \(minutes) minutes. Time to get back to work!"
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
        guard Bundle.main.bundleIdentifier != nil else { return }
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
}
