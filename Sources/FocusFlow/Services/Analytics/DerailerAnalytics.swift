import Foundation

// What derails you: app/site time outside focus blocks, for entries that are real derailers.
//
// A usage row counts when it is classified distracting (AppUsageEntry.classify, a known streaming
// site, or a rule the user confirmed in Settings → Distractions) and is never:
//  • a work tool (Slack, Cursor, Claude, Atlassian, Arc, GitHub, Zoom, …; Coach v2 §0/W2),
//  • something the user marked "allowed",
//  • a macOS system process (login window, screensaver, Dock, …).

enum DerailerClassifier {
    /// Same list as `AppUsageTracker.ignoredSystemBundleIdentifiers`, kept here so the engine stays actor-free.
    static let systemBundleIdentifiers: Set<String> = [
        "com.apple.loginwindow",
        "com.apple.screensaver.engine",
        "com.apple.usernotificationcenter",
        "com.apple.securityagent",
        "com.apple.dock",
        "com.apple.controlcenter",
        "com.apple.systemuiserver",
        "com.apple.notificationcenterui",
    ]

    /// Needles (matched against bundle id, app name and domain) for tools that are work, never derailers.
    static let workToolNeedles: [String] = [
        "slack", "cursor", "claude", "anthropic", "atlassian", "jira", "confluence",
        "thebrowser", "arc", "github", "gitlab", "zoom", "teams", "intellij", "jetbrains",
        "obsidian", "copilot", "antigravity", "notion", "figma", "xcode", "vscode",
        "terminal", "iterm", "ghostty", "warp", "mail.google", "calendar.google", "docs.google",
        "linear", "chatgpt", "openai", "focusflow",
    ]

    /// Streaming/social destinations that `AppUsageEntry.classify` does not know by name.
    static let extraDerailerNeedles: [String] = [
        "zee5", "hotstar", "primevideo", "prime video", "sonyliv", "jiocinema", "hulu", "disneyplus", "disney+",
    ]

    static func host(of sample: UsageSample) -> String? {
        CompanionAnalyticsBuilder.validPersistedDomainHost(for: sample.bundleIdentifier)
    }

    static func isSystemProcess(_ sample: UsageSample) -> Bool {
        systemBundleIdentifiers.contains(sample.bundleIdentifier.lowercased())
    }

    static func isWorkTool(_ sample: UsageSample) -> Bool {
        let haystacks = [sample.bundleIdentifier.lowercased(), sample.appName.lowercased(), host(of: sample) ?? ""]
        return workToolNeedles.contains { needle in
            haystacks.contains { haystack in
                guard !haystack.isEmpty else { return false }
                // "arc" and "teams" are short: match whole tokens so "search" or "steams" don't count.
                if needle.count <= 5 {
                    return haystack.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).contains { $0 == needle }
                }
                return haystack.contains(needle)
            }
        }
    }

    /// Whether `sample` matches one of the rule keys (bundle ids or hosts, lowercased).
    static func matches(_ sample: UsageSample, keys: Set<String>) -> Bool {
        guard !keys.isEmpty else { return false }
        let bundle = sample.bundleIdentifier.lowercased()
        if keys.contains(bundle) { return true }
        if let host = host(of: sample) {
            return keys.contains { host == $0 || host.hasSuffix("." + $0) }
        }
        return false
    }

    static func isDerailer(_ sample: UsageSample, confirmedKeys: Set<String> = [], allowedKeys: Set<String> = []) -> Bool {
        // Your rules come first (coach v8): a confirmed "Ghostty · Strong" used to lose to the
        // built-in work-tool list.
        guard !isSystemProcess(sample), !matches(sample, keys: allowedKeys) else { return false }
        if matches(sample, keys: confirmedKeys) { return true }
        guard !isWorkTool(sample) else { return false }
        let category = AppUsageEntry.classify(
            bundleIdentifier: sample.bundleIdentifier,
            appName: sample.appName,
            browserHost: host(of: sample)
        )
        if category == .distracting { return true }
        let text = [sample.bundleIdentifier, sample.appName, host(of: sample) ?? ""].joined(separator: " ").lowercased()
        return extraDerailerNeedles.contains { text.contains($0) }
    }

    /// Display name, merging a site and its app ("youtube.com" and the YouTube app → "YouTube").
    static func displayName(of sample: UsageSample) -> String {
        let name = sample.appName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let host = host(of: sample) {
            let known = AppUsageEntry.domainDisplayName(for: host)
            return known != host || name.isEmpty ? known : name
        }
        if !name.isEmpty { return name }
        return AppUsageEntry.recommendationDisplayLabel(for: "app:\(sample.bundleIdentifier)")
    }
}

/// What a "Distraction" or "It's work" click on a derailer row writes a rule for: the site's host,
/// or the app's bundle id (the one with the most time when a site and its app share a name).
struct DerailerTarget: Hashable, Sendable {
    enum Kind: String, Hashable, Sendable { case app, website }
    let kind: Kind
    /// Lowercased bundle id or host, as `IdleDistractionItem.key` stores it.
    let key: String

    init(kind: Kind, key: String) {
        self.kind = kind
        self.key = key.lowercased()
    }

    init(_ sample: UsageSample) {
        if let host = DerailerClassifier.host(of: sample) {
            self.init(kind: .website, key: host)
        } else {
            self.init(kind: .app, key: sample.bundleIdentifier)
        }
    }
}

