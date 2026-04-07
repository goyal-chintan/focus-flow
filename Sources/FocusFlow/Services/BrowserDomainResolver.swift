import Foundation

struct BrowserDomainResolution: Equatable {
    let host: String
    let displayLabel: String
}

struct BrowserDomainResolver {
    typealias AppleScriptRunner = (String) -> String?

    static let recoverySupportedBrowserList = "Safari, Chrome, Arc, Edge, Brave, or Opera"

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
        if normalizedBundleIdentifier == "com.apple.safari" {
            return true
        }
        return chromiumApplicationName(for: normalizedBundleIdentifier) != nil
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

        if normalizedBundleIdentifier == "com.apple.safari" {
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

        guard let applicationName = chromiumApplicationName(for: normalizedBundleIdentifier) else {
            return []
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
            tell application "\(applicationName)"
                if (count of windows) is 0 then return ""
                return URL of active tab of front window
            end tell
            """,
            """
            tell application "\(applicationName)"
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
        switch bundleIdentifier {
        case "com.google.chrome":
            return "Google Chrome"
        case "com.google.chrome.canary":
            return "Google Chrome Canary"
        case "company.thebrowser.browser":
            return "Arc"
        case "com.brave.browser":
            return "Brave Browser"
        case "com.microsoft.edgemac":
            return "Microsoft Edge"
        case "com.operasoftware.opera":
            return "Opera"
        default:
            return nil
        }
    }

    private static func executeAppleScript(_ source: String) -> String? {
        let script = NSAppleScript(source: source)
        var error: NSDictionary?
        let result = script?.executeAndReturnError(&error)
        guard error == nil else { return nil }
        return result?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
