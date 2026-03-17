import UserNotifications
import AppKit

@MainActor
final class NotificationService {
    static let shared = NotificationService()
    private init() {}

    func requestPermission() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
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
        UNUserNotificationCenter.current().add(request)
    }

    func sendPauseWarning(minutes: Int) {
        NSSound(named: NSSound.Name("Bottle"))?.play()
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = "Pause getting long"
        content.body = "You've been paused for \(minutes) minutes. Ready to get back to it?"
        content.sound = .default
        let request = UNNotificationRequest(identifier: "pause-warning", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func sendPauseCritical(minutes: Int) {
        NSSound(named: NSSound.Name("Sosumi"))?.play()
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = "Long pause!"
        content.body = "You've been paused for \(minutes) minutes. Consider resuming or ending the session."
        content.sound = UNNotificationSound.defaultCritical
        let request = UNNotificationRequest(identifier: "pause-critical", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func send(title: String, body: String, sound: String) {
        NSSound(named: NSSound.Name(sound))?.play()
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: sound + ".aiff"))
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
