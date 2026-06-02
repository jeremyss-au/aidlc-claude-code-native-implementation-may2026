#!/bin/bash
# t54: Structural assertions for the compaction-awareness flow and the
# --test-run terminal state.
#
# Compaction awareness (SKILL.md):
#   - Session Check references aidlc-state.ts resume and reads compaction_pending
#   - AskUserQuestion block offers Continue / Review / Restart
#   - acknowledge-compaction is called after the user answers
#
# Test-run terminal state (aidlc-jump.ts):
#   - `--test-run` with a jump target emits WORKFLOW_COMPLETED with
#     Reason=test-run-stopped-at-<target> and sets Status=Completed.
#   - Consumer docs explicitly call out that this is a CI-only flow.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/tap.sh"
source "$SCRIPT_DIR/../lib/fixtures.sh"

plan 8

SKILL="$AIDLC_SRC/skills/aidlc/SKILL.md"
JUMP="$AIDLC_SRC/tools/aidlc-jump.ts"

# --- Compaction awareness (structural on SKILL.md) ---

# Test 1: Session Check references resume with compaction_pending
if grep -q "compaction_pending" "$SKILL"; then
  ok "SKILL.md Session Check references compaction_pending from resume"
else
  not_ok "SKILL.md Session Check references compaction_pending from resume" \
    "grep found no match"
fi

# Test 2: AskUserQuestion offers three options (Continue / Review / Restart)
all_options=true
for option in "Continue from current stage" "Review prior artifact" "Restart stage"; do
  if ! grep -q "$option" "$SKILL"; then
    all_options=false
    break
  fi
done
if $all_options; then
  ok "compaction AskUserQuestion offers all three options"
else
  not_ok "compaction AskUserQuestion offers all three options" \
    "missing one of: Continue / Review / Restart"
fi

# Test 3: acknowledge-compaction is wired in
if grep -q "acknowledge-compaction" "$SKILL"; then
  ok "SKILL.md calls acknowledge-compaction after user answers"
else
  not_ok "SKILL.md calls acknowledge-compaction after user answers" \
    "grep found no match — is the wiring missing?"
fi

# Test 4: Compaction block mentions SESSION_COMPACTED in context
if grep -q "SESSION_COMPACTED\|context was compacted" "$SKILL"; then
  ok "SKILL.md compaction block names SESSION_COMPACTED / context was compacted"
else
  not_ok "SKILL.md compaction block names SESSION_COMPACTED" \
    "no context reference found"
fi

# --- Test-run terminal state (structural on aidlc-jump.ts) ---

# Test 5: --test-run flag recognized in jump tool
if grep -qE 'testRunMode|test-run' "$JUMP"; then
  ok "aidlc-jump.ts recognizes --test-run flag"
else
  not_ok "aidlc-jump.ts recognizes --test-run flag" "no --test-run handling found"
fi

# Test 6: Emits WORKFLOW_COMPLETED with Reason=test-run-stopped-at-<target>
if grep -q 'test-run-stopped-at' "$JUMP"; then
  ok "aidlc-jump.ts emits WORKFLOW_COMPLETED with Reason=test-run-stopped-at-<target>"
else
  not_ok "aidlc-jump.ts emits WORKFLOW_COMPLETED with Reason=test-run-stopped-at-<target>" \
    "pattern not found"
fi

# --- End-to-end --test-run terminal state (runtime) ---

# Test 7: --test-run jump to a target emits WORKFLOW_COMPLETED
PROJ=$(create_test_project)
seed_audit_file "$PROJ"
seed_state_file "$PROJ" "$REPO_ROOT/tests/fixtures/state-mid-ideation.md"

export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

if command -v bun >/dev/null 2>&1; then
  # jump's test-run-terminal behavior triggers when the state file declares
  # Test Run Mode: true (set by `aidlc-utility init --test-run` or
  # `--test-strategy --test-run`). Inject the field so the fixture is in
  # the right mode without running full init.
  printf '\n- **Test Run Mode**: true\n' >> "$PROJ/aidlc-docs/aidlc-state.md"
  bun "$JUMP" execute --target feasibility --direction forward --test-run --project-dir "$PROJ" >/dev/null 2>&1 || true
  if grep -q '^\*\*Event\*\*: WORKFLOW_COMPLETED' "$PROJ/aidlc-docs/audit.md" 2>/dev/null; then
    ok "--test-run jump emits WORKFLOW_COMPLETED terminal event"
  else
    not_ok "--test-run jump emits WORKFLOW_COMPLETED terminal event" \
      "no WORKFLOW_COMPLETED in audit.md"
  fi

  # Test 8: Reason field contains the target slug
  if grep -qE '\*\*Reason\*\*: test-run-stopped-at-feasibility' "$PROJ/aidlc-docs/audit.md" 2>/dev/null; then
    ok "--test-run terminal event Reason=test-run-stopped-at-feasibility"
  else
    not_ok "--test-run terminal event Reason=test-run-stopped-at-feasibility" \
      "Reason field missing or wrong value"
  fi
else
  ok "--test-run jump emits WORKFLOW_COMPLETED (SKIP: bun not installed)"
  ok "--test-run terminal event Reason=test-run-stopped-at-feasibility (SKIP)"
fi
cleanup_test_project "$PROJ"

finish
