# toolchain.sh — sourced by the build scripts. POSIX sh.
#
# The asset catalog needs Xcode's actool. When `xcode-select` points at the Command Line
# Tools, `swift build` fails with "tool 'actool' requires Xcode". Point this shell (only) at
# Xcode instead of changing the system-wide setting.

focusflow_use_xcode_toolchain() {
    if [ -n "${DEVELOPER_DIR:-}" ]; then
        return 0
    fi
    active="$(xcode-select -p 2>/dev/null || true)"
    case "$active" in
        *.app/Contents/Developer) return 0 ;;
    esac
    for candidate in /Applications/Xcode.app /Applications/Xcode-beta.app; do
        if [ -d "$candidate/Contents/Developer" ]; then
            DEVELOPER_DIR="$candidate/Contents/Developer"
            export DEVELOPER_DIR
            return 0
        fi
    done
    echo "✗ Xcode is required to build FocusFlow (asset catalog needs actool)." >&2
    echo "  Install Xcode, or set DEVELOPER_DIR=/path/to/Xcode.app/Contents/Developer." >&2
    return 1
}
