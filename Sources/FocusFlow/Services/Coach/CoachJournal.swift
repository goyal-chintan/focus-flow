import Foundation

/// Coach v4 §3.1: every coach decision, in plain words, in release builds too.
/// Before v4 the installed app logged nothing, so "why was the coach quiet?" had no answer.
///
/// Coach audit 2026-10-30: lines are structured. Each carries a reason code, and where there is
/// one the attempt id, the prompt probability and the hook shown, so a day can be counted
/// (`CoachLogSummary`) instead of read. Every exit of a decision path writes a line.
///
/// Stored as JSON lines in Application Support, trimmed to the newest `maxEntries`.
/// Insights shows the last days.
@MainActor
final class CoachJournal {
    struct Entry: Codable, Equatable, Sendable, Identifiable {
        enum Kind: String, Codable, Sendable {
            /// A prompt went on screen.
            case shown
            /// The coach chose not to prompt (and why).
            case quiet
            /// A block started; `text` says which prompt got the credit.
            case started
            /// The user declined, with or without a reason.
            case declined
            /// A prompt hid while nobody was at the desk.
            case unseen
            /// The user came back to the desk.
            case arrival
            /// Progress logged: a task ticked or a key result moved.
            case logged
        }

        let at: Date
        let kind: Kind
        let text: String
        /// Gate or exit reason. Nil on lines written before the audit.
        var code: Code?
        var attemptID: UUID?
        /// The prompt probability at a decision point (1 for a window's guaranteed prompt).
        var propensity: Double?
        /// The hook text the prompt showed.
        var hook: String?
        var id: String { "\(at.timeIntervalSince1970)-\(kind.rawValue)-\(text)" }

        init(at: Date, kind: Kind, text: String, code: Code? = nil, attemptID: UUID? = nil, propensity: Double? = nil, hook: String? = nil) {
            self.at = at
            self.kind = kind
            self.text = text
            self.code = code
            self.attemptID = attemptID
            self.propensity = propensity
            self.hook = hook
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            at = try c.decode(Date.self, forKey: .at)
            kind = try c.decode(Kind.self, forKey: .kind)
            text = try c.decode(String.self, forKey: .text)
            // An unknown code (a newer build's) reads as nil rather than dropping the line.
            code = (try? c.decodeIfPresent(String.self, forKey: .code)).flatMap { $0.flatMap(Code.init(rawValue:)) }
            attemptID = try c.decodeIfPresent(UUID.self, forKey: .attemptID)
            propensity = try c.decodeIfPresent(Double.self, forKey: .propensity)
            hook = try c.decodeIfPresent(String.self, forKey: .hook)
        }
    }

    /// Why a line was written. Raw values are what the file stores; keep them stable.
    enum Code: String, Codable, Sendable, CaseIterable {
        // Shown
        case prompted = "prompted"
        case guaranteed = "guaranteed"
        case forced = "forced"
        case startCard = "start_card"
        case plannedCue = "planned_cue"
        case counterOffer = "counter_offer"
        case rescue = "rescue"
        case pseudoCheck = "pseudo_check"
        case planTomorrow = "plan_tomorrow"
        case question = "question"
        case landing = "landing"
        case stretch = "stretch"
        case returnLadder = "return"
        case backAt = "back_at"
        // Held back
        case control = "control"
        case dailyCap = "daily_cap"
        case cooldown = "cooldown"
        case stickyPanel = "sticky_panel"
        case driftActive = "drift_active"
        case away = "away"
        case quietHours = "quiet_hours"
        case calendarBusy = "calendar_busy"
        case snoozed = "snoozed"
        case released = "released"
        case screenShare = "screen_share"
        case panelSpacing = "panel_spacing"
        case onTrack = "on_track"
        case outsideWindow = "outside_window"
        case outsideOwnWindow = "outside_own_window"
        case disabled = "disabled"
        case noSurface = "no_surface"
        case busyNow = "busy_now"
        case rescueAmbient = "rescue_ambient"
        // Started
        case afterPrompt = "after_prompt"
        case onYourOwn = "on_your_own"
        case quietArm = "quiet_arm"

