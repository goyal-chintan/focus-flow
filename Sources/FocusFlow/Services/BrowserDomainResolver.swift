import Foundation

struct BrowserAutomationTarget: Equatable {
    let bundleIdentifier: String
    let displayName: String
    let scriptingName: String
    let usesSafariTabsAPI: Bool
}

struct BrowserDomainResolution: Equatable {
    let host: String
    let displayLabel: String
}

struct BrowserDomainResolver {
    typealias AppleScriptRunner = (String) -> String?

    static let supportedAutomationTargets: [BrowserAutomationTarget] = [
        BrowserAutomationTarget(
            bundleIdentifier: "com.apple.safari",
            displayName: "Safari",
            scriptingName: "Safari",
            usesSafariTabsAPI: true
        ),
        BrowserAutomationTarget(
            bundleIdentifier: "com.google.chrome",
            displayName: "Chrome",
            scriptingName: "Google Chrome",
            usesSafariTabsAPI: false
        ),
        BrowserAutomationTarget(
            bundleIdentifier: "company.thebrowser.browser",
            displayName: "Arc",
            scriptingName: "Arc",
            usesSafariTabsAPI: false
        ),
        BrowserAutomationTarget(
            bundleIdentifier: "com.microsoft.edgemac",
            displayName: "Edge",
            scriptingName: "Microsoft Edge",
            usesSafariTabsAPI: false
        ),
        BrowserAutomationTarget(
            bundleIdentifier: "com.brave.browser",
            displayName: "Brave",
            scriptingName: "Brave Browser",
            usesSafariTabsAPI: false
        ),
        BrowserAutomationTarget(
            bundleIdentifier: "com.operasoftware.opera",
            displayName: "Opera",
            scriptingName: "Opera",
            usesSafariTabsAPI: false
        ),
        BrowserAutomationTarget(
            bundleIdentifier: "com.google.chrome.canary",
            displayName: "Chrome Canary",
            scriptingName: "Google Chrome Canary",
            usesSafariTabsAPI: false
        )
    ]

    static let recoverySupportedBrowserList = supportedAutomationTargets
        .filter { $0.bundleIdentifier != "com.google.chrome.canary" }
        .map(\.displayName)
        .joined(separator: ", ")

    private let runAppleScript: AppleScriptRunner

    init(runAppleScript: @escaping AppleScriptRunner = BrowserDomainResolver.executeAppleScript) {
        self.runAppleScript = runAppleScript
    }

    func resolve(bundleIdentifier: String, windowTitle: String, appName: String) -> BrowserDomainResolution? {
        for script in appleScriptSources(for: bundleIdentifier) {
            if let resolution = normalizeResolution(from: runAppleScript(script)) {
                return resolution
            }
        }

        return fallbackResolution(windowTitle: windowTitle, appName: appName)
    }

    static func supports(bundleIdentifier: String?) -> Bool {
        guard let normalizedBundleIdentifier = bundleIdentifier?.lowercased() else { return false }
        return supportedAutomationTargets.contains { $0.bundleIdentifier == normalizedBundleIdentifier }
    }

    private func normalizeResolution(from rawValue: String?) -> BrowserDomainResolution? {
        guard let host = AppUsageEntry.normalizedBrowserHost(from: rawValue),
              let displayLabel = AppUsageEntry.browserDomainDisplayLabel(for: host) else {
            return nil
        }

        return BrowserDomainResolution(host: host, displayLabel: displayLabel)
    }

    private func fallbackResolution(windowTitle: String, appName: String) -> BrowserDomainResolution? {
        let text = "\(windowTitle) \(appName)".trimmingCharacters(in: .whitespacesAndNewlines)
        let loweredText = text.lowercased()

        let patterns = [
            #"https?://[^\s]+"#,
            #"(?:www\.)?(?:[a-z0-9-]+\.)+[a-z]{2,}"#
        ]

        for pattern in patterns {
            if let range = loweredText.range(of: pattern, options: .regularExpression),
               let resolution = normalizeResolution(from: String(loweredText[range])) {
                return resolution
            }
        }

        let knownDomains: [(needle: String, domain: String)] = [
            ("youtube", "youtube.com"),
            ("reddit", "reddit.com"),
            ("twitter", "twitter.com"),
            ("x.com", "x.com"),
            ("instagram", "instagram.com"),
            ("facebook", "facebook.com"),
            ("tiktok", "tiktok.com"),
            ("netflix", "netflix.com"),
            ("spotify", "spotify.com"),
            ("github", "github.com"),
            ("stackoverflow", "stackoverflow.com"),
            ("linkedin", "linkedin.com"),
            ("twitch", "twitch.tv")
        ]

        guard let domain = knownDomains.first(where: { loweredText.contains($0.needle) })?.domain else {
            return nil
        }
        return normalizeResolution(from: domain)
    }

    private func appleScriptSources(for bundleIdentifier: String) -> [String] {
        let normalizedBundleIdentifier = bundleIdentifier.lowercased()
        guard let target = Self.supportedAutomationTargets.first(where: { $0.bundleIdentifier == normalizedBundleIdentifier }) else {
            return []
        }

        if target.usesSafariTabsAPI {
            return [
                """
                tell application id "\(normalizedBundleIdentifier)"
                    if (count of windows) is 0 then return ""
                    return URL of current tab of front window
                end tell
                """,
                """
                tell application id "\(normalizedBundleIdentifier)"
                    if (count of windows) is 0 then return ""
                    return URL of current tab of window 1
                end tell
                """,
                """
                tell application "Safari"
                    if (count of windows) is 0 then return ""
                    return URL of current tab of front window
                end tell
                """,
                """
                tell application "Safari"
                    if (count of windows) is 0 then return ""
                    return URL of current tab of window 1
                end tell
                """
            ]
        }

        return [
            """
            tell application id "\(normalizedBundleIdentifier)"
                if (count of windows) is 0 then return ""
                return URL of active tab of front window
            end tell
            """,
            """
            tell application id "\(normalizedBundleIdentifier)"
                if (count of windows) is 0 then return ""
                return URL of active tab of window 1
            end tell
            """,
            """
            tell application "\(target.scriptingName)"
                if (count of windows) is 0 then return ""
                return URL of active tab of front window
            end tell
            """,
            """
            tell application "\(target.scriptingName)"
                if (count of windows) is 0 then return ""
                return URL of active tab of window 1
            end tell
            """
        ]
    }

    private func chromiumApplicationName(for bundleIdentifier: String) -> String? {
        Self.chromiumApplicationName(for: bundleIdentifier)
    }

    private static func chromiumApplicationName(for bundleIdentifier: String) -> String? {
        supportedAutomationTargets
            .first(where: { $0.bundleIdentifier == bundleIdentifier && !$0.usesSafariTabsAPI })?
            .scriptingName
    }

    private static func executeAppleScript(_ source: String) -> String? {
        let script = NSAppleScript(source: source)
        var error: NSDictionary?
        let result = script?.executeAndReturnError(&error)
        guard error == nil else { return nil }
        return result?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
