#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRATCH_ROOT="$ROOT/.build/design-lab-test-scratch"
HOME_ROOT="$ROOT/.build/design-lab-test-home"

run_category() {
    local label="$1"
    local filter="$2"
    local scratch="$SCRATCH_ROOT/$label"
    local home="$HOME_ROOT/$label"

    rm -rf "$scratch" "$home"
    mkdir -p "$scratch" "$home"

    HOME="$home" swift test --scratch-path "$scratch" --filter "$filter"
}

mkdir -p "$SCRATCH_ROOT" "$HOME_ROOT"

run_category model "DesignLabModelTests" &
pid_model=$!
run_category store "DesignLabStoreTests" &
pid_store=$!
run_category logs "VariantLabLogStoreTests" &
pid_logs=$!
run_category integration "DesignLabIntegrationTests" &
pid_integration=$!
run_category guardrails "DesignLabStorageGuardrailTests" &
pid_guardrails=$!

wait "$pid_model"
wait "$pid_store"
wait "$pid_logs"
wait "$pid_integration"
wait "$pid_guardrails"

rm -rf "$SCRATCH_ROOT/full" "$HOME_ROOT/full"
mkdir -p "$SCRATCH_ROOT/full" "$HOME_ROOT/full"
HOME="$HOME_ROOT/full" swift test --scratch-path "$SCRATCH_ROOT/full"
