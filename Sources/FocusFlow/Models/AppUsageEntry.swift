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

    static func classify(bundleIdentifier: String, appName: String) -> AppCategory {
        let id = bundleIdentifier.lowercased()
        let name = appName.lowercased()

        // High-confidence distracting aliases from app title first (browser tabs/window titles).
        if name.contains("youtube") || name.contains("twitter") || name.contains("x.com") ||
           name.contains("reddit") || name.contains("instagram") || name.contains("tiktok") ||
           name.contains("facebook") || name.contains("netflix") || name.contains("spotify") {
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

    /// Converts a persisted recommendation target/context key into user-facing text.
    /// Example: `app:com.openai.chatgpt` -> `com.openai.chatgpt`.
    static func recommendationDisplayLabel(for targetOrContextKey: String) -> String {
        let trimmed = targetOrContextKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("app:") else { return trimmed }
        return String(trimmed.dropFirst(4))
    }
}
