import Foundation
import SwiftUI

struct FFBuildInfo: Equatable {
    let shortGitSHA: String
    let timestampUTC: String

    init(bundleInfo: [String: Any]? = Bundle.main.infoDictionary) {
        let info = bundleInfo ?? [:]
        let sha = (info["FFBuildSHA"] as? String)
            ?? (info["CFBundleVersion"] as? String)
            ?? "unknown"
        let timestamp = (info["FFBuildTimestampUTC"] as? String) ?? "unknown"

        self.shortGitSHA = sha
        self.timestampUTC = timestamp
    }

    var displayString: String {
        "\(shortGitSHA) · \(timestampUTC)"
    }
}

private struct FFBuildInfoKey: EnvironmentKey {
    static let defaultValue = FFBuildInfo()
}

extension EnvironmentValues {
    var ffBuildInfo: FFBuildInfo {
        get { self[FFBuildInfoKey.self] }
        set { self[FFBuildInfoKey.self] = newValue }
    }
}
