import Foundation

// Coach v8 phase 2 (docs/plans/2026-11-06-coach-v8-life-coach.md §3.3): an app is a tool or a
// pull *for a goal*, not in general. Slack is the Office goal and competes with Learning (goal
// shielding: Shah, Friedman & Kruglanski, 2002). Your rules always win; then what your blocks
// show; then editable defaults. Pure; `TimerViewModel` builds the book from the store.

enum AppRole: String, Codable, CaseIterable, Sendable {
    case tool, pull, neutral

    var title: String {
        switch self {
        case .tool: "Tool"
        case .pull: "Pull"
        case .neutral: "Neutral"
        }
    }
}

/// Where you are when an app is used.
enum AppContext: Hashable, Sendable {
    /// In a block on this project.
    case project(UUID, AreaGroup)
    /// Outside a block: office hours on a workday.
    case work
    /// Outside a block: an own-work window, or a block with no project (a starter).
    case own
    /// Everything else: evenings, weekends, leave.
    case free

    var area: AreaGroup? {
        switch self {
        case .project(_, let area): area
        case .work: .work
        case .own: .own
        case .free: nil
        }
    }

    var projectID: UUID? {
        if case .project(let id, _) = self { return id }
        return nil
    }

    /// Outside a block (phase 2: office hours 09:00–19:00 on a workday, minus own-work windows).
    static func outsideBlock(dayType: DayType, hour: Int, inOwnWindow: Bool) -> AppContext {
        if inOwnWindow { return .own }
        if dayType == .workday, (9..<19).contains(hour) { return .work }
        return .free
    }
}

/// Work vs own work, the two sides of the boundary (Kreiner, Hollensbe & Sheep, 2009).
enum AreaGroup: String, Codable, Hashable, Sendable {
    case work, own

    static func of(_ area: ProjectArea?) -> AreaGroup {
        area == .work ? .work : .own
    }
}

enum AppRoleScope: Hashable, Sendable {
    case everywhere
    case area(AreaGroup)
    case project(UUID)
}

enum AppRoleSource: String, Codable, Sendable {
    case user, learned, standard

    var title: String {
        switch self {
        case .user: "you"
        case .learned: "learned"
        case .standard: "default"
        }
    }
}

struct AppRoleRule: Equatable, Sendable {
    /// Lowercased bundle id or host (as `IdleDistractionItem.key` and `DerailerTarget.key`).
    let key: String
    let scope: AppRoleScope
    let role: AppRole
}

/// Evidence that an app belongs to a project's work: time inside that project's blocks.
struct AppRoleEvidence: Equatable, Sendable {
    var minutes: Double = 0
    var days: Set<Date> = []
    /// You kept it during a block review ("planned"), from the older per-project memory.
    var plannedMarks: Int = 0

    static let minMinutes = 60.0
    static let minDays = 3

    var isEnough: Bool { plannedMarks >= 2 || (minutes >= Self.minMinutes && days.count >= Self.minDays) }

    var caption: String {
        let hours = Int(minutes) / 60, mins = Int(minutes) % 60
        let time = hours > 0 ? "\(hours)h \(mins)m" : "\(mins)m"
        return "\(time) in its blocks on \(days.count) day\(days.count == 1 ? "" : "s")"
    }
}

struct AppRoleDecision: Equatable, Sendable {
    let role: AppRole
    let source: AppRoleSource
    let reason: String
}

struct AppRoleBook: Sendable {
    var rules: [AppRoleRule] = []
    /// key → project → evidence.
    var evidence: [String: [UUID: AppRoleEvidence]] = [:]

    /// Office tools: work for the Work area, a pull during own work, neutral in free time.
    static let officeNeedles = ["slack", "zoom", "teams", "webex", "meet.google", "atlassian", "jira", "confluence",
                                "outlook", "mail.google", "calendar.google"]

    static func isOffice(_ key: String, name: String = "") -> Bool {
        let text = (key + " " + name).lowercased()
        return officeNeedles.contains { text.contains($0) }
    }

