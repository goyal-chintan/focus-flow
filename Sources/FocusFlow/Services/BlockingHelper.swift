import Foundation

struct BlockingHelper {
    private static let startMarker = "# FocusFlow-Block-Start"
    private static let endMarker = "# FocusFlow-Block-End"
    private static let hostsPath = "/etc/hosts"
    private static let helperDir = NSHomeDirectory() + "/Library/Application Support/FocusFlow"
    private static let helperPath = NSHomeDirectory() + "/Library/Application Support/FocusFlow/blocking-helper.sh"

    /// Install the helper script once (creates with proper permissions)
    static func installHelperIfNeeded() {
        try? FileManager.default.createDirectory(atPath: helperDir, withIntermediateDirectories: true)

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
                # Add new block with both IPv4 and IPv6
                echo "" >> "$HOSTS"
                echo "$START_MARKER" >> "$HOSTS"
                for domain in "$@"; do
                    echo "127.0.0.1 $domain" >> "$HOSTS"
                    echo "::1 $domain" >> "$HOSTS"
                    if [[ ! "$domain" == www.* ]]; then
                        echo "127.0.0.1 www.$domain" >> "$HOSTS"
                        echo "::1 www.$domain" >> "$HOSTS"
                    fi
                done
                echo "$END_MARKER" >> "$HOSTS"
                # Flush DNS cache
                killall -HUP mDNSResponder 2>/dev/null || true
                dscacheutil -flushcache 2>/dev/null || true
                ;;
            unblock)
                sed -i '' "/$START_MARKER/,/$END_MARKER/d" "$HOSTS" 2>/dev/null
                killall -HUP mDNSResponder 2>/dev/null || true
                dscacheutil -flushcache 2>/dev/null || true
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

    /// Execute the helper with admin privileges.
    /// Uses osascript for the first call (prompts for admin password), then
    /// refreshes the sudo timestamp so subsequent calls via `sudo -n` succeed
    /// without prompting.
    private static func executeWithAdmin(_ command: String) {
        installHelperIfNeeded()

        // Try sudo -n first (non-interactive — works if timestamp is cached)
        let sudoProcess = Process()
        sudoProcess.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        sudoProcess.arguments = ["-n", "bash", helperPath] + command.split(separator: " ").map(String.init)
        sudoProcess.standardOutput = FileHandle.nullDevice
        sudoProcess.standardError = FileHandle.nullDevice
        try? sudoProcess.run()
        sudoProcess.waitUntilExit()

        if sudoProcess.terminationStatus == 0 {
            return // sudo cache was valid, no prompt needed
        }

        // sudo not cached — use osascript to prompt once, then refresh sudo timestamp
        let escapedHelper = helperPath.replacingOccurrences(of: "'", with: "'\\''")
        let script = """
        do shell script "bash '\(escapedHelper)' \(command) && /usr/bin/sudo -v" with administrator privileges
        """
        runAppleScript(script)
    }

    // MARK: - Chromium Secure DNS

    /// Chromium browsers (Arc, Chrome, Brave, Edge) use DNS-over-HTTPS by default,
    /// which bypasses /etc/hosts. We disable it during blocking and restore after.
    private static let chromiumBundles = [
        "com.google.Chrome",
        "company.thebrowser.Browser",   // Arc
        "com.brave.Browser",
        "com.microsoft.edgemac"
    ]

    private static func disableChromiumSecureDNS() {
        for bundle in chromiumBundles {
            // Set DnsOverHttpsMode to "off" — this is Chromium's policy setting
            let script = NSAppleScript(source: """
            do shell script "defaults write \(bundle) DnsOverHttpsMode -string off"
            """)
            var error: NSDictionary?
            script?.executeAndReturnError(&error)
        }
        print("[BlockingHelper] Disabled Secure DNS for Chromium browsers")
    }

    private static func restoreChromiumSecureDNS() {
        for bundle in chromiumBundles {
            let script = NSAppleScript(source: """
            do shell script "defaults delete \(bundle) DnsOverHttpsMode 2>/dev/null || true"
            """)
            var error: NSDictionary?
            script?.executeAndReturnError(&error)
        }
        print("[BlockingHelper] Restored Secure DNS for Chromium browsers")
    }

    // MARK: - Public API

    static func blockWebsites(_ domains: [String]) {
        guard !domains.isEmpty else { return }
        disableChromiumSecureDNS()
        let cleanDomains = domains.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        let domainArgs = cleanDomains.joined(separator: " ")
        executeWithAdmin("block \(domainArgs)")
    }

    static func unblockWebsites() {
        executeWithAdmin("unblock")
        restoreChromiumSecureDNS()
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
