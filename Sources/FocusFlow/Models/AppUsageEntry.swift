import Foundation
import SwiftData

/// Tracks time spent in individual applications during focus sessions and idle periods.
@Model
final class AppUsageEntry {
    var date: Date
    var appName: String
    var bundleIdentifier: String
    var duringFocusSeconds: Int
    var outsideFocusSeconds: Int

    init(
        date: Date = Calendar.current.startOfDay(for: Date()),
        appName: String = "",
        bundleIdentifier: String = "",
        duringFocusSeconds: Int = 0,
        outsideFocusSeconds: Int = 0
    ) {
        self.date = date
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.duringFocusSeconds = duringFocusSeconds
        self.outsideFocusSeconds = outsideFocusSeconds
    }

    var totalSeconds: Int { duringFocusSeconds + outsideFocusSeconds }

    var focusRatio: Double {
        guard totalSeconds > 0 else { return 0 }
        return Double(duringFocusSeconds) / Double(totalSeconds)
    }

    /// Categorizes apps into productive, neutral, or distracting
    var category: AppCategory {
        Self.classify(bundleIdentifier: bundleIdentifier, appName: appName)
    }

    enum AppCategory: String, Codable {
        case productive
        case neutral
        case distracting

        var label: String {
            switch self {
            case .productive: "Productive"
            case .neutral: "Neutral"
            case .distracting: "Distracting"
            }
        }
    }

    /// Context-aware classification for use during focus sessions.
    /// Browsers and AI/chat tools are treated as distracting during focus; terminals/editors stay neutral.
    func classifyForContext(isInFocusSession: Bool, projectWorkMode: WorkMode?) -> AppCategory {
        guard isInFocusSession else {
            return Self.classify(bundleIdentifier: bundleIdentifier, appName: appName)
        }
        let id = bundleIdentifier.lowercased()
        let name = appName.lowercased()

        // AI/chat tools → distracting during focus
        if id.contains("anthropic") || id.contains("openai") || id.contains("slack") ||
           id.contains("discord") || id.contains("telegram") || id.contains("whatsapp") ||
           name.contains("claude") || name.contains("chatgpt") || name.contains("copilot") ||
           name.contains("slack") || name.contains("discord") {
            return .distracting
        }

        // Browsers → distracting during focus
        if id.contains("safari") || id.contains("chrome") || id.contains("firefox") ||
           id.contains("brave") || id.contains("arc") || id.contains("edge") ||
           id.contains("opera") || id.contains("orion") {
            return .distracting
        }

        // Terminals/editors → neutral during focus (working, just in a different tool)
        if id.contains("terminal") || id.contains("iterm") || id.contains("warp") ||
           id.contains("ghostty") || id.contains("xcode") || id.contains("vscode") || id.contains("cursor") ||
           id.contains("jetbrains") || id.contains("sublime") ||
            name.contains("terminal") || name.contains("code") {
            return .neutral
        }

        return Self.classify(bundleIdentifier: bundleIdentifier, appName: appName)
    }

