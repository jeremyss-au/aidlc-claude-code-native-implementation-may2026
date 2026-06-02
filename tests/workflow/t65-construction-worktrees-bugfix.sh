#!/bin/bash
# t65: Construction worktrees per scope — bugfix (v0.4.0 MR 13).
# Skeleton-off scope (incremental, no GOOS ceremony). practices-discovery SKIP.
# (8 tests — skeleton-off scopes don't need the practices-discovery EXECUTE check.)
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

PROJ=$(setup_construction_project "bugfix")

assert_scope_codegen_mode "bugfix" "EXECUTE"
assert_construction_prose_intact
assert_practices_preamble_present
assert_hold_merge_invariant_present
assert_dispatch_event_runs_for_scope "bugfix" "$PROJ"
assert_skill_skeleton_stance_for_scope "bugfix" "off"

# bugfix is skeleton-off → SKILL.md U3 prose must explicitly include it in
# the skeleton-off list (verified via assert_skill_skeleton_stance_for_scope above).
# Additionally: bugfix SKIPs practices-discovery (incremental scopes don't
# rebuild practices each workflow).
MAPPING="$AIDLC_SRC/tools/data/scope-mapping.json"
PD_MODE=$(bun -e "console.log(require('$MAPPING').bugfix.stages['practices-discovery']);")
if [ "$PD_MODE" = "SKIP" ]; then
  ok "bugfix scope SKIPs practices-discovery (incremental scope)"
else
  not_ok "bugfix should SKIP practices-discovery" "got: $PD_MODE"
fi

STATE="$PROJ/aidlc-docs/aidlc-state.md"
if grep -q "Worktree Path" "$STATE" && grep -q "Bolt Refs" "$STATE"; then
  ok "v7 state has v0.4.0 fields for bugfix"
else
  not_ok "v7 state missing v0.4.0 fields" "$STATE"
fi

cleanup_test_project "$PROJ"
finish
