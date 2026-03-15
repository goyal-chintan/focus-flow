import Foundation

struct BlockingHelper {
    private static let startMarker = "# FocusFlow-Block-Start"
    private static let endMarker = "# FocusFlow-Block-End"
    private static let hostsPath = "/etc/hosts"
    private static let helperPath = NSHomeDirectory() + "/Library/Application Support/FocusFlow/blocking-helper.sh"

    /// Install the helper script once (creates with proper permissions)
    static func installHelperIfNeeded() {
        let dir = (helperPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        // Always overwrite to keep it current
        let script = """
        #!/bin/bash
        HOSTS="/etc/hosts"
        START_MARKER="# FocusFlow-Block-Start"
        END_MARKER="# FocusFlow-Block-End"

        case "$1" in
            block)
                shift
                # Remove any existing block first
                sed -i '' "/$START_MARKER/,/$END_MARKER/d" "$HOSTS" 2>/dev/null
                # Add new block
                echo "" >> "$HOSTS"
                echo "$START_MARKER" >> "$HOSTS"
                for domain in "$@"; do
                    echo "127.0.0.1 $domain" >> "$HOSTS"
                    if [[ ! "$domain" == www.* ]]; then
                        echo "127.0.0.1 www.$domain" >> "$HOSTS"
                    fi
                done
                echo "$END_MARKER" >> "$HOSTS"
                killall -HUP mDNSResponder 2>/dev/null || true
                ;;
            unblock)
                sed -i '' "/$START_MARKER/,/$END_MARKER/d" "$HOSTS" 2>/dev/null
                killall -HUP mDNSResponder 2>/dev/null || true
                ;;
            status)
                grep -q "$START_MARKER" "$HOSTS" && echo "active" || echo "inactive"
                ;;
        esac
        """
        try? script.write(toFile: helperPath, atomically: true, encoding: .utf8)
        // Make executable
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helperPath)
    }

    /// Request admin privileges once and run helper with sudo cached
    /// Uses `security authorizationdb` approach — the osascript admin dialog
    /// caches the auth for a short period so subsequent calls don't re-prompt
    static func blockWebsites(_ domains: [String]) {
        guard !domains.isEmpty else { return }
        installHelperIfNeeded()

        let domainArgs = domains.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.joined(separator: " ")
        let script = """
        do shell script "bash '\(helperPath)' block \(domainArgs)" with administrator privileges
        """
        runAppleScript(script)
    }

    static func unblockWebsites() {
        installHelperIfNeeded()

        let script = """
        do shell script "bash '\(helperPath)' unblock" with administrator privileges
        """
        runAppleScript(script)
    }

    /// Check if blocking is active WITHOUT requiring admin
    static func isBlockingActive() -> Bool {
        guard let contents = try? String(contentsOfFile: hostsPath, encoding: .utf8) else { return false }
        return contents.contains(startMarker)
    }

    /// Non-privileged cleanup attempt — for crash recovery, try without admin first
    /// If hosts file has stale entries, we need admin to clean up
    static func cleanupStaleBlocking() {
        guard isBlockingActive() else { return }
        // Need admin to modify /etc/hosts
        unblockWebsites()
    }

    @discardableResult
    private static func runAppleScript(_ source: String) -> Bool {
        let script = NSAppleScript(source: source)
        var error: NSDictionary?
        script?.executeAndReturnError(&error)
        if let error {
            print("[BlockingHelper] AppleScript error: \(error)")
            return false
        }
        return true
    }
}
