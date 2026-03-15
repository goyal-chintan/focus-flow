import Foundation

struct BlockingHelper {
    private static let startMarker = "# FocusFlow-Block-Start"
    private static let endMarker = "# FocusFlow-Block-End"
    private static let hostsPath = "/etc/hosts"

    static func blockWebsites(_ domains: [String]) {
        guard !domains.isEmpty else { return }
        var entries = [startMarker]
        for domain in domains {
            let clean = domain.trimmingCharacters(in: .whitespaces).lowercased()
            entries.append("127.0.0.1 \(clean)")
            if !clean.hasPrefix("www.") {
                entries.append("127.0.0.1 www.\(clean)")
            }
        }
        entries.append(endMarker)
        let block = entries.joined(separator: "\\n")
        let script = "do shell script \"printf '\\n\(block)\\n' >> \(hostsPath) && killall -HUP mDNSResponder 2>/dev/null || true\" with administrator privileges"
        runAppleScript(script)
    }

    static func unblockWebsites() {
        let script = "do shell script \"sed -i '' '/\(startMarker)/,/\(endMarker)/d' \(hostsPath) && killall -HUP mDNSResponder 2>/dev/null || true\" with administrator privileges"
        runAppleScript(script)
    }

    static func isBlockingActive() -> Bool {
        guard let contents = try? String(contentsOfFile: hostsPath, encoding: .utf8) else { return false }
        return contents.contains(startMarker)
    }

    private static func runAppleScript(_ source: String) {
        let script = NSAppleScript(source: source)
        var error: NSDictionary?
        script?.executeAndReturnError(&error)
        if let error { print("AppleScript error: \(error)") }
    }
}
