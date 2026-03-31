#!/bin/sh
set -eu

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
REPO_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
. "$SCRIPT_DIR/lib/screenshot-automation.sh"

RUN_ID="${RUN_ID:-$(date -u +%Y%m%d-%H%M%S)-readme}"
APPEARANCE_FILTER="${APPEARANCE_FILTER:-dark}"
OUTPUT_DIR="${FOCUSFLOW_README_SCREENSHOT_OUTPUT_DIR:-$REPO_DIR/docs/screenshots}"
SOURCE_ROOT="${FOCUSFLOW_README_SCREENSHOT_SOURCE_ROOT:-$REPO_DIR/Artifacts/review/$RUN_ID}"
SOURCE_DIR="${FOCUSFLOW_README_SCREENSHOT_SOURCE_DIR:-$SOURCE_ROOT/$APPEARANCE_FILTER}"
CONTRACT_PATH="${FOCUSFLOW_README_SCREENSHOT_CONTRACT_PATH:-$(focusflow_readme_screenshot_contract_path)}"
FLOW_FILTER="$(awk 'NR > 1 && NF > 0 { print $1 }' "$CONTRACT_PATH" | paste -sd ',' -)"

echo "Refreshing README screenshots..."
echo "  run id: $RUN_ID"
echo "  appearance: $APPEARANCE_FILTER"
echo "  flows: $FLOW_FILTER"

RUN_ID="$RUN_ID" \
APPEARANCE_FILTER="$APPEARANCE_FILTER" \
FLOW_FILTER="$FLOW_FILTER" \
bash "$SCRIPT_DIR/capture-ui-evidence.sh"

focusflow_publish_readme_screenshots "$SOURCE_DIR" "$OUTPUT_DIR" "$CONTRACT_PATH"

echo ""
echo "README screenshots refreshed."
echo "  source: $SOURCE_DIR"
echo "  output: $OUTPUT_DIR"
