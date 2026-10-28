# Installing FocusFlow from source

```bash
bash Scripts/install.sh
```

Run it once to install, and again after every `git pull` to update. It:

1. Uses Xcode's toolchain for this build, even when `xcode-select` points at the Command Line Tools. The asset catalog needs Xcode's `actool`.
2. Builds a **release** binary.
3. Assembles `FocusFlow.app` with an Info.plist. The build number is the git commit count, so each install is newer than the last.
4. Signs it with the **FocusFlow Development** certificate. The first run creates it through `setup-codesign.sh`. A stable signature keeps Calendar, Reminders and Automation permissions across reinstalls.
5. Quits the running copy (asks first, forces after 5 s), then replaces `~/Applications/FocusFlow.app` in one step.
6. Registers the app with LaunchServices (`lsregister -f`) and refreshes its Spotlight entry (`mdimport`).
7. Launches it and checks it stays running.

## Options

| Variable | Default | Effect |
|---|---|---|
| `INSTALL_DIR` | `~/Applications` | Where the app goes. `/Applications` also works for an admin user. |
| `NO_LAUNCH=1` | off | Install without launching. |
| `VERSION` | `1.0` | Marketing version shown in Finder. |
| `CODESIGN_IDENTITY` | `FocusFlow Development` | Signing certificate name. |
| `DEVELOPER_DIR` | auto | Xcode to build with. |

## Requirements

- macOS 26 or later.
- Xcode in `/Applications/Xcode.app` (or set `DEVELOPER_DIR`). The Command Line Tools alone cannot build the asset catalog.

## Spotlight

macOS indexes `~/Applications` and `/Applications` by itself. The installer registers the new bundle at once, so Spotlight, Launchpad and `open -a FocusFlow` find it right away. Do not turn Spotlight indexing off and on, or delete `.Spotlight-V100`: neither is needed.

Keep **one** copy. If the installer warns that another `FocusFlow.app` exists, delete that one. Two copies show up twice in Spotlight, and `open -a` may start the old one.

Check what macOS knows about:

```bash
mdfind "kMDItemCFBundleIdentifier == 'com.focusflow.app'"
```

## Troubleshooting

| Symptom | Fix |
|---|---|
| `tool 'actool' requires Xcode` | Install Xcode. To fix it for every tool, run `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`. |
| macOS asks for Calendar/Reminders again after an update | The app was signed ad hoc. Run `bash Scripts/setup-codesign.sh`, then install again. |
| Spotlight still opens an old build | Delete the duplicate copy, then run the installer again. |
| The app does not start | Open Console.app and look for crash reports from `FocusFlow`. |

## Other scripts

- `Scripts/run.sh`: debug build launched from `.build/debug` for quick development runs. It does not install anything.
- `Scripts/build-dmg.sh`: release DMG for distribution.
- `Scripts/uninstall.sh`: quits and removes the installed app.
- `Scripts/install-and-register-smart.sh`: old name; it now runs `install.sh`.
