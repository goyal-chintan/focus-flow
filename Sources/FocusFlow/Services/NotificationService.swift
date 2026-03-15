import UserNotifications
import AppKit

final class NotificationService {
    static let shared = NotificationService()
    private init() {}

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func sendFocusComplete(sound: String) {
        send(title: "Focus session complete!", body: "Great work! Time for a break.", sound: sound)
    }

    func sendBreakComplete(sound: String) {
        send(title: "Break's over!", body: "Ready to focus again?", sound: sound)
    }

    private func send(title: String, body: String, sound: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
        NSSound(named: NSSound.Name(sound))?.play()
    }
}
