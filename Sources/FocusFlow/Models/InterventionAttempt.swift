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
    var skipReasonRaw: String?
    var deliveredAt: Date
    var resolvedAt: Date?

    // Coach v2.1 learning fields (optional: no migration needed).
    /// `CoachSurface` raw value.
    var surfaceRawValue: String?
    /// `CoachStyle` raw value of the message shown.
    var styleRawValue: String?
    /// Bandit context bucket, e.g. "avail:high|idle:30-90|front:work|today:0".
    var contextKey: String?
    /// Learned reward once resolved: +1 start, +0.5 completed, ±0.5 outcome rating.
    var reward: Double?

    var kind: FocusCoachInterventionKind {
        get { FocusCoachInterventionKind(rawValue: kindRawValue) ?? .softNudge }
        set { kindRawValue = newValue.rawValue }
    }

    var outcome: FocusCoachOutcome? {
        get { outcomeRawValue.flatMap { FocusCoachOutcome(rawValue: $0) } }
        set { outcomeRawValue = newValue?.rawValue }
    }

    var skipReason: FocusCoachSkipReason? {
        get { skipReasonRaw.flatMap { FocusCoachSkipReason(rawValue: $0) } }
        set { skipReasonRaw = newValue?.rawValue }
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
        self.skipReasonRaw = nil
        self.deliveredAt = Date()
        self.resolvedAt = nil
    }
}
