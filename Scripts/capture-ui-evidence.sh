#!/bin/sh
set -eu

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
REPO_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_DIR"

RUN_ID="${RUN_ID:-$(date -u +%Y%m%d-%H%M%S)}"
RUNNER="${RUNNER:-xcodebuild}"
FLOW_FILTER="${FLOW_FILTER:-}"
APPEARANCE_FILTER="${APPEARANCE_FILTER:-}"

export FOCUSFLOW_REVIEW_RUN_ID="$RUN_ID"
if [ -n "$FLOW_FILTER" ]; then
    export FOCUSFLOW_REVIEW_FLOW_FILTER="$FLOW_FILTER"
fi
if [ -n "$APPEARANCE_FILTER" ]; then
    export FOCUSFLOW_REVIEW_APPEARANCE_FILTER="$APPEARANCE_FILTER"
fi

mkdir -p "$REPO_DIR/Artifacts/review"
RUN_MARKER="$(mktemp)"
touch "$RUN_MARKER"

echo "Capturing FocusFlow UI evidence..."
echo "  run id: $RUN_ID"
echo "  runner: $RUNNER"
if [ -n "$FLOW_FILTER" ]; then
    echo "  flow filter: $FLOW_FILTER"
fi
if [ -n "$APPEARANCE_FILTER" ]; then
    echo "  appearance filter: $APPEARANCE_FILTER"
fi

if [ "$RUNNER" = "swift" ]; then
    swift test --filter UIEvidenceCaptureTests/testCaptureReviewArtifactsForAllRequiredFlows
else
    xcodebuild \
        -workspace .swiftpm/xcode/package.xcworkspace \
        -scheme FocusFlow \
        -destination 'platform=macOS' \
        test \
        -only-testing:FocusFlowTests/UIEvidenceCaptureTests/testCaptureReviewArtifactsForAllRequiredFlows
fi

OUTPUT_DIR="$(find "$REPO_DIR/Artifacts/review" -mindepth 1 -maxdepth 1 -type d -newer "$RUN_MARKER" | sort | tail -n 1)"
if [ -z "$OUTPUT_DIR" ]; then
    OUTPUT_DIR="$REPO_DIR/Artifacts/review/$RUN_ID"
fi
rm -f "$RUN_MARKER"
echo ""
echo "Evidence capture complete."
echo "  output:   $OUTPUT_DIR"
echo "  manifest: $OUTPUT_DIR/manifest.json"
echo "  journey:  $OUTPUT_DIR/journey.md"
