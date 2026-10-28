import Foundation
import SwiftData

/// The honest one-line "today" (screen audit: "Honest total"):
/// "3h 50m tracked · 50m on your #1 · 22% own work". Shared by the popover footer and the notch.
@MainActor
enum TodayVerdict {
    static func text(modelContext: ModelContext, now: Date = Date()) -> String? {
        let projects = (try? modelContext.fetch(FetchDescriptor<Project>(predicate: #Predicate { !$0.archived }))) ?? []
        let dayStart = Calendar.current.startOfDay(for: now)
        let since = dayStart.addingTimeInterval(-12 * 3600)
        let sessions = (try? modelContext.fetch(FetchDescriptor<FocusSession>(predicate: #Predicate { $0.startedAt >= since }))) ?? []
        let samples = sessions.filter { $0.type == .focus }.map(FocusSample.init)
        let day = DateInterval(start: dayStart, end: dayStart.addingTimeInterval(86_400))
        let allocation = GoalDataBuilder.allocation(samples: samples, projects: projects, day: day)
        // Under a minute reads as "0m tracked": say nothing yet.
        return allocation.totalSeconds >= 60 ? allocation.shortVerdict(format: FFFormat.duration) : nil
    }
}
