import Foundation

enum InstalledAppCatalog {
    static func loadInstalledApps() async -> [(name: String, bundleID: String)] {
        let searchDirectories = applicationDirectories()
        return await Task.detached(priority: .userInitiated) {
            installedApps(in: searchDirectories)
        }.value
    }

    static func applicationDirectories(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [URL] {
        let standardDirectories = FileManager.default.urls(for: .applicationDirectory, in: .allDomainsMask)
        let fallbackUserApplications = homeDirectory.appendingPathComponent("Applications", isDirectory: true)
        var seenPaths = Set<String>()

        return (standardDirectories + [fallbackUserApplications]).filter { directory in
            seenPaths.insert(directory.standardizedFileURL.path).inserted
        }
    }

    static func installedApps(in searchDirectories: [URL]) -> [(name: String, bundleID: String)] {
        var appsByBundleID: [String: (name: String, bundleID: String)] = [:]

        for dir in searchDirectories {
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for url in contents where url.pathExtension == "app" {
                guard let bundle = Bundle(url: url),
                      let bundleID = bundle.bundleIdentifier else { continue }
                let name = (bundle.infoDictionary?["CFBundleDisplayName"] as? String)
                    ?? (bundle.infoDictionary?["CFBundleName"] as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                appsByBundleID[bundleID] = (name, bundleID)
            }
        }

        return appsByBundleID.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}
