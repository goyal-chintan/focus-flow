# System-Wide Blocking Feature — Design Document

**Date:** 2026-03-16
**Status:** Approved

---

## Overview

Add website, app, and notification blocking during focus sessions. Uses `/etc/hosts` for websites, AppleScript + NSWorkspace for apps, and AppleScript for selective notification muting. Supports global default blocklists and per-project overrides.

## Architecture

### Three Blocking Engines

| Engine | Method | Scope |
|--------|--------|-------|
| Website | `/etc/hosts` → `127.0.0.1` with marker comments | All browsers, system-wide |
| App | AppleScript `quit app` + NSWorkspace 5-second poll | Per-app by bundle ID |
| Notification | AppleScript to mute per-app notifications | Per-app by bundle ID |

### BlockingService (Singleton)

Central coordinator. Activated when a focus session starts, deactivated when it ends/stops/is abandoned.

**Activate flow:**
1. Resolve effective block profile (project-specific or global default)
2. Run privileged helper to add domains to `/etc/hosts`
3. Flush DNS cache (`killall -HUP mDNSResponder`)
4. AppleScript quit blocked apps
5. Start NSWorkspace polling (5s interval) to prevent relaunching blocked apps
6. AppleScript mute notifications for specified apps

**Deactivate flow:**
1. Run privileged helper to remove domains from `/etc/hosts`
2. Flush DNS cache
3. Stop NSWorkspace polling
4. AppleScript restore notification settings

**Crash recovery:** On app launch, check if blocking markers exist in `/etc/hosts` and clean up.

### Privileged Helper

A shell script at `~/Library/Application Support/FocusFlow/blocking-helper.sh` that:
- Accepts `block` or `unblock` command + list of domains
- Adds/removes entries between `# FocusFlow-Block-Start` and `# FocusFlow-Block-End` markers
- Flushes DNS cache after modification
- Executed via `Process` with `/usr/bin/osascript` to prompt for admin password when needed

### `/etc/hosts` Format

```
# FocusFlow-Block-Start
127.0.0.1 youtube.com
127.0.0.1 www.youtube.com
127.0.0.1 x.com
127.0.0.1 www.x.com
# FocusFlow-Block-End
```

### AppleScript Integration

**Quit app:**
```applescript
tell application "Slack" to quit
```

**Check if app is running:**
```applescript
tell application "System Events" to (name of processes) contains "Slack"
```

**App monitoring:** Every 5 seconds, check `NSWorkspace.shared.runningApplications` against the blocked list. If a blocked app launches, immediately terminate it via `app.terminate()`.

---

## Data Model

### BlockProfile (SwiftData @Model)

| Field | Type | Notes |
|-------|------|-------|
| id | UUID | Primary key |
| name | String | e.g., "Social Media", "Full Focus" |
| blockedWebsites | [String] | Domains: ["youtube.com", "x.com"] |
| blockedApps | [String] | Bundle IDs: ["com.tinyspeck.slackmacgap"] |
| mutedNotificationApps | [String] | Bundle IDs for notification muting |
| isDefault | Bool | Used when project has no specific profile |
| createdAt | Date | |

Note: SwiftData can't store `[String]` directly. Store as comma-separated String and use computed property for array access.

### Project Extension

Add optional `blockProfile: BlockProfile?` relationship to existing Project model.

### Pre-built Profiles (Seeded on First Launch)

**Social Media:**
- Websites: youtube.com, x.com, twitter.com, reddit.com, instagram.com, facebook.com, tiktok.com
- Apps: (none by default)
- Notifications: (none by default)

**Full Focus:**
- Websites: all of Social Media + news.ycombinator.com, netflix.com, twitch.tv
- Apps: Slack, Discord, Telegram, WhatsApp
- Notifications: same apps

---

## UI

### Settings → Blocking Tab

- List of block profiles with edit/delete
- "New Profile" button
- Each profile shows: name, website count, app count, notification count
- Default profile indicator (star/checkmark)

### BlockProfileFormView

- Name field
- **Websites section:** list of domains with add/remove, text field with "Add" button
- **Apps section:** dropdown of installed applications (from NSWorkspace), multi-select
- **Notifications section:** dropdown of installed apps, multi-select
- Pre-fill buttons: "Social Media", "Productivity", "Entertainment"

### Project Form Update

- Add "Block Profile" picker to ProjectFormView
- Dropdown: None, or select from available profiles

### Menu Bar Popover

- Small shield/lock icon visible when blocking is active
- Tooltip: "Blocking active: 5 websites, 2 apps"

---

## Edge Cases

1. **App quit during focus:** Blocking cleanup runs on next launch via crash recovery
2. **No admin password:** If user cancels admin prompt, website blocking skipped (apps still blocked)
3. **User tries to edit /etc/hosts manually:** Marker comments make it easy to find/remove
4. **Multiple sessions:** Only one blocking session active at a time
5. **Break time:** Blocking stays active during breaks (user chose to focus)
6. **Session abandoned:** Full cleanup runs
7. **DNS cache:** Flushed on both block and unblock to ensure immediate effect
8. **www variants:** Always block both `domain.com` and `www.domain.com`

---

## Security Considerations

- Helper script is readable/editable by the user (stored in user's Application Support)
- Admin password prompted via osascript dialog (standard macOS pattern)
- No persistent root access — each block/unblock requires separate authorization
- Blocked app termination uses `NSRunningApplication.terminate()` (graceful, not SIGKILL)
