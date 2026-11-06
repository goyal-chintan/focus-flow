import SwiftData

/// Every model the app's store holds. The app opens its store with exactly this list, and the
/// upgrade test opens an older store with it, so the two can't drift apart.
enum FocusFlowSchema {
    static let models: [any PersistentModel.Type] = [
        Project.self, FocusSession.self, AppSettings.self, TimeSplit.self, BlockProfile.self, AppUsageRecord.self, AppUsageEntry.self,
        TaskIntent.self, CoachInterruption.self, InterventionAttempt.self, BreakLearningEvent.self, IdleDistractionItem.self,
        WeeklyPriority.self, PlannedBlock.self, ProjectGoal.self, GoalKeyResult.self, GoalProgressEntry.self, DailyTask.self,
        BlockStartEvent.self,
        // Coach v8 (6 Nov 2026).
        ActivityHour.self, DayLabel.self, AppRoleRuleRecord.self,
    ]

    static var schema: Schema { Schema(models) }
}
