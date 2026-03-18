# Design Tokens Exports

This directory contains machine-readable outputs from `FocusFlow2` Design Lab.

## Export Files

- `bootstrap.json`
- `component-decision-<component>.json`
- `promoted-snapshot-<snapshot-id>.json`

## Notes

- JSON output is encoded with stable key ordering and ISO-8601 dates.
- These files are meant to feed future UI implementation directly.
- The local app store remains isolated from the `FocusFlow` production store.

