# Design Lab Artifacts

This directory holds human-readable exports from `FocusFlow2` Design Lab.

## Runtime Model

- Local runtime state lives in `Application Support/FocusFlow2/DesignLab`.
- Repository exports are written here only when explicitly requested by export helpers.
- The runtime store is isolated from the production `FocusFlow` data store.

## Export Files

- `component-decision-<component>.md`
- `promoted-snapshot-<snapshot-id>.md`

## Decision Shape

Each component decision records:

- component id
- chosen variant
- tuned token overrides
- guided fix history
- state: `draft`, `compared`, `tuned`, `locked`, `promoted`
- lock and promotion timestamps
- version

