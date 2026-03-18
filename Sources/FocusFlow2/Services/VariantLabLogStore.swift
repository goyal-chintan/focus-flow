import Foundation

@MainActor
final class VariantLabLogStore {
    static let shared = VariantLabLogStore()

    private let encoder: JSONEncoder
    private let rootDirectory: URL?

    init(rootDirectory: URL? = nil) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
        self.rootDirectory = rootDirectory
    }

    func appendDecision(_ record: VariantLabDecisionRecord) throws -> URL {
        let directory = try logsDirectoryURL()
        let jsonlURL = directory.appendingPathComponent("decision-log.jsonl")
        let markdownURL = directory.appendingPathComponent("decision-log.md")

        var jsonData = try encoder.encode(record)
        jsonData.append(0x0A)
        try appendData(jsonData, to: jsonlURL)

        let markdown = record.markdownEntry + "\n"
        if let markdownData = markdown.data(using: .utf8) {
            try appendData(markdownData, to: markdownURL)
        }

        return markdownURL
    }

    func latestLogPath() -> URL? {
        try? logsDirectoryURL().appendingPathComponent("decision-log.md")
    }

    private func logsDirectoryURL() throws -> URL {
        let directory = rootDirectory ?? DesignLabStorageRoots.variantLabRootURL

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func appendData(_ data: Data, to url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } else {
            try data.write(to: url)
        }
    }
}
