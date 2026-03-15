import Foundation

enum SessionType: String, Codable, CaseIterable {
    case focus
    case shortBreak
    case longBreak

    var displayName: String {
        switch self {
        case .focus: "Focus"
        case .shortBreak: "Short Break"
        case .longBreak: "Long Break"
        }
    }
}
