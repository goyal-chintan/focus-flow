# FocusFlow UI Evidence Automation

## Goals

- Capture contract-driven screenshots for all critical UI review flows.
- Produce reproducible evidence from command line (local and CI-compatible).
- Include motion evidence for animation quality checks.
- Export machine-readable and human-readable artifacts for design/product reviews.

## Architecture

### 1) Contract Layer (existing)

- `Sources/FocusFlow/Review/ReviewArtifactContract.swift`
  - Defines required flow IDs and canonical artifact paths.

### 2) Evidence State Seeding (new)

- `TimerViewModel.configureForEvidence(...)` (`#if DEBUG`)
  - Creates a side-effect-free VM setup for capture without full runtime bootstrapping.
- `TimerViewModel.seedEvidenceCompletionState(...)` (`#if DEBUG`)
  - Seeds deterministic completion/overtime states without real timers.

### 3) Capture Harness (new)

- `Tests/FocusFlowTests/UIEvidenceCaptureTests.swift`
  - Renders each required flow to PNG in light/dark mode.
  - Exports timer ring animation GIF for motion evidence.
  - Writes:
    - `manifest.json` (machine-readable artifact map)
    - `journey.md` (step-by-step review walkthrough)
  - Supports selective runs via env vars:
    - `FOCUSFLOW_REVIEW_FLOW_FILTER`
    - `FOCUSFLOW_REVIEW_APPEARANCE_FILTER`

### 4) Command Runner (new)

- `Scripts/capture-ui-evidence.sh`
  - Default runner: `xcodebuild`
  - Optional runner: `swift test`
  - Exposes run configuration:
    - `RUN_ID`
    - `FLOW_FILTER`
    - `APPEARANCE_FILTER`
    - `RUNNER`

## Output Format

All evidence lives under:

`Artifacts/review/<run-id>/`

- `light/*.png`
- `dark/*.png`
- `light/timer_ring_animation.gif`
- `dark/timer_ring_animation.gif`
- `manifest.json`
- `journey.md`

## Typical Commands

```bash
# Full evidence run
./Scripts/capture-ui-evidence.sh

# Dark-only pass
APPEARANCE_FILTER=dark ./Scripts/capture-ui-evidence.sh

# Flow subset
FLOW_FILTER=menu_bar_idle,coach_strong_window ./Scripts/capture-ui-evidence.sh
```
