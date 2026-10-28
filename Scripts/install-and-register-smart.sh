#!/bin/sh
# Replaced by install.sh, which builds release, registers with LaunchServices and relaunches.
# Kept so existing habits and links keep working.
exec "$(cd -- "$(dirname -- "$0")" && pwd)/install.sh" "$@"
