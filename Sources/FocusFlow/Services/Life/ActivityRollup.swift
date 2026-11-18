import Foundation

// Coach v8 §3.2: the hourly rollup. Pure accumulation here; `AppUsageTracker` feeds it each tick
// and flushes it into `ActivityHour` rows with its daily deltas.

struct ActivityRollup {
    static let retentionDays = 90
    /// No keyboard or mouse input for this long is "away", not the frontmost app's time.
    static let awayAfterIdleSeconds: TimeInterval = 5 * 60
    /// A tick gap beyond this (sleep, a stalled run loop) is away time, not app time.
    static let maxCreditedSecondsPerTick = 30

    struct Key: Hashable, Sendable {
        let hourStart: Date
        let key: String
        let projectID: UUID?
        let inBlock: Bool
    }

    struct Delta: Equatable, Sendable {
        var label: String
        var seconds: Int
        var switches: Int
    }

    private(set) var pending: [Key: Delta] = [:]
    private var lastKey: String?

    /// What this stretch of time was.
    enum Activity: Equatable, Sendable {
        case app(bundleID: String, name: String)
        case domain(host: String)
        case away
        case call

        var key: String {
            switch self {
            case .app(let id, _): "app:\(id)"
            case .domain(let host): "domain:\(host)"
            case .away: "away"
            case .call: "call"
            }
        }

        var label: String {
            switch self {
            case .app(_, let name): name
            case .domain(let host): host
            case .away: "Away"
            case .call: "Calls"
            }
        }
    }

    /// Priority: a call beats away (people sit still in calls), away beats the frontmost app, and
    /// a resolved domain replaces its browser.
    static func activity(frontmostBundleID: String?, frontmostName: String?, domain: String?,
                         idleSeconds: TimeInterval, inCall: Bool) -> Activity {
        if inCall { return .call }
        if idleSeconds >= awayAfterIdleSeconds { return .away }
        guard let id = frontmostBundleID, !id.isEmpty else { return .away }
        if let domain, !domain.isEmpty { return .domain(host: domain) }
        return .app(bundleID: id, name: frontmostName ?? id)
    }

    /// Adds `seconds` of `activity` at `now`. Seconds past `maxCreditedSecondsPerTick` go to away.
    /// A tick that straddles an hour boundary is split across both hours.
    mutating func record(_ activity: Activity, seconds: Int, now: Date, projectID: UUID?, inBlock: Bool, calendar: Calendar = .current) {
        guard seconds > 0 else { return }
        let credited = activity == .away ? seconds : min(seconds, Self.maxCreditedSecondsPerTick)
        let overflow = seconds - credited
        // A switch is moving from one app or site to another; leaving or returning to the desk, or
        // a call starting or ending, is not.
        let quiet: Set<String> = ["away", "call"]
        let switched = lastKey.map { !quiet.contains($0) && $0 != activity.key } ?? false && !quiet.contains(activity.key)
        lastKey = activity.key
        add(activity, seconds: credited, endingAt: now, projectID: projectID, inBlock: inBlock, switched: switched, calendar: calendar)
        if overflow > 0 {
            add(.away, seconds: overflow, endingAt: now.addingTimeInterval(-TimeInterval(credited)), projectID: projectID, inBlock: inBlock, switched: false, calendar: calendar)
        }
    }

    private mutating func add(_ activity: Activity, seconds: Int, endingAt end: Date, projectID: UUID?, inBlock: Bool, switched: Bool, calendar: Calendar) {
        var remaining = seconds
        var cursor = end
        var first = true
        while remaining > 0 {
            guard let hour = calendar.dateInterval(of: .hour, for: cursor.addingTimeInterval(-0.001)) else { return }
            let inThisHour = min(remaining, max(1, Int(cursor.timeIntervalSince(hour.start).rounded(.up))))
            let key = Key(hourStart: hour.start, key: activity.key, projectID: projectID, inBlock: inBlock)
            var delta = pending[key] ?? Delta(label: activity.label, seconds: 0, switches: 0)
            delta.seconds += inThisHour
            if first && switched { delta.switches += 1 }
            pending[key] = delta
            remaining -= inThisHour
            cursor = hour.start
            first = false
        }
    }

    mutating func drain() -> [Key: Delta] {
        defer { pending = [:] }
        return pending
    }
}

/// Coach v8 §3.2: are you in a call? The camera on is enough. The mic alone is not (dictation
/// apps use it): it needs a call app running or a meeting site frontmost.
enum CallRule {
    /// Not Slack: it is always running, so the mic for dictation would read as a call.
    static let callAppNeedles = ["zoom.us", "us.zoom", "microsoft.teams", "facetime", "webex", "gotomeeting", "whereby", "skype"]
    static let meetingHosts = ["meet.google.com", "zoom.us", "teams.microsoft.com", "whereby.com", "webex.com"]

    static func inCall(cameraInUse: Bool, micInUse: Bool, runningBundleIDs: [String], frontmostDomain: String?) -> Bool {
        if cameraInUse { return true }
        guard micInUse else { return false }
        if let host = frontmostDomain?.lowercased(), meetingHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) { return true }
        let running = runningBundleIDs.map { $0.lowercased() }
        return running.contains { id in callAppNeedles.contains { id.contains($0) } }
    }
}
