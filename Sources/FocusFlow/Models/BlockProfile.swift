import Foundation
import SwiftData

@Model
final class BlockProfile {
    var id: UUID
    var name: String
    var blockedWebsitesRaw: String
    var blockedAppsRaw: String
    var mutedNotifAppsRaw: String
    var isDefault: Bool
    var createdAt: Date

    init(name: String, websites: [String] = [], apps: [String] = [], mutedApps: [String] = [], isDefault: Bool = false) {
        self.id = UUID()
        self.name = name
        self.blockedWebsitesRaw = websites.joined(separator: ",")
        self.blockedAppsRaw = apps.joined(separator: ",")
        self.mutedNotifAppsRaw = mutedApps.joined(separator: ",")
        self.isDefault = isDefault
        self.createdAt = Date()
    }

    var blockedWebsites: [String] {
        get { blockedWebsitesRaw.split(separator: ",").map(String.init).filter { !$0.isEmpty } }
        set { blockedWebsitesRaw = newValue.joined(separator: ",") }
    }

    var blockedApps: [String] {
        get { blockedAppsRaw.split(separator: ",").map(String.init).filter { !$0.isEmpty } }
        set { blockedAppsRaw = newValue.joined(separator: ",") }
    }

    var mutedNotificationApps: [String] {
        get { mutedNotifAppsRaw.split(separator: ",").map(String.init).filter { !$0.isEmpty } }
        set { mutedNotifAppsRaw = newValue.joined(separator: ",") }
    }
}
