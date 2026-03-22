import Foundation
import SwiftData

/// Records a coach-detected anomaly during a focus session (drift, break overrun, mid-session stop, etc.)
/// along with an optional user-supplied reason to distinguish legitimate interruptions from avoidance.
@Model
final class CoachInterruption {
    var id: UUID
    var sessionId: UUID
    var kindRawValue: String
    var reasonRawValue: String?
    var detectedAt: Date
    var riskScoreAtDetection: Double

    var kind: FocusCoachInterruptionKind {
        get { FocusCoachInterruptionKind(rawValue: kindRawValue) ?? .drift }
        set { kindRawValue = newValue.rawValue }
    }

    var reason: FocusCoachReason? {
        get { reasonRawValue.flatMap { FocusCoachReason(rawValue: $0) } }
        set { reasonRawValue = newValue?.rawValue }
    }

    var isLegitimate: Bool {
        reason?.isLegitimate ?? false
    }

    init(
        sessionId: UUID,
        kind: FocusCoachInterruptionKind,
        reason: FocusCoachReason? = nil,
        riskScoreAtDetection: Double = 0
    ) {
        self.id = UUID()
        self.sessionId = sessionId
        self.kindRawValue = kind.rawValue
        self.reasonRawValue = reason?.rawValue
        self.detectedAt = Date()
        self.riskScoreAtDetection = riskScoreAtDetection
    }
}
