import Foundation
import Combine

@MainActor
final class CompanionAnalyticsReportCoordinator: ObservableObject {
    @Published private(set) var report: CompanionAnalyticsReport

    private let debounceNanoseconds: UInt64
    private var hasComputedInitialReport = false
    private var pendingRefreshTask: Task<Void, Never>?

    init(debounceInterval: TimeInterval = 0.35, initialNow: Date = Date()) {
        self.debounceNanoseconds = UInt64(max(0, debounceInterval) * 1_000_000_000)
        self.report = CompanionAnalyticsBuilder().build(
            entries: [],
            domainTrackingEnabled: false,
            now: initialNow
        )
    }

    deinit {
        pendingRefreshTask?.cancel()
    }

    func scheduleRefresh(
        entries: [AppUsageEntry],
        domainTrackingEnabled: Bool,
        now: Date,
        buildReport: @escaping ([AppUsageEntry], Bool, Date) -> CompanionAnalyticsReport
    ) {
        pendingRefreshTask?.cancel()

        if !hasComputedInitialReport {
            hasComputedInitialReport = true
            report = buildReport(entries, domainTrackingEnabled, now)
            return
        }

        pendingRefreshTask = Task { [debounceNanoseconds] in
            if debounceNanoseconds > 0 {
                do {
                    try await Task.sleep(nanoseconds: debounceNanoseconds)
                } catch {
                    return
                }
            }

            guard !Task.isCancelled else { return }
            report = buildReport(entries, domainTrackingEnabled, now)
        }
    }
}
