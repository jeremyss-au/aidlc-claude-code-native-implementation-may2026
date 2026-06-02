#!/bin/bash
# t47: Construction Bolt-by-Bolt flow — verify vocabulary, audit events, state field, and Glossary (15 tests)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/tap.sh"
source "$SCRIPT_DIR/../lib/fixtures.sh"

plan 15

SKILL_MD="$AIDLC_SRC/skills/aidlc/SKILL.md"
STAGE_PROTOCOL="$AIDLC_SRC/skills/aidlc/stage-protocol.md"
CODE_GEN="$AIDLC_SRC/skills/aidlc/stages/construction/code-generation.md"
AUDIT_TS="$AIDLC_SRC/tools/aidlc-audit.ts"
AUDIT_FORMAT="$AIDLC_SRC/knowledge/aidlc-shared/audit-format.md"
STATE_TEMPLATE="$AIDLC_SRC/knowledge/aidlc-shared/state-template.md"

# --- Tests 1-4: "Construction Phase N" labels are gone ---

for n in 1 2 3 4; do
  if grep -q "Construction Phase $n" "$SKILL_MD" 2>/dev/null; then
    not_ok "SKILL.md no longer labels sub-steps 'Construction Phase $n'" "found 'Construction Phase $n'"
  else
    ok "SKILL.md no longer labels sub-steps 'Construction Phase $n'"
  fi
done

# --- Test 5: SKILL.md references bolt-plan.md in the Construction flow ---

assert_grep "$SKILL_MD" "bolt-plan.md" "SKILL.md Construction flow reads bolt-plan.md"

# --- Test 6: SKILL.md describes the walking skeleton ---

if grep -qi "walking skeleton" "$SKILL_MD" 2>/dev/null; then
  ok "SKILL.md Construction flow references the walking skeleton"
else
  not_ok "SKILL.md Construction flow references the walking skeleton" "no walking-skeleton mention"
fi

# --- Test 7: SKILL.md describes the ladder prompt ---

if grep -qi "ladder prompt" "$SKILL_MD" 2>/dev/null; then
  ok "SKILL.md Construction flow references the ladder prompt"
else
  not_ok "SKILL.md Construction flow references the ladder prompt" "no ladder-prompt mention"
fi

# --- Tests 8-11: 4 new audit events registered in aidlc-audit.ts ---

for event in BOLT_STARTED BOLT_COMPLETED BOLT_FAILED AUTONOMY_MODE_SET; do
  if grep -q "\"$event\"" "$AUDIT_TS" 2>/dev/null; then
    ok "aidlc-audit.ts registers $event"
  else
    not_ok "aidlc-audit.ts registers $event" "event not in VALID_EVENT_TYPES"
  fi
done

# --- Test 12: audit-format.md documents the new events (spot-check BOLT_STARTED) ---

assert_grep "$AUDIT_FORMAT" "BOLT_STARTED" "audit-format.md documents BOLT_STARTED"

# --- Test 13: state-template.md includes Construction Autonomy Mode ---

assert_grep "$STATE_TEMPLATE" "Construction Autonomy Mode" "state-template.md exposes Construction Autonomy Mode"

# --- Test 14: stage-protocol.md Glossary ties Bolt to stages 3.1-3.5 and batches 3.6/3.7 ---

if grep -q "3\.1.*3\.5" "$STAGE_PROTOCOL" 2>/dev/null && grep -qi "3\.6.*3\.7.*once" "$STAGE_PROTOCOL" 2>/dev/null; then
  ok "stage-protocol.md Glossary ties Bolt to 3.1-3.5 with 3.6/3.7 once at end"
else
  not_ok "stage-protocol.md Glossary ties Bolt to 3.1-3.5 with 3.6/3.7 once at end" "expected strings not both found"
fi

# --- Test 15: code-generation.md documents orchestrator-managed gating ---

if grep -qi "orchestrator-managed gating\|suppressed by the orchestrator" "$CODE_GEN" 2>/dev/null; then
  ok "code-generation.md notes orchestrator-managed gating in Bolt flow"
else
  not_ok "code-generation.md notes orchestrator-managed gating in Bolt flow" "suppression note missing"
fi

finish
