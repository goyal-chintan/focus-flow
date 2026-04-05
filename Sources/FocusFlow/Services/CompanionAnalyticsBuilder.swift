import Foundation

struct CompanionAnalyticsBuilder {
    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func build(
        entries: [AppUsageEntry],
        domainTrackingEnabled: Bool,
        now: Date = Date()
    ) -> CompanionAnalyticsReport {
        CompanionAnalyticsReport(
            today: buildSnapshot(
                for: .today,
                entries: entries,
                domainTrackingEnabled: domainTrackingEnabled,
                now: now
            ),
            trailing7Days: buildSnapshot(
                for: .trailing7Days,
                entries: entries,
                domainTrackingEnabled: domainTrackingEnabled,
                now: now
            ),
            trailing30Days: buildSnapshot(
                for: .trailing30Days,
                entries: entries,
                domainTrackingEnabled: domainTrackingEnabled,
                now: now
            )
        )
    }

    static func isPersistedDomainBundleIdentifier(_ bundleIdentifier: String) -> Bool {
        bundleIdentifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .hasPrefix("domain:")
    }

    static func validPersistedDomainHost(for bundleIdentifier: String) -> String? {
        let trimmed = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("domain:") else {
            return nil
        }

        let rawHost = String(trimmed.dropFirst("domain:".count))
        return AppUsageEntry.normalizedBrowserHost(from: rawHost)
    }

    private func buildSnapshot(
        for window: CompanionAnalyticsWindow,
        entries: [AppUsageEntry],
        domainTrackingEnabled: Bool,
        now: Date
    ) -> CompanionAnalyticsWindowSnapshot {
        guard let interval = window.dateInterval(relativeTo: now, calendar: calendar) else {
            return CompanionAnalyticsWindowSnapshot(
                window: window,
                rows: [],
                domainRows: [],
                domainEmptyState: resolveDomainEmptyState(domainTrackingEnabled: domainTrackingEnabled)
            )
        }

        var grouped: [String: RowAccumulator] = [:]

        for entry in entries where contains(entry.date, in: interval) && entry.totalSeconds > 0 {
            guard let candidate = candidate(for: entry, domainTrackingEnabled: domainTrackingEnabled) else {
                continue
            }

            if var existing = grouped[candidate.bundleIdentifier] {
                existing.duringFocusSeconds += candidate.duringFocusSeconds
                existing.outsideFocusSeconds += candidate.outsideFocusSeconds
                grouped[candidate.bundleIdentifier] = existing
            } else {
                grouped[candidate.bundleIdentifier] = candidate
            }
        }

        let aggregatedRows = grouped.values.map(\.row)
        let unsortedDomainRows = aggregatedRows.filter { $0.kind == .domain }
        let browserAppRows = aggregatedRows.filter {
            $0.kind == .app && AppUsageEntry.isBrowserBundleIdentifier($0.bundleIdentifier)
        }

        var rows = aggregatedRows.filter { row in
            guard !unsortedDomainRows.isEmpty else { return true }
            return !(row.kind == .app && AppUsageEntry.isBrowserBundleIdentifier(row.bundleIdentifier))
        }
        if let unresolvedBrowserRow = unresolvedBrowserRow(
            from: browserAppRows,
            domainRows: unsortedDomainRows
        ) {
            rows.append(unresolvedBrowserRow)
        }
        rows.sort(by: CompanionAnalyticsBuilder.rowComparator)
        let domainRows = rows.filter { $0.kind == .domain }

        return CompanionAnalyticsWindowSnapshot(
            window: window,
            rows: rows,
            domainRows: domainRows,
            domainEmptyState: domainRows.isEmpty
                ? resolveDomainEmptyState(domainTrackingEnabled: domainTrackingEnabled)
                : nil
        )
    }

