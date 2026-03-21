import Foundation

struct BlockingHelper {
    private static let startMarker = "# FocusFlow-Block-Start"
    private static let endMarker = "# FocusFlow-Block-End"
    private static let hostsPath = "/etc/hosts"
    private static let helperDir = NSHomeDirectory() + "/Library/Application Support/FocusFlow"
    private static let helperPath = NSHomeDirectory() + "/Library/Application Support/FocusFlow/blocking-helper.sh"
    private static let askpassPath = NSHomeDirectory() + "/Library/Application Support/FocusFlow/sudo-askpass.sh"
    private static let keepAliveQueue = DispatchQueue(label: "FocusFlow.SudoKeepAlive")
    nonisolated(unsafe) private static var keepAliveTimer: DispatchSourceTimer?
    private static let keepAliveIntervalSeconds: TimeInterval = 240

    /// Install the helper script once (creates with proper permissions)
    static func installHelperIfNeeded() {
        do {
            try FileManager.default.createDirectory(atPath: helperDir, withIntermediateDirectories: true)
        } catch {
            print("[BlockingHelper] Failed to create helper directory: \(error.localizedDescription)")
        }

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
        do {
            try script.write(toFile: helperPath, atomically: true, encoding: .utf8)
        } catch {
            print("[BlockingHelper] Failed to write helper script: \(error.localizedDescription)")
        }
        // Make executable
        do {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helperPath)
        } catch {
            print("[BlockingHelper] Failed to set helper script permissions: \(error.localizedDescription)")
        }
        installAskpassIfNeeded()
    }

    /// Execute the helper with admin privileges.
    /// Prompts once via sudo askpass and keeps the sudo ticket alive while app runs.
    @discardableResult
    private static func executeWithAdmin(_ command: String) -> Bool {
        installHelperIfNeeded()
        guard ensureSudoSession() else { return false }

        let status = runProcess(
            executablePath: "/usr/bin/sudo",
            arguments: ["-n", "bash", helperPath] + command.split(separator: " ").map(String.init)
        )
        if status == 0 { return true }

        print("[BlockingHelper] Privileged command failed: \(command)")
        return false
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
        let cleanDomains = domains.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        let domainArgs = cleanDomains.joined(separator: " ")
        if executeWithAdmin("block \(domainArgs)") {
            disableChromiumSecureDNS()
        }
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

    private static func installAskpassIfNeeded() {
        let script = """
        #!/bin/bash
        /usr/bin/osascript <<'APPLESCRIPT'
        set promptText to "FocusFlow needs administrator access once to enable website blocking for this macOS session."
        set promptResult to display dialog promptText default answer "" with hidden answer buttons {"Cancel", "Continue"} default button "Continue"
        text returned of promptResult
        APPLESCRIPT
        """
        do {
            try script.write(toFile: askpassPath, atomically: true, encoding: .utf8)
        } catch {
            print("[BlockingHelper] Failed to write askpass script: \(error.localizedDescription)")
        }
        do {
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: askpassPath)
        } catch {
            print("[BlockingHelper] Failed to set askpass script permissions: \(error.localizedDescription)")
        }
    }

    private static func ensureSudoSession() -> Bool {
        if runProcess(executablePath: "/usr/bin/sudo", arguments: ["-n", "-v"]) == 0 {
            startSudoKeepAlive()
            return true
        }

        var env = ProcessInfo.processInfo.environment
        env["SUDO_ASKPASS"] = askpassPath
        env["SSH_ASKPASS_REQUIRE"] = "force"
        env["SUDO_PROMPT"] = "FocusFlow admin password: "

        if runProcess(executablePath: "/usr/bin/sudo", arguments: ["-A", "-v"], environment: env) == 0 {
            startSudoKeepAlive()
            return true
        }

        print("[BlockingHelper] Admin authorization failed or was cancelled.")
        return false
    }

    private static func startSudoKeepAlive() {
        keepAliveQueue.async {
            if keepAliveTimer != nil { return }
            let timer = DispatchSource.makeTimerSource(queue: keepAliveQueue)
            timer.schedule(
                deadline: .now() + keepAliveIntervalSeconds,
                repeating: keepAliveIntervalSeconds
            )
            timer.setEventHandler {
                let status = runProcess(executablePath: "/usr/bin/sudo", arguments: ["-n", "-v"])
                if status != 0 {
                    keepAliveTimer?.cancel()
                    keepAliveTimer = nil
                }
            }
            keepAliveTimer = timer
            timer.resume()
        }
    }

    private static func runProcess(
        executablePath: String,
        arguments: [String],
        environment: [String: String]? = nil
    ) -> Int32? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        if let environment {
            process.environment = environment
        }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            print("[BlockingHelper] Failed to run process \(executablePath): \(error)")
            return nil
        }
    }
}
