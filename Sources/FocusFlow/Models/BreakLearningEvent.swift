import Foundation
import SwiftData

@Model
final class BreakLearningEvent {
    var id: UUID
    var createdAt: Date
    var projectId: UUID?
    var workModeRawValue: String
    var suggestedMinutes: Int
    var choseSuggested: Bool
    var actualBreakSeconds: Int
    var returnedToFocus: Bool
    var endedEarly: Bool
    var overrunSeconds: Int
    /// Coach v6 §3.4: why a break ran 5+ min over, when the user said (`BreakOverrunReason`).
    var overrunReasonRaw: String? = nil

    var overrunReason: BreakOverrunReason? { overrunReasonRaw.flatMap(BreakOverrunReason.init(rawValue:)) }

    var workMode: WorkMode {
        get { WorkMode(rawValue: workModeRawValue) ?? .deepWork }
        set { workModeRawValue = newValue.rawValue }
    }

    init(
        projectId: UUID?,
        workMode: WorkMode,
        suggestedMinutes: Int,
        choseSuggested: Bool,
        actualBreakSeconds: Int,
        returnedToFocus: Bool,
        endedEarly: Bool,
        overrunSeconds: Int
    ) {
        self.id = UUID()
        self.createdAt = Date()
        self.projectId = projectId
        self.workModeRawValue = workMode.rawValue
        self.suggestedMinutes = suggestedMinutes
        self.choseSuggested = choseSuggested
        self.actualBreakSeconds = actualBreakSeconds
        self.returnedToFocus = returnedToFocus
        self.endedEarly = endedEarly
        self.overrunSeconds = overrunSeconds
    }
}
