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

    // Coach v5 learning fields (optional: no migration needed). A decision row is logged at every
    // decision point, including the ones where the coach stayed quiet (docs/plans/2026-10-28-coach-v5-learning-engine-design.md).
    /// "prompt" for a Learner A decision point.
    var decisionRaw: String?
    /// `CoachPromptFeatures` vector at the decision, comma-separated.
    var featuresRaw: String?
    /// Probability the coach prompted with (nil when forced, e.g. by a test override).
    var propensity: Double?
    /// Whether it prompted.
    var treated: Bool?
    /// Block size asked for (Learner B).
    var askedMinutes: Int?
    /// `CoachSizePolicy.Context` vector at the ask, comma-separated.
    var sizeFeaturesRaw: String?

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
