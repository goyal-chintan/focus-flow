import Foundation

enum FocusMood: String, Codable, CaseIterable {
    case distracted = "Distracted"
    case neutral = "Neutral"
    case focused = "Focused"
    case deepFocus = "Deep Focus"

    var icon: String {
        switch self {
        case .distracted: "wind"
        case .neutral: "minus.circle"
        case .focused: "eye"
        case .deepFocus: "brain.head.profile"
        }
    }
}