    /// The role of `key` (with its display `name`) in `context`.
    func role(key rawKey: String, name: String = "", in context: AppContext) -> AppRoleDecision {
        let key = Self.normalize(rawKey)
        let matching = rules.filter { Self.matches(key, ruleKey: $0.key) }
        if let id = context.projectID, let rule = matching.first(where: { $0.scope == .project(id) }) {
            return AppRoleDecision(role: rule.role, source: .user, reason: "You set it for this project.")
        }
        if let area = context.area, let rule = matching.first(where: { $0.scope == .area(area) }) {
            return AppRoleDecision(role: rule.role, source: .user, reason: area == .work ? "You set it for work." : "You set it for own work.")
        }
        if let rule = matching.first(where: { $0.scope == .everywhere }) {
            return AppRoleDecision(role: rule.role, source: .user, reason: "You set it everywhere.")
        }
        if let id = context.projectID, !Self.isBrowser(key), let found = evidence.first(where: { Self.matches(key, ruleKey: $0.key) })?.value[id],
           found.isEnough, Self.standardRole(key: key, name: name, in: context) != .pull {
            return AppRoleDecision(role: .tool, source: .learned, reason: found.caption)
        }
        let role = Self.standardRole(key: key, name: name, in: context)
        let reason: String
        switch role {
        case .pull where Self.isOffice(key, name: name): reason = "Office tools pull you off own work."
        case .pull: reason = "Streaming and social sites."
        case .tool: reason = "An office tool, at work."
        case .neutral: reason = "Neither, until you or your blocks say."
        }
        return AppRoleDecision(role: role, source: .standard, reason: reason)
    }

    /// The editable defaults (the old global "work tool" list, now per context).
    static func standardRole(key: String, name: String, in context: AppContext) -> AppRole {
        if isOffice(key, name: name) {
            switch context.area {
            case .work: return .tool
            case .own: return .pull
            case nil: return .neutral
            }
        }
        let sample = UsageSample(day: .distantPast, appName: name.isEmpty ? key : name,
                                 bundleIdentifier: key.contains(".") && !key.contains("/") && isHost(key) ? "domain:\(key)" : key,
                                 outsideFocusSeconds: 1)
        if DerailerClassifier.isWorkTool(sample) { return .neutral }
        let category = AppUsageEntry.classify(bundleIdentifier: sample.bundleIdentifier, appName: sample.appName, browserHost: DerailerClassifier.host(of: sample))
        if category == .distracting { return .pull }
        let text = (key + " " + name).lowercased()
        if DerailerClassifier.extraDerailerNeedles.contains(where: { text.contains($0) }) { return .pull }
        return .neutral
    }

    /// Browsers hold sites; the site has the role, never the browser (it is not learned or listed).
    static let browserNeedles = ["company.thebrowser", "com.google.chrome", "com.apple.safari", "org.mozilla.firefox",
                                 "com.brave.browser", "com.microsoft.edgemac", "com.operasoftware", "com.vivaldi", "app.zen-browser"]

    static func isBrowser(_ key: String) -> Bool {
        let lower = key.lowercased()
        return browserNeedles.contains { lower.hasPrefix($0) }
    }

    /// "domain:youtube.com" → "youtube.com"; bundle ids stay as they are, lowercased.
    static func normalize(_ key: String) -> String {
        let lower = key.lowercased()
        return lower.hasPrefix("domain:") ? String(lower.dropFirst("domain:".count)) : (lower.hasPrefix("app:") ? String(lower.dropFirst(4)) : lower)
    }

    /// A host matches its rule's host and subdomains; a bundle id matches exactly.
    static func matches(_ key: String, ruleKey: String) -> Bool {
        key == ruleKey || (isHost(ruleKey) && key.hasSuffix("." + ruleKey))
    }

    /// Hosts have a dot and a TLD-like ending; bundle ids start with a reverse domain ("com.").
    static func isHost(_ key: String) -> Bool {
        let first = key.split(separator: ".").first.map(String.init) ?? ""
        return key.contains(".") && !["com", "org", "net", "io", "us", "md", "company", "app", "dev", "co"].contains(first)
    }
}

/// Which app is open in an own-work project's blocks that the defaults call a pull (or an office
/// tool), so the coach asks: part of the work, or a pull?
enum AppRoleQuestionPicker {
    static let minMinutes = 15.0

    struct Candidate: Equatable, Sendable {
        let key: String
        let name: String
        let projectID: UUID
        let minutes: Double
        let days: Int
    }

    static func pick(evidence: [String: [UUID: AppRoleEvidence]], names: [String: String], ownProjects: Set<UUID>, book: AppRoleBook) -> Candidate? {
        var best: Candidate?
        for (key, byProject) in evidence {
            for (projectID, found) in byProject where ownProjects.contains(projectID) && found.minutes >= minMinutes {
                let name = names[key] ?? key
                let decision = book.role(key: key, name: name, in: .project(projectID, .own))
                guard decision.source == .standard, decision.role == .pull else { continue }
                let candidate = Candidate(key: key, name: name, projectID: projectID, minutes: found.minutes, days: found.days.count)
                if best.map({ candidate.minutes > $0.minutes }) ?? true { best = candidate }
            }
        }
        return best
    }
}
