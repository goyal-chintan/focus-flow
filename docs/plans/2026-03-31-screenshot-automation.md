# Screenshot Automation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make FocusFlow screenshot capture reliable and non-disruptive by default, and add a one-command way to refresh the README screenshots from deterministic review artifacts.

**Architecture:** Keep screenshot generation inside the existing offscreen `UIEvidenceCaptureTests` pipeline, because it already avoids desktop interference. Add a thin shell-tooling layer for runner resolution and README publishing, plus targeted tests that validate the shell behavior without touching unrelated app code.

**Tech Stack:** POSIX shell, `swift test`, XCTest, AppKit/ImageIO, `sips`

---

### Task 1: Add screenshot tooling tests and shared contract

**Files:**
- Create: `Tests/FocusFlowTests/ScreenshotAutomationScriptTests.swift`
- Create: `Scripts/lib/screenshot-automation.sh`
- Create: `Scripts/readme-screenshot-contract.tsv`
- Reference: `Scripts/capture-ui-evidence.sh`
- Reference: `Tests/FocusFlowTests/UIEvidenceCaptureTests.swift`

**Step 1: Write the failing tests**

Add targeted tests for:
- default runner resolution returns `swift` when `RUNNER` is unset
- explicit runner override preserves `xcodebuild`
- README publishing reads the contract, copies/resizes source artifacts, and writes the expected files/sizes

Example test shape:

```swift
func testDefaultCaptureRunnerFallsBackToSwift() throws {
    let result = try runShell(". Scripts/lib/screenshot-automation.sh; unset RUNNER; focusflow_resolve_capture_runner")
    XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "swift")
}
```

**Step 2: Run the targeted tests to verify they fail**

Run:

```bash
cd /Users/chintan/Personal/repos/FocusFlow/.worktrees/fix/screenshot-automation
swift test --filter ScreenshotAutomationScriptTests
```

Expected: FAIL because the shell helper/contract do not exist yet.

**Step 3: Write the minimal shared shell contract/helper**

Implement:
- runner resolution helper
- contract-path helper
- contract-driven README publish helper that resizes outputs to fixed dimensions

Prefer a single shared contract file instead of duplicating flow IDs and sizes across scripts/tests.

**Step 4: Run the targeted tests to verify they pass**

Run:

```bash
swift test --filter ScreenshotAutomationScriptTests
```

Expected: PASS

**Step 5: Commit**

```bash
git add Tests/FocusFlowTests/ScreenshotAutomationScriptTests.swift Scripts/lib/screenshot-automation.sh Scripts/readme-screenshot-contract.tsv
git commit -m "test: add screenshot automation tooling coverage"
```

### Task 2: Make capture default to the working non-disruptive path

**Files:**
- Modify: `Scripts/capture-ui-evidence.sh`
- Test: `Tests/FocusFlowTests/ScreenshotAutomationScriptTests.swift`

**Step 1: Update the capture script to use the shared runner helper**

Behavior requirements:
- default to `swift`
- keep `RUNNER=xcodebuild` available as an opt-in override
- keep existing `RUN_ID`, `FLOW_FILTER`, and `APPEARANCE_FILTER` behavior intact

**Step 2: Run the existing capture command that previously failed**

Run:

```bash
cd /Users/chintan/Personal/repos/FocusFlow/.worktrees/fix/screenshot-automation
RUN_ID=tdd-default FLOW_FILTER=menu_bar_focusing APPEARANCE_FILTER=dark bash Scripts/capture-ui-evidence.sh
```

Expected: PASS and generate `Artifacts/review/tdd-default/dark/menu_bar_focusing.png`

**Step 3: Verify explicit xcodebuild override still routes correctly**

Use the shell test coverage added in Task 1 for the override path instead of requiring `xcodebuild` to succeed on this machine.

**Step 4: Commit**

```bash
git add Scripts/capture-ui-evidence.sh
git commit -m "fix: default screenshot capture to swift"
```

### Task 3: Add one-command README screenshot publishing

**Files:**
- Create: `Scripts/refresh-readme-screenshots.sh`
- Modify: `README.md`
- Reference: `docs/screenshots/`

**Step 1: Write the publish wrapper**

The wrapper should:
- derive the README flow list from `Scripts/readme-screenshot-contract.tsv`
- capture only those flows in dark mode by default
- publish normalized screenshots into `docs/screenshots/`
- allow test overrides for source/output directories via environment variables

**Step 2: Run the publish command**

Run:

```bash
cd /Users/chintan/Personal/repos/FocusFlow/.worktrees/fix/screenshot-automation
RUN_ID=readme-refresh bash Scripts/refresh-readme-screenshots.sh
```

Expected:
- four README screenshot files refreshed under `docs/screenshots/`
- sizes match the contract exactly

**Step 3: Update README documentation**

Document:
- `Scripts/capture-ui-evidence.sh` now defaults to the `swift` runner
- `Scripts/refresh-readme-screenshots.sh` refreshes README screenshots from deterministic artifacts

**Step 4: Re-run verification**

Run:

```bash
swift build
swift test --filter ScreenshotAutomationScriptTests
RUN_ID=readme-refresh-check bash Scripts/refresh-readme-screenshots.sh
```

Expected:
- build succeeds
- targeted screenshot automation tests pass
- README screenshots are regenerated without requiring a foreground app window

**Step 5: Commit**

```bash
git add Scripts/refresh-readme-screenshots.sh README.md docs/screenshots
git commit -m "fix: automate readme screenshot refresh"
```

### Task 4: Final verification and handoff

**Files:**
- Review only

**Step 1: Run the project verification commands**

Run:

```bash
swift build
swift test
```

Expected:
- `swift build` passes
- `swift test` still shows the pre-existing unrelated failure in `DriftClassificationMemoryTests`

**Step 2: Capture the before/after status**

Report explicitly that:
- screenshot tooling changes are verified with targeted tests and end-to-end commands
- full-suite baseline still contains the unrelated pre-existing failure

**Step 3: Commit**

```bash
git add docs/plans/2026-03-31-screenshot-automation-design.md docs/plans/2026-03-31-screenshot-automation.md
git commit -m "docs: add screenshot automation plan"
```

## Notes

- Worktree path: `/Users/chintan/Personal/repos/FocusFlow/.worktrees/fix/screenshot-automation`
- Do not modify the unrelated AppUsage / Guardian files in the main workspace.
- Clean-worktree baseline currently has one unrelated failing test:

```text
DriftClassificationMemoryTests
  Session-scoped allowance does not apply to previous session
```

- Use targeted screenshot-tooling tests for TDD and report the unrelated full-suite failure separately.
