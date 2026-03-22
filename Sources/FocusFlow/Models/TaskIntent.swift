import Foundation
import SwiftData

/// Captures the user's pre-session intention: what they plan to work on, expected difficulty,
/// and suggested duration. Used by the coach to calibrate risk scoring and measure start delay.
@Model
final class TaskIntent {
    var id: UUID
    var title: String
    var taskTypeRawValue: String
    var expectedResistance: Int
    var suggestedDurationMinutes: Int?
    var successCriteria: String?
    var sessionId: UUID?
    var createdAt: Date

    var taskType: FocusCoachTaskType {
        get { FocusCoachTaskType(rawValue: taskTypeRawValue) ?? .deepWork }
        set { taskTypeRawValue = newValue.rawValue }
    }

    init(
        title: String,
        taskType: FocusCoachTaskType = .deepWork,
        expectedResistance: Int = 3,
        suggestedDurationMinutes: Int? = nil,
        successCriteria: String? = nil,
        sessionId: UUID? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.taskTypeRawValue = taskType.rawValue
        self.expectedResistance = expectedResistance
        self.suggestedDurationMinutes = suggestedDurationMinutes
        self.successCriteria = successCriteria
        self.sessionId = sessionId
        self.createdAt = Date()
    }
}
