import Foundation

/// A lightweight data snapshot captured at the moment of a coach intervention.
/// Passed through `FocusCoachDecision.context` so the UI can build
/// personalised, data-driven messages without querying stores itself.
struct FocusCoachContext: Sendable {

    // MARK: - Idle & app state
    let idleSeconds: Int
    let frontmostAppName: String?
    let frontmostBundleIdentifier: String?
    let frontmostAppCategory: AppUsageCategory?
    let isInActiveSession: Bool

    // MARK: - Today's focus progress
    let todayFocusSeconds: TimeInterval
    let dailyGoalSeconds: TimeInterval
    let todaySessionCount: Int
    let selectedProjectName: String?

    // MARK: - Time of day
    let hourOfDay: Int

    // MARK: - Top distracting app today
    let topDistractingAppName: String?
    let topDistractingAppMinutes: Int

    // MARK: - Behavioural pattern signal
    /// Number of times the user selected "low priority work" as skip reason in the last 7 days.
    let recentLowPriorityWorkCount: Int
    let suggestedBlockTarget: String?
    let blockRecommendationReason: String?
    let inReleaseWindow: Bool

    // MARK: - Derived helpers

    /// 0.0–1.0 progress toward daily goal.
    var goalProgress: Double {
        guard dailyGoalSeconds > 0 else { return 0 }
        return min(todayFocusSeconds / dailyGoalSeconds, 1.0)
    }

    /// True when the frontmost app is classified as distracting.
    var isInDistractingApp: Bool {
        frontmostAppCategory == .distracting && frontmostAppName != nil
    }

    var hasBlockRecommendation: Bool {
        suggestedBlockTarget?.isEmpty == false
    }

    /// Formatted idle duration for display (e.g. "23m" or "1h 4m").
    var formattedIdle: String {
        let minutes = idleSeconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let h = minutes / 60; let m = minutes % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }
}

/// App category subset used for context (mirrors `AppUsageEntry.AppCategory`).
/// Kept separate so `FocusCoachContext` doesn't import the model layer.
enum AppUsageCategory: String, Sendable {
    case productive
    case neutral
    case distracting
}
