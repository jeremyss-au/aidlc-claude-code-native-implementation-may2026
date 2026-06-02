#!/bin/bash
# t64: Construction worktrees per scope — workshop (v0.4.0 MR 13).
# Skeleton-on; practices-discovery EXECUTE; multi-engineer parallel scenario. (9 tests)
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

plan 9

PROJ=$(setup_construction_project "workshop")

assert_scope_codegen_mode "workshop" "EXECUTE"
assert_construction_prose_intact
assert_practices_preamble_present
assert_hold_merge_invariant_present
assert_dispatch_event_runs_for_scope "workshop" "$PROJ"
assert_skill_skeleton_stance_for_scope "workshop" "on"

# Workshop scenario: SKILL.md U5 + §8 must reference parallel-engineer resume
# (the carve-out names git pull as the sync mechanism).
SKILL="$AIDLC_SRC/skills/aidlc/SKILL.md"
if grep -q "Workshop resume" "$SKILL" \
  && grep -q "git pull" "$SKILL"; then
  ok "SKILL.md §8 names workshop-resume + git-pull sync mechanism"
else
  not_ok "SKILL.md §8 workshop-resume carve-out missing" "check halt-and-ask region"
fi

# Multi-failure HOLD-MERGE marker must survive resume — the prose in §8
# names per-Bolt forked state as the persistence mechanism.
if grep -q "Merge-Held: true" "$SKILL" \
  && grep -q "Resuming a batch in flight" "$SKILL"; then
  ok "SKILL.md §8 names per-Bolt Merge-Held marker as resume-persistent"
else
  not_ok "SKILL.md §8 missing resume-mid-batch carve-out" "check halt-and-ask region"
fi

STATE="$PROJ/aidlc-docs/aidlc-state.md"
if grep -q "Worktree Path" "$STATE" && grep -q "Bolt Refs" "$STATE"; then
  ok "v7 state has v0.4.0 fields for workshop"
else
  not_ok "v7 state missing v0.4.0 fields" "$STATE"
fi

cleanup_test_project "$PROJ"
finish
