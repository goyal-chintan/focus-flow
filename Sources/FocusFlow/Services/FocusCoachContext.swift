import Foundation

/// A lightweight data snapshot captured at the moment of a coach intervention.
/// Passed through `FocusCoachDecision.context` so the UI can build
/// personalised, data-driven messages without querying stores itself.
struct FocusCoachContext: Sendable {

    // MARK: - Idle & app state
    let idleSeconds: Int
    let frontmostAppName: String?
    let frontmostBundleIdentifier: String?
    let frontmostDisplayLabel: String?
    let frontmostDomainLabel: String?
    let frontmostAppCategory: AppUsageCategory?
    let isInActiveSession: Bool

    // MARK: - Today's focus progress
    let todayFocusSeconds: TimeInterval
    let dailyGoalSeconds: TimeInterval
    let todaySessionCount: Int
    let selectedProjectName: String?
    let selectedWorkMode: WorkMode?

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
    /// Seconds since the end of the user's most recent focus session; nil when unknown.
    /// Copy that says "since your last focused block" must use this, never `idleSeconds`.
    let secondsSinceLastFocusSession: Int?

    init(
        idleSeconds: Int,
        frontmostAppName: String?,
        frontmostBundleIdentifier: String?,
        frontmostDisplayLabel: String? = nil,
        frontmostDomainLabel: String? = nil,
        frontmostAppCategory: AppUsageCategory?,
        isInActiveSession: Bool,
        todayFocusSeconds: TimeInterval,
        dailyGoalSeconds: TimeInterval,
        todaySessionCount: Int,
        selectedProjectName: String?,
        selectedWorkMode: WorkMode?,
        hourOfDay: Int,
        topDistractingAppName: String?,
        topDistractingAppMinutes: Int,
        recentLowPriorityWorkCount: Int,
        suggestedBlockTarget: String?,
        blockRecommendationReason: String?,
        inReleaseWindow: Bool,
        secondsSinceLastFocusSession: Int? = nil
    ) {
        self.idleSeconds = idleSeconds
        self.frontmostAppName = frontmostAppName
        self.frontmostBundleIdentifier = frontmostBundleIdentifier
        self.frontmostDisplayLabel = frontmostDisplayLabel
        self.frontmostDomainLabel = frontmostDomainLabel
        self.frontmostAppCategory = frontmostAppCategory
        self.isInActiveSession = isInActiveSession
        self.todayFocusSeconds = todayFocusSeconds
        self.dailyGoalSeconds = dailyGoalSeconds
        self.todaySessionCount = todaySessionCount
        self.selectedProjectName = selectedProjectName
        self.selectedWorkMode = selectedWorkMode
        self.hourOfDay = hourOfDay
        self.topDistractingAppName = topDistractingAppName
        self.topDistractingAppMinutes = topDistractingAppMinutes
        self.recentLowPriorityWorkCount = recentLowPriorityWorkCount
        self.suggestedBlockTarget = suggestedBlockTarget
        self.blockRecommendationReason = blockRecommendationReason
        self.inReleaseWindow = inReleaseWindow
        self.secondsSinceLastFocusSession = secondsSinceLastFocusSession
    }

    // MARK: - Derived helpers

    /// 0.0–1.0 progress toward daily goal.
    var goalProgress: Double {
        guard dailyGoalSeconds > 0 else { return 0 }
        return min(todayFocusSeconds / dailyGoalSeconds, 1.0)
    }

    /// True when the frontmost app is classified as distracting.
    var isInDistractingApp: Bool {
        let hasForegroundContext = frontmostDisplayLabel != nil
            || frontmostAppName != nil
            || frontmostBundleIdentifier != nil
        return frontmostAppCategory == .distracting && hasForegroundContext
    }

    var hasBlockRecommendation: Bool {
        suggestedBlockTarget?.isEmpty == false
    }

    /// Formatted idle duration for display (e.g. "23m" or "1h 4m").
    var formattedIdle: String {
        Self.formatDuration(seconds: idleSeconds)
    }

    static func formatDuration(seconds: Int) -> String {
        let minutes = seconds / 60
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
