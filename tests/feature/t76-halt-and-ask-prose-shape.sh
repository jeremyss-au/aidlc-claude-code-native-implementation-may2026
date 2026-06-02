#!/bin/bash
# t76: halt-and-ask prose-shape contract across 4 surfaces. v0.4.0 MR 12 + MR 13.
# Pins line-anchored assertions (NOT file-wide grep) so existing "preserved"
# matches in branching-strategies.md can't false-green the test. (15 tests)
#
# v0.4.0 MR 13 added two italic carve-outs to SKILL.md halt-and-ask region:
# the audit-merge prefix-hash mismatch failure mode (MR 10 forward-note) and
# the orphan-BOLT_STARTED recovery seam (MR 9 forward-note). Tests 14-15
# pin these new subheadings so they can't drift away.
#
# Surfaces:
#   1. SKILL.md  — failure-handling block, slug-derivation paragraph,
#                  carve-out subheadings, "Inspecting a paused Bolt" para,
#                  MR 13 prefix-hash + orphan-BOLT_STARTED carve-outs
#   2. stage-protocol.md — AUQ template with [path]/[branch_name],
#                          preservation phrase same-line as Skip/Abort
#   3. branching-strategies.md — preservation appended to dirty-tree bullet,
#                                cross-link to halt-and-ask block
#   4. aidlc-pipeline-deploy-agent.md — preservation appended to conflict bullet
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/tap.sh"
source "$SCRIPT_DIR/../lib/fixtures.sh"

plan 15

SKILL="$AIDLC_SRC/skills/aidlc/SKILL.md"
PROTO="$AIDLC_SRC/skills/aidlc/stage-protocol.md"
BRANCH="$AIDLC_SRC/knowledge/aidlc-pipeline-deploy-agent/branching-strategies.md"
PDAGENT="$AIDLC_SRC/agents/aidlc-pipeline-deploy-agent.md"

# --- Tests 1-2: SKILL.md slug-derivation paragraph ---
# The phrase "Slug derivation" appears, paired with worktreePath reference
assert_grep "$SKILL" "Slug derivation" "SKILL.md has Slug derivation paragraph"
assert_grep "$SKILL" "lib\.ts:139.*worktreePath" "SKILL.md cites lib.ts:139 worktreePath as bolt- prefix source"

# --- Tests 3-4: SKILL.md carve-out structural subheadings ---
# Two subheadings on consecutive paragraph blocks; the structural marker is
# the literal "code-generation and merge-conflict (worktree visible)" string
# and "pre-creation and rejection (no worktree to show)".
assert_grep "$SKILL" "code-generation and merge-conflict (worktree visible)" "SKILL.md visible-worktree subheading"
assert_grep "$SKILL" "pre-creation and rejection (no worktree to show)" "SKILL.md no-worktree subheading"

# --- Test 5: SKILL.md "Inspecting a paused Bolt" paragraph references discard ---
assert_grep "$SKILL" "Inspecting a paused Bolt" "SKILL.md Inspecting paragraph header"
# Should mention discard --slug as the cleanup path
INSPECT_LINE=$(grep -n "Inspecting a paused Bolt" "$SKILL" | head -1 | cut -d: -f1)
TAIL=$(tail -n +"$INSPECT_LINE" "$SKILL" | head -3 | tr '\n' ' ')
echo "$TAIL" | grep -q "discard --slug"
if [ "$?" -eq 0 ]; then
  ok "Inspecting paragraph references discard --slug within 3 lines"
else
  not_ok "Inspecting paragraph references discard --slug within 3 lines" "got: $TAIL"
fi

# --- Tests 6-7: stage-protocol.md AUQ template has [path] and [branch_name] ---
# The new template interpolates [path] and [branch_name] in the question body
assert_grep "$PROTO" 'question.*\[path\].*\[branch_name\]' "stage-protocol.md AUQ question carries [path] and [branch_name]"
# Skip and Abort options keep "preserved" phrasing
assert_grep "$PROTO" 'Skip.*worktree preserved' "stage-protocol.md Skip option mentions worktree preserved"

# --- Test 8: stage-protocol.md Skip line same-line preservation phrase ---
# The bullet "- Skip:" should ALSO contain "Worktree at" on the same line
SKIP_LINE=$(grep -n "^- Skip:" "$PROTO" | head -1)
echo "$SKIP_LINE" | grep -q "Worktree at"
if [ "$?" -eq 0 ]; then
  ok "stage-protocol.md - Skip: line contains preservation phrase same-line"
else
  not_ok "stage-protocol.md - Skip: line contains preservation phrase same-line" "got: $SKIP_LINE"
fi

# --- Test 9: same for - Abort: ---
ABORT_LINE=$(grep -n "^- Abort:" "$PROTO" | head -1)
echo "$ABORT_LINE" | grep -q "Worktree at"
if [ "$?" -eq 0 ]; then
  ok "stage-protocol.md - Abort: line contains preservation phrase same-line"
else
  not_ok "stage-protocol.md - Abort: line contains preservation phrase same-line" "got: $ABORT_LINE"
fi

# --- Test 10: branching-strategies.md dirty-tree bullet has new phrase ---
DIRTY_LINE=$(grep -n "Dirty tree on merge" "$BRANCH" | head -1)
echo "$DIRTY_LINE" | grep -q "Worktree preserved on retry"
if [ "$?" -eq 0 ]; then
  ok "branching-strategies.md Dirty-tree bullet appends preservation phrase"
else
  not_ok "branching-strategies.md Dirty-tree bullet appends preservation phrase" "got: $DIRTY_LINE"
fi

# --- Test 11: branching-strategies.md cross-link to halt-and-ask block ---
assert_grep "$BRANCH" "stage-protocol\.md.*Halt-and-ask" "branching-strategies.md cross-links to stage-protocol halt-and-ask"

# --- Test 12: aidlc-pipeline-deploy-agent.md conflict bullet appended ---
PD_LINE=$(grep -n "On conflict envelopes" "$PDAGENT" | head -1)
echo "$PD_LINE" | grep -q "preserves the worktree"
if [ "$?" -eq 0 ]; then
  ok "aidlc-pipeline-deploy-agent.md conflict bullet appends preservation phrase"
else
  not_ok "aidlc-pipeline-deploy-agent.md conflict bullet appends preservation phrase" "got: $PD_LINE"
fi

# --- Test 13 (MR 13): SKILL.md prefix-hash carve-out (italic, not bold) ---
# v0.4.0 MR 10's forward-note named the prefix-hash failure mode for MR 13;
# v0.4.0 MR 13 adds it as an italic carve-out _Audit-merge prefix-hash mismatch:_
# in the halt-and-ask region. Italic preserves t70's region-extraction (which
# terminates on bold ^**).
assert_grep "$SKILL" "_Audit-merge prefix-hash mismatch:_" "SKILL.md italic carve-out for prefix-hash failure mode"

# --- Test 14 (MR 13): SKILL.md orphan-BOLT_STARTED recovery carve-out ---
# v0.4.0 MR 9's ship note named the recovery seam for MR 13; v0.4.0 MR 13
# adds an italic carve-out _Orphan-BOLT_STARTED recovery:_ instructing
# `aidlc-worktree discard --slug` for the cleanup path.
assert_grep "$SKILL" "_Orphan-BOLT_STARTED recovery:_" "SKILL.md italic carve-out for orphan-BOLT_STARTED recovery seam"

finish
