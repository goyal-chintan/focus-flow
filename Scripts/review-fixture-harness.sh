#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <run-id> [--verify]"
  exit 1
fi

RUN_ID="$1"
VERIFY="${2:-}"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ARTIFACT_ROOT="$ROOT_DIR/Artifacts/review/$RUN_ID"

FLOW_IDS=(
  "menu_bar_idle"
  "menu_bar_focusing"
  "menu_bar_paused"
  "menu_bar_overtime"
  "menu_bar_break_overrun"
  "session_complete_focus_complete"
  "session_complete_manual_stop"
  "session_complete_break_complete"
  "coach_quick_prompt"
  "coach_strong_window"
  "settings_calendar_permissions"
  "settings_reminders_permissions"
  "first_run_initial_render"
  "first_run_first_toggle"
)

mkdir -p "$ARTIFACT_ROOT/light" "$ARTIFACT_ROOT/dark"

if [[ "$VERIFY" != "--verify" ]]; then
  echo "Prepared artifact folders:"
  echo "  $ARTIFACT_ROOT/light"
  echo "  $ARTIFACT_ROOT/dark"
  exit 0
fi

missing=0
for appearance in light dark; do
  for flow_id in "${FLOW_IDS[@]}"; do
    expected="$ARTIFACT_ROOT/$appearance/$flow_id.png"
    if [[ ! -f "$expected" ]]; then
      echo "Missing artifact: $expected"
      missing=$((missing + 1))
    fi
  done
done

if [[ $missing -gt 0 ]]; then
  echo "Artifact verification failed: $missing required captures missing."
  exit 2
fi

echo "Artifact verification passed for run-id: $RUN_ID"