    static func classify(
        bundleIdentifier: String,
        appName: String,
        windowTitle: String? = nil,
        browserHost: String? = nil
    ) -> AppCategory {
        let id = bundleIdentifier.lowercased()
        let name = appName.lowercased()
        let title = (windowTitle ?? "").lowercased()
        let host = browserHost?.lowercased()
        let textSignals = [name, title].joined(separator: " ")

        if let host {
            let distractingDomains = [
                "youtube.com", "twitter.com", "x.com", "reddit.com",
                "instagram.com", "tiktok.com", "facebook.com",
                "netflix.com", "twitch.tv", "spotify.com"
            ]
            if distractingDomains.contains(where: { host.contains($0) }) {
                return .distracting
            }
        }

        // High-confidence distracting aliases from app title first (browser tabs/window titles).
        if textSignals.contains("youtube") || textSignals.contains("twitter") || textSignals.contains("x.com") ||
           textSignals.contains("reddit") || textSignals.contains("instagram") || textSignals.contains("tiktok") ||
           textSignals.contains("facebook") || textSignals.contains("netflix") || textSignals.contains("spotify") {
            return .distracting
        }

        // Development tools
        if id.contains("xcode") || id.contains("vscode") || id.contains("visual-studio") ||
           id.contains("jetbrains") || id.contains("sublime") || id.contains("atom") ||
           id.contains("terminal") || id.contains("iterm") || id.contains("warp") ||
           id.contains("ghostty") ||
           id.contains("cursor") || id.contains("nova") || id.contains("bbedit") ||
           name.contains("terminal") || name.contains("code") || name.contains("editor") {
            return .productive
        }

        // Productivity tools
        if id.contains("pages") || id.contains("numbers") || id.contains("keynote") ||
           id.contains("microsoft") || id.contains("notion") || id.contains("obsidian") ||
           id.contains("figma") || id.contains("sketch") || id.contains("affinity") ||
           id.contains("photoshop") || id.contains("illustrator") || id.contains("logic") ||
           id.contains("finalcut") || id.contains("davinci") {
            return .productive
        }

        // Communication (neutral — could be work or personal)
        if id.contains("slack") || id.contains("teams") || id.contains("discord") ||
           id.contains("zoom") || id.contains("mail") || id.contains("messages") ||
           id.contains("telegram") || id.contains("whatsapp") {
            return .neutral
        }

        // Entertainment / social media
        if id.contains("music") || id.contains("spotify") || id.contains("netflix") ||
           id.contains("youtube") || id.contains("twitter") || id.contains("reddit") ||
           id.contains("instagram") || id.contains("tiktok") || id.contains("facebook") ||
           id.contains("game") || id.contains("steam") {
            return .distracting
        }

        // Browsers — neutral (could be either)
        if id.contains("safari") || id.contains("chrome") || id.contains("firefox") ||
           id.contains("brave") || id.contains("arc") || id.contains("edge") ||
           id.contains("opera") || id.contains("orion") {
            return .neutral
        }

        // System utilities — neutral
        if id.contains("apple.") || id.contains("finder") || id.contains("systempreferences") ||
           id.contains("activity-monitor") || id.contains("preview") {
            return .neutral
        }

        return .neutral
    }

    /// Derives a likely block target from app metadata.
    /// Returns website domains for browser/social contexts when confidence is high.
    static func recommendedBlockTarget(bundleIdentifier: String, appName: String) -> String? {
        let id = bundleIdentifier.lowercased()
        let name = appName.lowercased()

        let mapping: [(needle: String, target: String)] = [
            ("youtube", "youtube.com"),
            ("reddit", "reddit.com"),
            ("x.com", "x.com"),
            ("twitter", "x.com"),
            ("instagram", "instagram.com"),
            ("facebook", "facebook.com"),
            ("tiktok", "tiktok.com"),
            ("netflix", "netflix.com"),
            ("twitch", "twitch.tv"),
            ("spotify", "spotify.com")
        ]

        if let hit = mapping.first(where: { name.contains($0.needle) || id.contains($0.needle) }) {
            return hit.target
        }

        // Non-web derailer fallback for repeat candidates.
        let derailerNeedles = [
            "anthropic", "claude",
            "openai", "chatgpt",
            "slack", "discord",
            "telegram", "whatsapp"
        ]
        let browserNeedles = [
            "safari", "chrome", "firefox",
            "brave", "arc", "edge",
            "opera", "orion"
        ]
        if !bundleIdentifier.isEmpty,
           !browserNeedles.contains(where: { id.contains($0) }),
           derailerNeedles.contains(where: { id.contains($0) || name.contains($0) }) {
            return "app:\(id)"
        }
        return nil
    }

    /// Converts persisted context keys into display-safe labels for prompts and insights.
    /// Never returns raw URLs, paths, or package identifiers.
    static func recommendationDisplayLabel(for targetOrContextKey: String) -> String {
        let trimmed = targetOrContextKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "This context" }

