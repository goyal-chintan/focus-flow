import Foundation
import SwiftData

@Model
final class AppSettings {
    var focusDuration: TimeInterval
    var shortBreakDuration: TimeInterval
    var longBreakDuration: TimeInterval
    var sessionsBeforeLongBreak: Int
    var autoStartBreak: Bool
    var autoStartNextSession: Bool
    var launchAtLogin: Bool
    var completionSound: String

    init() {
        self.focusDuration = 25 * 60
        self.shortBreakDuration = 5 * 60
        self.longBreakDuration = 15 * 60
        self.sessionsBeforeLongBreak = 4
        self.autoStartBreak = true
        self.autoStartNextSession = false
        self.launchAtLogin = false
        self.completionSound = "Glass"
    }
}
