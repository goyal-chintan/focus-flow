import Foundation
import SwiftData

/// Records each intervention the coach delivers and its outcome, enabling the weekly
/// personalization loop to upweight effective interventions and suppress noisy ones.
@Model
final class InterventionAttempt {
    var id: UUID
    var sessionId: UUID?
    var kindRawValue: String
    var riskScore: Double
    var dismissed: Bool
    var outcomeRawValue: String?
    var deliveredAt: Date
    var resolvedAt: Date?

    var kind: FocusCoachInterventionKind {
        get { FocusCoachInterventionKind(rawValue: kindRawValue) ?? .softNudge }
        set { kindRawValue = newValue.rawValue }
    }

    var outcome: FocusCoachOutcome? {
        get { outcomeRawValue.flatMap { FocusCoachOutcome(rawValue: $0) } }
        set { outcomeRawValue = newValue?.rawValue }
    }

    init(
        kind: FocusCoachInterventionKind,
        riskScore: Double,
        sessionId: UUID? = nil
    ) {
        self.id = UUID()
        self.sessionId = sessionId
        self.kindRawValue = kind.rawValue
        self.riskScore = riskScore
        self.dismissed = false
        self.outcomeRawValue = nil
        self.deliveredAt = Date()
        self.resolvedAt = nil
    }
}
