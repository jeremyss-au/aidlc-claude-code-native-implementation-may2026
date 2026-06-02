#!/bin/bash
# t70: Static checks for v0.4.0 MR 7 KB rewrites + agent + SKILL.md edits.
#
# Pins shape, not exact line numbers — uses heading markers and awk-extracted
# regions so tests survive future edits inside those regions.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/tap.sh"
source "$SCRIPT_DIR/../lib/fixtures.sh"

plan 14

SKILL="$AIDLC_SRC/skills/aidlc/SKILL.md"
AGENT="$AIDLC_SRC/agents/aidlc-pipeline-deploy-agent.md"
BS="$AIDLC_SRC/knowledge/aidlc-pipeline-deploy-agent/branching-strategies.md"
PR="$AIDLC_SRC/knowledge/aidlc-shared/rules-reading.md"

# --- 1. shared/rules-reading.md exists with all expected sections ---
assert_file_exists "$PR" "shared/rules-reading.md exists"
assert_grep "$PR" "## 1. Empty-template detection" \
  "rules-reading.md has empty-template detection section"
assert_grep "$PR" "## 2. Semantic-topic matching" \
  "rules-reading.md has semantic-topic matching section"
assert_grep "$PR" "## 3. Fallback chain" \
  "rules-reading.md has fallback chain section"

# --- 2. branching-strategies.md has Execution runbook + Failure modes per
#       strategy + Response contract ---
RUNBOOK_COUNT=$(grep -c "^### Execution runbook" "$BS")
assert_eq "$RUNBOOK_COUNT" "5" \
  "branching-strategies.md has 5 Execution runbook sub-sections (one per strategy)"
FAILURE_COUNT=$(grep -c "^### Failure modes" "$BS")
assert_eq "$FAILURE_COUNT" "5" \
  "branching-strategies.md has 5 Failure modes sub-sections (one per strategy)"
assert_grep "$BS" "^## Response contract" \
  "branching-strategies.md has Response contract top-level section"
# Cites the new shared KB.
assert_grep "$BS" "shared/rules-reading.md" \
  "branching-strategies.md references shared/rules-reading.md"

# --- 3. aidlc-pipeline-deploy-agent.md loads .claude/rules/ at position 4 ---
# Extract Knowledge Loading numbered list and confirm position 4 matches.
POS4=$(awk '
  /^## Knowledge Loading/ { inside=1; next }
  inside && /^## / { exit }
  inside { print }
' "$AGENT" | grep -E "^[0-9]+\. " | sed -n '4p')
assert_contains "$POS4" ".claude/rules/" \
  "aidlc-pipeline-deploy-agent.md Knowledge Loading position 4 is .claude/rules/"

# --- 4. SKILL.md per-Bolt execution: Steps 0, 0.5, 6.5, 6.75 ---
# Extract the per-Bolt execution region by heading marker. The region runs
# from "**Per-Bolt execution" until the next "**" heading.
PER_BOLT=$(awk '
  /\*\*Per-Bolt execution/ { inside=1; next }
  inside && /^\*\*/ && !/\*\*Per-Bolt execution/ { exit }
  inside { print }
' "$SKILL")
echo "$PER_BOLT" | grep -q "^0\. \*\*Worktree create dispatch" && \
  ok "SKILL.md per-Bolt execution has Step 0 (worktree create dispatch)" || \
  not_ok "SKILL.md per-Bolt execution has Step 0" "no Step 0 found in region"
echo "$PER_BOLT" | grep -q "^0\.5\. \*\*Verify create" && \
  ok "SKILL.md per-Bolt execution has Step 0.5 (verify create)" || \
  not_ok "SKILL.md per-Bolt execution has Step 0.5" "no Step 0.5 found"
echo "$PER_BOLT" | grep -q "^6\.5\. \*\*Worktree merge dispatch" && \
  ok "SKILL.md per-Bolt execution has Step 6.5 (worktree merge dispatch)" || \
  not_ok "SKILL.md per-Bolt execution has Step 6.5" "no Step 6.5 found"
echo "$PER_BOLT" | grep -q "^6\.75\. \*\*Verify merge" && \
  ok "SKILL.md per-Bolt execution has Step 6.75 (verify merge)" || \
  not_ok "SKILL.md per-Bolt execution has Step 6.75" "no Step 6.75 found"

# --- 5. SKILL.md halt-and-ask region mentions worktree-dispatch failure shapes ---
HAA=$(awk '
  /\*\*Halt-and-ask failure handling/ { inside=1; next }
  inside && /^\*\*/ && !/\*\*Halt-and-ask failure handling/ { exit }
  inside { print }
' "$SKILL")
echo "$HAA" | grep -q "Verify-failed" && \
  ok "SKILL.md halt-and-ask region documents Verify-failed (audit-silent) failure shape" || \
  not_ok "SKILL.md halt-and-ask region documents Verify-failed" "shape not present"

finish
