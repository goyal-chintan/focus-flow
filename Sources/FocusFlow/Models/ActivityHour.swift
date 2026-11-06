import Foundation
import SwiftData

/// Coach v8 §3.2: where an hour went. One row per (hour, key, project context, in a block).
/// `key` is `app:<bundle id>`, `domain:<host>` (replaces its browser's time, so nothing is counted
/// twice), `away` (no input for 5+ min, a locked screen, or sleep) or `call` (camera on, or the
/// mic in use with a call app open). Kept 90 days (`ActivityRollup.retentionDays`); the daily
/// `AppUsageEntry` rows stay as they were.
@Model
final class ActivityHour {
    var hourStart: Date
    var key: String
    var label: String
    /// The running block's project; nil outside a block or for a block with no project.
    var projectID: UUID?
    var inBlock: Bool
    var seconds: Int
    /// Switches *into* this key during the hour (app or domain changes).
    var switches: Int

    init(hourStart: Date, key: String, label: String, projectID: UUID?, inBlock: Bool, seconds: Int = 0, switches: Int = 0) {
        self.hourStart = hourStart
        self.key = key
        self.label = label
        self.projectID = projectID
        self.inBlock = inBlock
        self.seconds = seconds
        self.switches = switches
    }
}

/// Coach v8 §3.1: what kind of day it was, when the user said so or the calendar did. Inferred
/// days are not stored; they are recomputed from activity (`DayClassifier`).
@Model
final class DayLabel {
    var day: Date
    var typeRaw: String
    /// `user` or `calendar` (`DayTypeSource`).
    var sourceRaw: String
    var createdAt: Date

    init(day: Date, type: DayType, source: DayTypeSource, createdAt: Date = Date()) {
        self.day = day
        self.typeRaw = type.rawValue
        self.sourceRaw = source.rawValue
        self.createdAt = createdAt
    }

    var type: DayType { DayType(rawValue: typeRaw) ?? .workday }
    var source: DayTypeSource { DayTypeSource(rawValue: sourceRaw) ?? .user }
}
