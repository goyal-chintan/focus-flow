import Foundation

// MARK: - Task Classification

enum FocusCoachTaskType: String, Codable, CaseIterable {
    case deepWork
    case admin
    case learning
    case creative

    var displayName: String {
        switch self {
        case .deepWork: "Deep"
        case .admin: "Admin"
        case .learning: "Learn"
        case .creative: "Create"
        }
    }

    var icon: String {
        switch self {
        case .deepWork: "brain.head.profile"
        case .admin: "tray.full.fill"
        case .learning: "book.fill"
        case .creative: "paintbrush.fill"
        }
    }
}

// MARK: - Skip / Snooze Reasons (Why User is Declining to Focus Right Now)

/// A user-selected reason for skipping or snoozing a coach intervention.
enum FocusCoachSkipReason: String, CaseIterable, Sendable {
    // MARK: Genuine reasons (isLegitimate = true → snooze extended to 20m)
    case urgentTask       = "urgentTask"
    case inMeeting        = "inMeeting"
    case takingBreak      = "takingBreak"
    case notWell          = "notWell"

    // MARK: Being honest (isLegitimate = false)
    case lowPriorityWork  = "lowPriorityWork"
    case procrastinating  = "procrastinating"
    case cantFocus        = "cantFocus"
    case justTired        = "justTired"
    case doneForToday     = "doneForToday"

    var displayName: String {
        switch self {
        case .urgentTask:      "Urgent task"
        case .inMeeting:       "In a meeting"
        case .takingBreak:     "Real break"
        case .notWell:         "Not feeling well"
        case .lowPriorityWork: "Low-priority work"
        case .procrastinating: "Procrastinating"
        case .cantFocus:       "Can't focus"
        case .justTired:       "Just tired"
        case .doneForToday:    "Done for today"
        }
    }

    var icon: String {
        switch self {
        case .urgentTask:      "🔥"
        case .inMeeting:       "🗓"
        case .takingBreak:     "☕"
        case .notWell:         "😓"
        case .lowPriorityWork: "🔀"
        case .procrastinating: "😬"
        case .cantFocus:       "🌀"
        case .justTired:       "🛋"
        case .doneForToday:    "🌙"
        }
    }

    /// Genuine reasons = legitimate interruptions → extend snooze to 20m
    var isLegitimate: Bool {
        switch self {
        case .urgentTask, .inMeeting, .takingBreak, .notWell: return true
        default: return false
        }
    }

    /// Group label for the skip reason panel
    var group: SkipReasonGroup {
        isLegitimate ? .genuineReason : .beingHonest
    }

    enum SkipReasonGroup: String {
        case genuineReason = "Genuine reason"
        case beingHonest   = "Being honest"
    }

    /// Genuine reasons in display order
    static let genuineReasons: [FocusCoachSkipReason] =
        [.urgentTask, .inMeeting, .takingBreak, .notWell]

    /// Honest reasons in display order
    static let honestReasons: [FocusCoachSkipReason] =
        [.lowPriorityWork, .procrastinating, .cantFocus, .justTired, .doneForToday]
}

// MARK: - Anomaly Reasons (Why Focus Was Interrupted)

enum FocusCoachReason: String, Codable, CaseIterable {
    case urgentMeeting
    case familyPersonal
    case stressSpike
    case fatigue
    case legitDistraction
    case resistanceAvoidance
    case taskComplete
    case higherPriority
    case contextChanged
    case other

    var displayName: String {
        switch self {
        case .urgentMeeting: "Urgent Meeting"
        case .familyPersonal: "Family / Personal"
        case .stressSpike: "Stress Spike"
        case .fatigue: "Fatigue"
        case .legitDistraction: "Legit Distraction"
        case .resistanceAvoidance: "Resistance / Avoidance"
        case .taskComplete: "Task Complete"
        case .higherPriority: "Higher Priority"
        case .contextChanged: "Context Changed"
        case .other: "Other"
        }
    }

    /// Reasons considered legitimate (not avoidance) for false-positive dampening
    var isLegitimate: Bool {
        switch self {
        case .urgentMeeting, .familyPersonal, .stressSpike, .fatigue, .legitDistraction,
             .taskComplete, .higherPriority, .contextChanged:
            return true
        case .resistanceAvoidance, .other:
            return false
        }
    }

    static let legitimateChips: [FocusCoachReason] = [
        .urgentMeeting, .familyPersonal, .stressSpike, .fatigue,
        .legitDistraction, .taskComplete, .higherPriority, .contextChanged
    ]

    static let avoidantChips: [FocusCoachReason] = [
        .resistanceAvoidance, .other
    ]
}

// MARK: - Interruption Classification

enum FocusCoachInterruptionKind: String, Codable, CaseIterable {
    case missedStart
    case fakeStart
    case drift
    case breakOverrun
    case midSessionStop
    case projectSwitch

    var displayName: String {
        switch self {
        case .missedStart: "Missed Start"
        case .fakeStart: "Fake Start"
        case .drift: "Drift"
        case .breakOverrun: "Break Overrun"
        case .midSessionStop: "Mid-Session Stop"
        case .projectSwitch: "Project Switch"
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

// MARK: - Coach Intervention Mode

enum FocusCoachInterventionMode: String, Codable, CaseIterable {
    case balanced
    case adaptiveStrict
    case sessionRescue

    var displayName: String {
        switch self {
        case .balanced: "Balanced"
        case .adaptiveStrict: "Adaptive Strict"
        case .sessionRescue: "Session Rescue"
        }
    }
}
