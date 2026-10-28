import Foundation

/// Coach v4 §3.1: every coach decision, in plain words, in release builds too.
/// Before v4 the installed app logged nothing, so "why was the coach quiet?" had no answer.
///
/// Stored as JSON lines in Application Support, trimmed to the newest `maxEntries`.
/// Insights shows today's entries.
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
        var id: String { "\(at.timeIntervalSince1970)-\(kind.rawValue)-\(text)" }
    }

    static let maxEntries = 2_000
    static let fileName = "coach-journal.jsonl"

    /// Nil disables writing (tests, evidence captures).
    let fileURL: URL?
    private(set) var recent: [Entry] = []
    private var lastQuietText: String?
    private var writesSinceTrim = 0

    init(fileURL: URL?) {
        self.fileURL = fileURL
        recent = Self.load(from: fileURL).suffix(200)
    }

    static func defaultURL() -> URL? {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return dir.appendingPathComponent("FocusFlow", isDirectory: true).appendingPathComponent(fileName)
    }

    /// Appends an entry. Repeats of the same "quiet" reason are written once until something
    /// else happens, so a 15-second tick doesn't flood the file.
    func record(_ kind: Entry.Kind, _ text: String, at now: Date = Date()) {
        if kind == .quiet {
            guard text != lastQuietText else { return }
            lastQuietText = text
        } else {
            lastQuietText = nil
        }
        let entry = Entry(at: now, kind: kind, text: text)
        recent.append(entry)
        if recent.count > 200 { recent.removeFirst(recent.count - 200) }
        append(entry)
    }

    func entries(on day: Date, calendar: Calendar = .current) -> [Entry] {
        recent.filter { calendar.isDate($0.at, inSameDayAs: day) }
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
