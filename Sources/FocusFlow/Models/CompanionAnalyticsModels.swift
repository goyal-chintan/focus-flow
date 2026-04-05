import Foundation

enum CompanionAnalyticsWindow: CaseIterable {
    case today
    case trailing7Days
    case trailing30Days

    func dateInterval(relativeTo now: Date, calendar: Calendar) -> DateInterval? {
        let dayStart = calendar.startOfDay(for: now)
        guard let intervalEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
            return nil
        }

        switch self {
        case .today:
            return DateInterval(start: dayStart, end: intervalEnd)
        case .trailing7Days:
            guard let intervalStart = calendar.date(byAdding: .day, value: -6, to: dayStart) else {
                return nil
            }
            return DateInterval(start: intervalStart, end: intervalEnd)
        case .trailing30Days:
            guard let intervalStart = calendar.date(byAdding: .day, value: -29, to: dayStart) else {
                return nil
            }
            return DateInterval(start: intervalStart, end: intervalEnd)
        }
    }
}

enum CompanionAnalyticsDomainEmptyState: Equatable {
    case trackingDisabled
    case noValidDomainsYet
}

enum CompanionAnalyticsRowKind: Equatable {
    case app
    case domain
}

struct CompanionAnalyticsRow: Identifiable, Equatable {
    let id: String
    let label: String
    let bundleIdentifier: String
    let kind: CompanionAnalyticsRowKind
    let category: AppUsageEntry.AppCategory
    let duringFocusSeconds: Int
    let outsideFocusSeconds: Int

    var totalSeconds: Int {
        duringFocusSeconds + outsideFocusSeconds
    }
}

struct CompanionAnalyticsWindowSnapshot: Equatable {
    let window: CompanionAnalyticsWindow
    let rows: [CompanionAnalyticsRow]
    let domainRows: [CompanionAnalyticsRow]
    let domainEmptyState: CompanionAnalyticsDomainEmptyState?

    var totalTrackedSeconds: Int {
        rows.reduce(0) { $0 + $1.totalSeconds }
    }
}

struct CompanionAnalyticsReport: Equatable {
    let today: CompanionAnalyticsWindowSnapshot
    let trailing7Days: CompanionAnalyticsWindowSnapshot
    let trailing30Days: CompanionAnalyticsWindowSnapshot

    func snapshot(for window: CompanionAnalyticsWindow) -> CompanionAnalyticsWindowSnapshot {
        switch window {
        case .today:
            return today
        case .trailing7Days:
            return trailing7Days
        case .trailing30Days:
            return trailing30Days
        }
    }
}
