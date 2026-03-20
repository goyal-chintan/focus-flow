import Foundation
import SwiftData

@Model
final class AppUsageRecord {
    var date: Date
    var focusFlowOpenSeconds: Int
    var totalFocusSeconds: Int

    init(date: Date = Calendar.current.startOfDay(for: Date())) {
        self.date = date
        self.focusFlowOpenSeconds = 0
        self.totalFocusSeconds = 0
    }

    var efficiencyRatio: Double {
        guard focusFlowOpenSeconds > 0 else { return 0 }
        return Double(totalFocusSeconds) / Double(focusFlowOpenSeconds)
    }
}