    private func candidate(
        for entry: AppUsageEntry,
        domainTrackingEnabled: Bool
    ) -> RowAccumulator? {
        if let host = Self.validPersistedDomainHost(for: entry.bundleIdentifier) {
            guard domainTrackingEnabled else { return nil }
            let bundleIdentifier = "domain:\(host)"
            let label = AppUsageEntry.browserDomainDisplayLabel(for: host) ?? entry.appName
            let category = AppUsageEntry.classify(
                bundleIdentifier: bundleIdentifier,
                appName: label,
                browserHost: host
            )
            return RowAccumulator(
                label: label,
                bundleIdentifier: bundleIdentifier,
                kind: .domain,
                category: category,
                duringFocusSeconds: entry.duringFocusSeconds,
                outsideFocusSeconds: entry.outsideFocusSeconds
            )
        }

        if Self.isPersistedDomainBundleIdentifier(entry.bundleIdentifier) {
            return nil
        }

        let bundleIdentifier = normalizedAppBundleIdentifier(for: entry)
        return RowAccumulator(
            label: normalizedAppLabel(for: entry, bundleIdentifier: bundleIdentifier),
            bundleIdentifier: bundleIdentifier,
            kind: .app,
            category: entry.category,
            duringFocusSeconds: entry.duringFocusSeconds,
            outsideFocusSeconds: entry.outsideFocusSeconds
        )
    }

    private func normalizedAppBundleIdentifier(for entry: AppUsageEntry) -> String {
        let trimmed = entry.bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else {
            let fallbackName = entry.appName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return fallbackName.isEmpty ? "unknown-app" : "app:\(fallbackName)"
        }
        return trimmed
    }

    private func normalizedAppLabel(for entry: AppUsageEntry, bundleIdentifier: String) -> String {
        let trimmed = entry.appName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return AppUsageEntry.recommendationDisplayLabel(for: bundleIdentifier)
        }
        return trimmed
    }

    private func resolveDomainEmptyState(domainTrackingEnabled: Bool) -> CompanionAnalyticsDomainEmptyState {
        guard domainTrackingEnabled else {
            return .trackingDisabled
        }
        return .noValidDomainsYet
    }

    private static func rowComparator(lhs: CompanionAnalyticsRow, rhs: CompanionAnalyticsRow) -> Bool {
        if lhs.totalSeconds != rhs.totalSeconds {
            return lhs.totalSeconds > rhs.totalSeconds
        }
        let labelComparison = lhs.label.localizedCaseInsensitiveCompare(rhs.label)
        if labelComparison != .orderedSame {
            return labelComparison == .orderedAscending
        }
        return lhs.bundleIdentifier.localizedCaseInsensitiveCompare(rhs.bundleIdentifier) == .orderedAscending
    }

    private func contains(_ date: Date, in interval: DateInterval) -> Bool {
        date >= interval.start && date < interval.end
    }

    private func unresolvedBrowserRow(
        from browserRows: [CompanionAnalyticsRow],
        domainRows: [CompanionAnalyticsRow]
    ) -> CompanionAnalyticsRow? {
        guard !browserRows.isEmpty, !domainRows.isEmpty else {
            return nil
        }

        let unresolvedDuringFocusSeconds = max(
            0,
            browserRows.reduce(0) { $0 + $1.duringFocusSeconds }
                - domainRows.reduce(0) { $0 + $1.duringFocusSeconds }
        )
        let unresolvedOutsideFocusSeconds = max(
            0,
            browserRows.reduce(0) { $0 + $1.outsideFocusSeconds }
                - domainRows.reduce(0) { $0 + $1.outsideFocusSeconds }
        )

        guard unresolvedDuringFocusSeconds > 0 || unresolvedOutsideFocusSeconds > 0 else {
            return nil
        }

        let primaryBrowserRow = browserRows.max(by: { $0.totalSeconds < $1.totalSeconds })
        let label = browserRows.count == 1 ? (primaryBrowserRow?.label ?? "Browser") : "Browser"
        let bundleIdentifier = browserRows.count == 1
            ? (primaryBrowserRow?.bundleIdentifier ?? "browser.unresolved")
            : "browser.unresolved"

        return CompanionAnalyticsRow(
            id: "unresolved:\(bundleIdentifier)",
            label: label,
            bundleIdentifier: bundleIdentifier,
            kind: .app,
            category: .neutral,
            duringFocusSeconds: unresolvedDuringFocusSeconds,
            outsideFocusSeconds: unresolvedOutsideFocusSeconds
        )
    }
}

private struct RowAccumulator {
    let label: String
    let bundleIdentifier: String
    let kind: CompanionAnalyticsRowKind
    let category: AppUsageEntry.AppCategory
    var duringFocusSeconds: Int
    var outsideFocusSeconds: Int

    var row: CompanionAnalyticsRow {
        CompanionAnalyticsRow(
            id: bundleIdentifier,
            label: label,
            bundleIdentifier: bundleIdentifier,
            kind: kind,
            category: category,
            duringFocusSeconds: duringFocusSeconds,
            outsideFocusSeconds: outsideFocusSeconds
        )
    }
}
