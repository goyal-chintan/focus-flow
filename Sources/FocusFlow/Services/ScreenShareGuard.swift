import AppKit
import Foundation

struct ScreenShareGuard {
    struct FrontmostApplication {
        let bundleIdentifier: String?
        let localizedName: String?
    }

    private let isScreenSharingProvider: () -> Bool
    private let frontmostApplicationProvider: () -> FrontmostApplication?

    private static let sensitiveBundleNeedles: [String] = [
        "us.zoom",
        "zoom",
        "microsoft.teams",
        "teams",
        "webex",
        "cisco.webex",
        "slack",
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
        isScreenSharingProvider: @escaping () -> Bool = { false },
        frontmostApplicationProvider: @escaping () -> FrontmostApplication? = ScreenShareGuard.defaultFrontmostApplication
    ) {
        self.isScreenSharingProvider = isScreenSharingProvider
        self.frontmostApplicationProvider = frontmostApplicationProvider
    }

    func shouldSuppressGuardianPopups(enabled: Bool) -> Bool {
        guard enabled else { return false }
        if isScreenSharingProvider() {
            return true
        }
        guard let app = frontmostApplicationProvider() else { return false }
        return Self.shouldSuppressForFrontmostApplication(app)
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