extension FocusAnalytics {
    struct Derailer: Hashable, Sendable, Identifiable {
        let name: String
        /// Time in the period shown (this week, or the Insights range).
        let thisWeekSeconds: Int
        /// Time in the period before it, of the same length.
        let lastWeekSeconds: Int
        var target: DerailerTarget?
        /// The user already marked it a distraction (a confirmed rule matched).
        var isConfirmed = false
        var id: String { name.lowercased() }
        var deltaSeconds: Int { thisWeekSeconds - lastWeekSeconds }
    }

    struct DerailerTotal: Hashable, Sendable, Identifiable {
        let name: String
        let seconds: Int
        var target: DerailerTarget?
        var isConfirmed = false
        var id: String { name.lowercased() }
    }

    /// Outside-focus derailer time per name for usage rows whose day falls inside `interval`, largest first.
    func derailerTotals(
        _ usage: [UsageSample],
        in interval: DateInterval,
        confirmedKeys: Set<String> = [],
        allowedKeys: Set<String> = [],
        minimumSeconds: Int = 0
    ) -> [DerailerTotal] {
        struct Bucket {
            var name: String
            var seconds = 0
            var confirmed = false
            var targetSeconds: [DerailerTarget: Int] = [:]
        }
        var totals: [String: Bucket] = [:]
        for sample in usage where sample.outsideFocusSeconds > 0 && interval.contains(sample.day) {
            guard DerailerClassifier.isDerailer(sample, confirmedKeys: confirmedKeys, allowedKeys: allowedKeys) else { continue }
            let name = DerailerClassifier.displayName(of: sample)
            let key = name.lowercased()
            totals[key, default: Bucket(name: name)].seconds += sample.outsideFocusSeconds
            totals[key]?.targetSeconds[DerailerTarget(sample), default: 0] += sample.outsideFocusSeconds
            if DerailerClassifier.matches(sample, keys: confirmedKeys) { totals[key]?.confirmed = true }
        }
        return totals.values
            .filter { $0.seconds >= minimumSeconds && $0.seconds > 0 }
            .map { bucket in
                let target = bucket.targetSeconds.max { lhs, rhs in
                    lhs.value == rhs.value ? lhs.key.key > rhs.key.key : lhs.value < rhs.value
                }?.key
                return DerailerTotal(name: bucket.name, seconds: bucket.seconds, target: target, isConfirmed: bucket.confirmed)
            }
            .sorted { (lhs: DerailerTotal, rhs: DerailerTotal) -> Bool in
                lhs.seconds == rhs.seconds ? lhs.name < rhs.name : lhs.seconds > rhs.seconds
            }
    }

    /// This calendar week vs last calendar week, sorted by this week's time.
    func derailers(
        _ usage: [UsageSample],
        now: Date,
        confirmedKeys: Set<String> = [],
        allowedKeys: Set<String> = [],
        limit: Int = 6
    ) -> [Derailer] {
        let thisWeek = weekInterval(containing: now)
        let lastWeekStart = calendar.date(byAdding: .weekOfYear, value: -1, to: thisWeek.start) ?? thisWeek.start
        let lastWeek = weekInterval(containing: lastWeekStart)
        return derailers(usage, current: thisWeek, previous: lastWeek, confirmedKeys: confirmedKeys, allowedKeys: allowedKeys, limit: limit)
    }

    /// The last `days` days (today included) against the `days` before them (Insights' range).
    func derailers(
        _ usage: [UsageSample],
        lastDays days: Int,
        now: Date,
        confirmedKeys: Set<String> = [],
        allowedKeys: Set<String> = [],
        limit: Int = 6
    ) -> [Derailer] {
        let today = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: today) ?? now
        let start = calendar.date(byAdding: .day, value: -(max(1, days) - 1), to: today) ?? today
        let previousStart = calendar.date(byAdding: .day, value: -max(1, days), to: start) ?? start
        return derailers(
            usage,
            current: DateInterval(start: start, end: end),
            previous: DateInterval(start: previousStart, end: start),
            confirmedKeys: confirmedKeys, allowedKeys: allowedKeys, limit: limit
        )
    }

    /// `current` against `previous`, sorted by the current period's time.
    func derailers(
        _ usage: [UsageSample],
        current currentInterval: DateInterval,
        previous previousInterval: DateInterval,
        confirmedKeys: Set<String> = [],
        allowedKeys: Set<String> = [],
        limit: Int = 6
    ) -> [Derailer] {
        let current = derailerTotals(usage, in: currentInterval, confirmedKeys: confirmedKeys, allowedKeys: allowedKeys)
        let previous = derailerTotals(usage, in: previousInterval, confirmedKeys: confirmedKeys, allowedKeys: allowedKeys)
        var names: [String: String] = [:]
        for total in current + previous where names[total.id] == nil { names[total.id] = total.name }
        let currentByID = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
        let previousByID = Dictionary(uniqueKeysWithValues: previous.map { ($0.id, $0) })
        return Array(
            names
                .map { id, name in
                    let now = currentByID[id]
                    let before = previousByID[id]
                    return Derailer(
                        name: name,
                        thisWeekSeconds: now?.seconds ?? 0,
                        lastWeekSeconds: before?.seconds ?? 0,
                        target: now?.target ?? before?.target,
                        isConfirmed: (now?.isConfirmed ?? false) || (before?.isConfirmed ?? false)
                    )
                }
                .sorted {
                    if $0.thisWeekSeconds != $1.thisWeekSeconds { return $0.thisWeekSeconds > $1.thisWeekSeconds }
                    if $0.lastWeekSeconds != $1.lastWeekSeconds { return $0.lastWeekSeconds > $1.lastWeekSeconds }
                    return $0.name < $1.name
                }
                .prefix(max(0, limit))
        )
    }
}