        let lowered = trimmed.lowercased()
        if lowered.hasPrefix("app:") {
            return appDisplayName(forBundleId: String(lowered.dropFirst(4)))
        }

        if let host = hostFromURLOrDomain(trimmed) {
            return domainDisplayName(for: host)
        }

        if looksLikeBundleIdentifier(trimmed) {
            return appDisplayName(forBundleId: lowered)
        }

        if trimmed.contains("/") {
            let tail = trimmed
                .split(separator: "/")
                .last
                .map(String.init) ?? trimmed
            let safeTail = prettifyToken(tail)
            return safeTail.isEmpty ? "This context" : safeTail
        }

        let pretty = prettifyToken(trimmed)
        return pretty.isEmpty ? "This context" : pretty
    }

    static func appBundleID(fromRecommendationTarget target: String) -> String? {
        let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("app:") else { return nil }
        let bundleId = String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return bundleId.isEmpty ? nil : bundleId
    }

    private static func appDisplayName(forBundleId bundleId: String) -> String {
        let knownNames: [String: String] = [
            "com.anthropic.claudefordesktop": "Claude",
            "com.tinyspeck.slackmacgap": "Slack",
            "com.openai.chatgpt": "ChatGPT",
            "com.openai.codex": "Codex",
            "com.mitchellh.ghostty": "Ghostty",
            "com.apple.safari": "Safari",
            "com.google.chrome": "Chrome",
            "com.brave.browser": "Brave",
            "company.thebrowser.browser": "Arc",
            "org.mozilla.firefox": "Firefox",
            "com.microsoft.edgemac": "Edge"
        ]
        if let known = knownNames[bundleId] { return known }

        if bundleId.contains("claude") { return "Claude" }
        if bundleId.contains("slack") { return "Slack" }
        if bundleId.contains("chatgpt") { return "ChatGPT" }
        if bundleId.contains("codex") { return "Codex" }
        if bundleId.contains("ghostty") { return "Ghostty" }
        if bundleId.contains("safari") { return "Safari" }
        if bundleId.contains("chrome") { return "Chrome" }
        if bundleId.contains("brave") { return "Brave" }
        if bundleId.contains("firefox") { return "Firefox" }
        if bundleId.contains("edge") { return "Edge" }

        let lastToken = bundleId.split(separator: ".").last.map(String.init) ?? bundleId
        let cleaned = prettifyToken(lastToken)
        return cleaned.isEmpty ? "This app" : cleaned
    }

    private static func hostFromURLOrDomain(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), let host = url.host {
            return host.lowercased().replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression)
        }
        if trimmed.contains("://"), let components = URLComponents(string: trimmed), let host = components.host {
            return host.lowercased().replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression)
        }
        let lower = trimmed.lowercased()
        if !lower.contains(" "), lower.contains("."), !lower.contains("/") {
            return lower.replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression)
        }
        return nil
    }

    private static func domainDisplayName(for host: String) -> String {
        let knownDomains: [String: String] = [
            "youtube.com": "YouTube",
            "reddit.com": "Reddit",
            "x.com": "X",
            "twitter.com": "X",
            "instagram.com": "Instagram",
            "facebook.com": "Facebook",
            "tiktok.com": "TikTok",
            "netflix.com": "Netflix",
            "twitch.tv": "Twitch",
            "spotify.com": "Spotify",
            "github.com": "GitHub",
            "stackoverflow.com": "Stack Overflow",
            "linkedin.com": "LinkedIn"
        ]
        if let known = knownDomains.first(where: { host.hasSuffix($0.key) })?.value {
            return known
        }
        return host
    }

    private static func looksLikeBundleIdentifier(_ value: String) -> Bool {
        let lowered = value.lowercased()
        guard !lowered.contains(" "), lowered.contains("."), !lowered.contains("/") else { return false }
        return lowered.split(separator: ".").count >= 3
    }

    private static func prettifyToken(_ value: String) -> String {
        value
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }
}
