import Foundation

extension Notification.Name {
    /// Posted after a focus session is manually logged from ManualSessionView so that
    /// TimerViewModel can refresh the menu-bar today-total immediately.
    static let focusSessionLoggedManually = Notification.Name("com.focusflow.focusSessionLoggedManually")
}
