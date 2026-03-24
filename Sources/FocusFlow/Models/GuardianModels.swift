import Foundation

// MARK: - Completed Block Context
/// Durable record of an earned focus block. Replaces transient lastCompletedSession.
/// Must survive: complete -> take break, complete -> defer break -> next block, complete -> end day.
/// Cleared only when: newer block completes, day-close summary dismissed, day rollover.
struct CompletedBlockContext: Equatable {
    let sessionId: UUID
    let projectName: String
    let projectId: UUID?
    let durationMinutes: Int
    let workMode: WorkMode
    let earnedAt: Date
    var carryForwardNote: String?
}

// MARK: - Break Episode Context
/// Tracks a break period separately from the earned focus block.
struct BreakEpisodeContext {
    let earnedBlock: CompletedBlockContext
    let breakStarted: Date
    let plannedDurationSeconds: Int
    var breakEnded: Date?
    var overrunSeconds: Int {
        guard let ended = breakEnded else {
            return max(0, Int(Date().timeIntervalSince(breakStarted)) - plannedDurationSeconds)
        }
        return max(0, Int(ended.timeIntervalSince(breakStarted)) - plannedDurationSeconds)
    }
    var recoveryQuality: BreakRecoveryQuality?
}

// MARK: - Break Recovery Quality
enum BreakRecoveryQuality: String, Codable, CaseIterable {
    case stillRecovering  = "still_recovering"
    case doneForNow       = "done_for_now"
    case gotDistracted    = "got_distracted"

    var displayName: String {
        switch self {
        case .stillRecovering: return "Still recovering"
        case .doneForNow:      return "Done for now"
        case .gotDistracted:   return "Got distracted"
        }
    }
}

// MARK: - Explicit Opt-Out Reason
enum ExplicitOptOutReason: String, Codable, CaseIterable {
    case offDuty      = "off_duty"
    case doneForNow   = "done_for_now"
    case tooTired     = "too_tired"
    case realBreak    = "real_break"
    case meeting      = "meeting"

    /// Suppression duration in seconds after this opt-out
    var suppressionDuration: TimeInterval {
        switch self {
        case .offDuty:    return 90 * 60
        case .doneForNow: return 60 * 60
        case .tooTired:   return 60 * 60
        case .realBreak:  return 45 * 60
        case .meeting:    return 45 * 60
        }
    }
}

// MARK: - Intervention Suppression Window
/// Suppresses hard guardian challenges after explicit opt-out.
struct InterventionSuppressionWindow {
    let reason: ExplicitOptOutReason
    let suppressedAt: Date

    var expiresAt: Date {
        suppressedAt.addingTimeInterval(reason.suppressionDuration)
    }

    var isActive: Bool {
        Date() < expiresAt
    }
}

// MARK: - Guardian Engagement Mode
/// Derived from Project.guardianSensitivity. Controls intervention thresholds.
enum GuardianEngagementMode: String, Codable {
    case strict    // Lower confidence thresholds, faster escalation
    case adaptive  // Default context-aware behavior
    case passive   // Ambient ring only, no popover prompts or hard dialogs

    /// In-session challenge threshold (driftConfidence >= this → .challenge)
    var inSessionChallengeThreshold: Double {
        switch self {
        case .strict:   return 0.5
        case .adaptive: return 0.7
        case .passive:  return 1.1  // effectively disabled
        }
    }

    /// Outside-session challenge threshold
    var outsideSessionChallengeThreshold: Double {
        switch self {
        case .strict:   return 0.65
        case .adaptive: return 0.8
        case .passive:  return 1.1
        }
    }
}

// MARK: - Work Mode
enum WorkMode: String, Codable, CaseIterable {
    case deepWork  = "deep_work"
    case learning  = "learning"
    case admin     = "admin"
    case creative  = "creative"

    var displayName: String {
        switch self {
        case .deepWork: return "Deep Work"
        case .learning: return "Learning"
        case .admin:    return "Admin"
        case .creative: return "Creative"
        }
    }

    var icon: String {
        switch self {
        case .deepWork: return "brain.head.profile"
        case .learning: return "book.fill"
        case .admin:    return "tray.full.fill"
        case .creative: return "paintbrush.fill"
        }
    }
}

// MARK: - Difficulty Bias
enum DifficultyBias: String, Codable, CaseIterable {
    case light    = "light"
    case moderate = "moderate"
    case heavy    = "heavy"

    var displayName: String {
        switch self {
        case .light:    return "Light"
        case .moderate: return "Moderate"
        case .heavy:    return "Heavy"
        }
    }
}

// MARK: - Guardian Sensitivity
enum GuardianSensitivity: String, Codable, CaseIterable {
    case normal = "normal"
    case strict = "strict"

    var displayName: String {
        switch self {
        case .normal: return "Normal"
        case .strict: return "Strict"
        }
    }

    var engagementMode: GuardianEngagementMode {
        switch self {
        case .normal: return .adaptive
        case .strict: return .strict
        }
    }
}
