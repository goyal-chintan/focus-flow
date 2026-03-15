import Foundation

extension TimeInterval {
    var formattedFocusTime: String {
        let h = Int(self) / 3600
        let m = (Int(self) % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}
