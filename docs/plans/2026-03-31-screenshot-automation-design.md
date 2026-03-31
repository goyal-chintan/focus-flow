# Screenshot Automation Design

## Problem

FocusFlow already has an automated UI-evidence pipeline in `UIEvidenceCaptureTests`, but the last-mile tooling has two issues:

- `Scripts/capture-ui-evidence.sh` defaults to `xcodebuild`, which currently fails on this machine before artifacts are produced.
- README screenshots in `docs/screenshots/` are not refreshed from the deterministic review artifacts, so they have drifted into inconsistent sizes and crops.

The screenshot flow also has a product constraint: it must not interrupt active desktop work. That rules out solutions that depend on foregrounding a live app window or capturing the real desktop.

## Approved approach

Keep the existing offscreen SwiftUI renderer and fix the tooling around it.

1. Make `swift test` the default capture path, while preserving `RUNNER=xcodebuild` as an explicit opt-in.
2. Add a small screenshot contract for the four README images:
   - source review flow ID
   - published filename
   - fixed output size
3. Add a one-command `Scripts/refresh-readme-screenshots.sh` wrapper that:
   - captures only the README screenshot flows
   - uses dark appearance by default
   - publishes normalized images into `docs/screenshots/`
4. Add targeted tests for the shell tooling so the default runner and README publishing behavior are regression-proof.

## Why this fits the requirement

- It stays non-disruptive because the renderer remains offscreen inside the test process.
- It makes screenshots “proper” by publishing them from deterministic artifacts instead of ad-hoc manual exports.
- It makes the process repeatable with a single refresh command instead of a loose multi-step workflow.

## Alternatives considered

### 1. Dedicated visible capture window on another Space

Pros:
- More closely matches a live app surface.

Cons:
- Still risks stealing attention, switching Spaces, or surfacing windows while the user is working.
- Adds orchestration complexity that the current problem does not require.

Decision: rejected because the user explicitly prefers automation that stays out of the way.

### 2. Keep manual README screenshot publishing

Pros:
- Minimal code changes.

Cons:
- Preserves the exact drift problem we are fixing.
- Leaves no reliable contract between the review artifacts and README assets.

Decision: rejected because it does not solve the root cause.

### 3. Rework the renderer to use live window capture APIs

Pros:
- Could eventually validate more composition details.

Cons:
- Larger scope than needed for the current failure.
- Changes the proven non-disruptive architecture instead of fixing the broken/default tooling.

Decision: rejected for now; keep the offscreen renderer and improve the tooling contract.

## Implementation boundaries

In scope:
- capture runner default/fallback behavior
- README screenshot contract and publish script
- tests and README documentation

Out of scope:
- changing actual app UI
- replacing the offscreen renderer with live desktop capture
- fixing the unrelated `DriftClassificationMemoryTests` baseline failure
