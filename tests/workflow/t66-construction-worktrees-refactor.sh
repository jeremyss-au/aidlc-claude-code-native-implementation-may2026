#!/bin/bash
# t66: Construction worktrees per scope — refactor (v0.4.0 MR 13).
# Skeleton-off; practices-discovery SKIP. (8 tests)
set -euo pipefail
T_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$T_DIR/../lib/tap.sh"
source "$T_DIR/../lib/fixtures.sh"
source "$T_DIR/_construction-worktrees-helpers.sh"

export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

if ! command -v bun >/dev/null 2>&1; then
  echo "1..0 # SKIP bun not installed"
  exit 0
fi

plan 8

PROJ=$(setup_construction_project "refactor")

assert_scope_codegen_mode "refactor" "EXECUTE"
assert_construction_prose_intact
assert_practices_preamble_present
assert_hold_merge_invariant_present
assert_dispatch_event_runs_for_scope "refactor" "$PROJ"
assert_skill_skeleton_stance_for_scope "refactor" "off"

MAPPING="$AIDLC_SRC/tools/data/scope-mapping.json"
PD_MODE=$(bun -e "console.log(require('$MAPPING').refactor.stages['practices-discovery']);")
if [ "$PD_MODE" = "SKIP" ]; then
  ok "refactor scope SKIPs practices-discovery"
else
  not_ok "refactor should SKIP practices-discovery" "got: $PD_MODE"
fi

STATE="$PROJ/aidlc-docs/aidlc-state.md"
if grep -q "Worktree Path" "$STATE" && grep -q "Bolt Refs" "$STATE"; then
  ok "v7 state has v0.4.0 fields for refactor"
else
  not_ok "v7 state missing v0.4.0 fields" "$STATE"
fi

cleanup_test_project "$PROJ"
finish