        /// Plain words for the coach log's "held back" counts.
        var label: String {
            switch self {
            case .control: "kept quiet to measure"
            case .dailyCap: "daily limit"
            case .cooldown: "just asked"
            case .stickyPanel: "a plan was on screen"
            case .driftActive: "rescue had it"
            case .away: "away from desk"
            case .quietHours: "quiet hours"
            case .calendarBusy: "in a meeting"
            case .snoozed: "you said not now"
            case .released: "done for today"
            case .screenShare: "sharing screen"
            case .panelSpacing: "asked < 2h ago"
            case .onTrack: "on track"
            case .outsideWindow: "outside your windows"
            case .outsideOwnWindow: "outside your windows"
            case .disabled: "switched off"
            case .noSurface: "nowhere to show"
            case .busyNow: "busy with something else"
            case .rescueAmbient: "menu-bar counter only"
            case .question: "quick question"
            default: rawValue.replacingOccurrences(of: "_", with: " ")
            }
        }
    }

    static let maxEntries = 2_000
    static let fileName = "coach-journal.jsonl"

    /// Nil disables writing (tests, evidence captures).
    let fileURL: URL?
    /// The whole file, in memory: the coach log shows several days.
    private(set) var recent: [Entry] = []
    private var lastQuietKey: String?
    private var writesSinceTrim = 0

    init(fileURL: URL?) {
        self.fileURL = fileURL
        recent = Array(Self.load(from: fileURL).suffix(Self.maxEntries))
    }

    static var defaultURL: URL { AppIsolation.supportDirectory.appendingPathComponent(fileName) }

    /// Appends an entry. Repeats of the same "quiet" reason are written once until something
    /// else happens, so a 15-second tick doesn't flood the file. A quiet line with an attempt
    /// (a logged decision point) is always written: each one is a decision.
    func record(
        _ kind: Entry.Kind,
        _ text: String,
        code: Code? = nil,
        attemptID: UUID? = nil,
        propensity: Double? = nil,
        hook: String? = nil,
        at now: Date = Date()
    ) {
        if kind == .quiet && attemptID == nil {
            let key = "\(code?.rawValue ?? "")|\(text)"
            guard key != lastQuietKey else { return }
            lastQuietKey = key
        } else {
            lastQuietKey = nil
        }
        let entry = Entry(at: now, kind: kind, text: text, code: code, attemptID: attemptID, propensity: propensity, hook: hook)
        recent.append(entry)
        if recent.count > Self.maxEntries { recent.removeFirst(recent.count - Self.maxEntries) }
        append(entry)
    }

    func entries(on day: Date, calendar: Calendar = .current) -> [Entry] {
        recent.filter { calendar.isDate($0.at, inSameDayAs: day) }
    }

    /// Entries from the start of the day `days - 1` days before `now` through `now`.
    func entries(lastDays days: Int, now: Date = Date(), calendar: Calendar = .current) -> [Entry] {
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -(max(days, 1) - 1), to: today) ?? today
        return recent.filter { $0.at >= start && $0.at <= now }
    }

    // MARK: File

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private func append(_ entry: Entry) {
        guard let fileURL, var line = try? Self.encoder.encode(entry) else { return }
        line.append(0x0A)
        let manager = FileManager.default
        if !manager.fileExists(atPath: fileURL.path) {
            try? manager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            manager.createFile(atPath: fileURL.path, contents: line)
        } else if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        }
        writesSinceTrim += 1
        if writesSinceTrim >= 200 {
            writesSinceTrim = 0
            Self.trim(fileURL)
        }
    }

    static func load(from url: URL?) -> [Entry] {
        guard let url, let data = try? Data(contentsOf: url) else { return [] }
        return data.split(separator: 0x0A).compactMap { try? decoder.decode(Entry.self, from: Data($0)) }
    }

    static func trim(_ url: URL, keep: Int = maxEntries) {
        guard let data = try? Data(contentsOf: url) else { return }
        let lines = data.split(separator: 0x0A)
        guard lines.count > keep else { return }
        var kept = Data()
        for line in lines.suffix(keep) {
            kept.append(contentsOf: line)
            kept.append(0x0A)
        }
        try? kept.write(to: url, options: .atomic)
    }
}
