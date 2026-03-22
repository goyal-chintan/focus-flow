import Foundation

// MARK: - Task Classification

enum FocusCoachTaskType: String, Codable, CaseIterable {
    case deepWork
    case admin
    case learning
    case creative

    var displayName: String {
        switch self {
        case .deepWork: "Deep Work"
        case .admin: "Admin"
        case .learning: "Learning"
        case .creative: "Creative"
        }
    }
}

// MARK: - Anomaly Reasons (Why Focus Was Interrupted)

enum FocusCoachReason: String, Codable, CaseIterable {
    case urgentMeeting
    case familyPersonal
    case stressSpike
    case fatigue
    case legitDistraction
    case resistanceAvoidance
    case other

    var displayName: String {
        switch self {
        case .urgentMeeting: "Urgent Meeting"
        case .familyPersonal: "Family / Personal"
        case .stressSpike: "Stress Spike"
        case .fatigue: "Fatigue"
        case .legitDistraction: "Legit Distraction"
        case .resistanceAvoidance: "Resistance / Avoidance"
        case .other: "Other"
        }
    }

    /// Reasons considered legitimate (not avoidance) for false-positive dampening
    var isLegitimate: Bool {
        switch self {
        case .urgentMeeting, .familyPersonal, .stressSpike, .fatigue, .legitDistraction:
            return true
        case .resistanceAvoidance, .other:
            return false
        }
    }
}

// MARK: - Interruption Classification

enum FocusCoachInterruptionKind: String, Codable, CaseIterable {
    case missedStart
    case fakeStart
    case drift
    case breakOverrun
    case midSessionStop

    var displayName: String {
        switch self {
        case .missedStart: "Missed Start"
        case .fakeStart: "Fake Start"
        case .drift: "Drift"
        case .breakOverrun: "Break Overrun"
        case .midSessionStop: "Mid-Session Stop"
        }
    }
}

// MARK: - Intervention Types (Escalation Ladder)

enum FocusCoachInterventionKind: String, Codable, CaseIterable {
    case softNudge
    case quickPrompt
    case strongPrompt

    var displayName: String {
        switch self {
        case .softNudge: "Soft Nudge"
        case .quickPrompt: "Quick Prompt"
        case .strongPrompt: "Strong Prompt"
        }
    }
}

// MARK: - Intervention Outcomes

enum FocusCoachOutcome: String, Codable, CaseIterable {
    case improved
    case ignored
    case snoozed
    case dismissed

    var displayName: String {
        switch self {
        case .improved: "Improved"
        case .ignored: "Ignored"
        case .snoozed: "Snoozed"
        case .dismissed: "Dismissed"
        }
    }
}

// MARK: - Risk Levels

enum FocusCoachRiskLevel: String, Codable, CaseIterable {
    case stable
    case driftRisk
    case highRisk

    var displayName: String {
        switch self {
        case .stable: "Stable"
        case .driftRisk: "Drift Risk"
        case .highRisk: "High Risk"
        }
    }
}
