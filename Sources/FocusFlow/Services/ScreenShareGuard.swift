import AppKit
import Foundation

struct ScreenShareGuard {
    struct FrontmostApplication {
        let bundleIdentifier: String?
        let localizedName: String?
    }

    private let isScreenSharingProvider: () -> Bool
    private let frontmostApplicationProvider: () -> FrontmostApplication?

    /// Call apps. Not Slack: it is where people read and write all day, and treating it as a call
    /// kept the coach silent through ordinary work (34 min on 2026-10-28).
    private static let sensitiveBundleNeedles: [String] = [
        "us.zoom",
        "zoom",
        "microsoft.teams",
        "teams",
        "webex",
        "cisco.webex",
        "gotomeeting",
        "ringcentral",
        "whereby",
        "skype",
        "meet"
    ]

    private static let sensitiveNameNeedles: [String] = [
        "zoom",
        "teams",
        "webex",
        "google meet",
        "meet",
        "meeting",
        "conference",
        "huddle",
        "call"
    ]

    init(
        isScreenSharingProvider: @escaping () -> Bool = { ScreenCapture.isActive },
        frontmostApplicationProvider: @escaping () -> FrontmostApplication? = ScreenShareGuard.defaultFrontmostApplication
    ) {
        self.isScreenSharingProvider = isScreenSharingProvider
        self.frontmostApplicationProvider = frontmostApplicationProvider
    }

    /// Only a real screen capture holds the coach. Being in a call app is not sharing: the old
    /// frontmost-app guess ("teams", "meet", "call"…) silenced 58 coach decisions in 10 days
    /// (28 Oct–6 Nov 2026) while nothing was shared. The heuristic below stays for callers that
    /// only want to know "is this a meeting app".
    func shouldSuppressGuardianPopups(enabled: Bool) -> Bool {
        guard enabled else { return false }
        return isScreenSharingProvider()
    }

    static func shouldSuppressForFrontmostApplication(_ app: FrontmostApplication?) -> Bool {
        guard let app else { return false }
        return isLikelyScreenShareSensitiveContext(
            bundleIdentifier: app.bundleIdentifier,
            appName: app.localizedName
        )
    }

    static func isLikelyScreenShareSensitiveContext(bundleIdentifier: String?, appName: String?) -> Bool {
        let bundle = bundleIdentifier?.lowercased() ?? ""
        let name = appName?.lowercased() ?? ""
        return sensitiveBundleNeedles.contains(where: bundle.contains)
            || sensitiveNameNeedles.contains(where: name.contains)
    }

    private static func defaultFrontmostApplication() -> FrontmostApplication? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        return FrontmostApplication(
            bundleIdentifier: app.bundleIdentifier,
            localizedName: app.localizedName
        )
    }
}
