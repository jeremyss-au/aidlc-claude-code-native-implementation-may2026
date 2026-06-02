#!/bin/bash
# t41: Validate SKILL.md handler structure for --stage/--phase/--scope/--depth/--test-strategy (32 tests)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/tap.sh"
source "$SCRIPT_DIR/../lib/fixtures.sh"

plan 32

SKILL="$AIDLC_SRC/skills/aidlc/SKILL.md"

# Verify SKILL.md contains the new handler sections
assert_grep "$SKILL" '\-\-stage' "SKILL.md documents --stage flag"
assert_grep "$SKILL" '\-\-phase' "SKILL.md documents --phase flag"
assert_grep "$SKILL" '\-\-scope' "SKILL.md documents --scope flag"
assert_grep "$SKILL" 'STAGE_JUMPED' "SKILL.md defines STAGE_JUMPED audit event"
assert_grep "$SKILL" '\[S\]' "SKILL.md documents [S] checkbox state"

# Verify composable flag extraction section exists
assert_grep "$SKILL" 'Composable Flag Extraction' "SKILL.md has composable flag extraction section"

# Verify error messages exist for invalid input
assert_grep "$SKILL" 'Unknown phase' "SKILL.md has invalid phase error message"
assert_grep "$SKILL" 'Unknown stage' "SKILL.md has invalid stage error message"
assert_grep "$SKILL" 'Unknown scope' "SKILL.md has invalid scope error message"

# Verify --stage and --phase are mutually exclusive
assert_grep "$SKILL" 'Cannot use --stage and --phase together' "SKILL.md enforces mutual exclusivity"

# Verify bidirectional jump support
assert_grep "$SKILL" 'FORWARD JUMP' "SKILL.md documents forward jump"
assert_grep "$SKILL" 'BACKWARD JUMP' "SKILL.md documents backward jump"
assert_grep "$SKILL" 'REDO' "SKILL.md documents redo jump"

# Verify initialization stages are blocked from jump targets
assert_grep "$SKILL" 'Cannot jump to initialization' "SKILL.md blocks jumping to init stages"

# Verify artifact re-use protocol is referenced
assert_grep "$SKILL" 'Artifact re-use\|existing artifacts' \
  "SKILL.md references artifact re-use on backward jump"

# --- --depth flag validation ---
assert_grep "$SKILL" '\-\-depth' "SKILL.md documents --depth flag"
assert_grep "$SKILL" 'Unknown depth' "SKILL.md has invalid depth error message"
assert_grep "$SKILL" 'minimal, standard, comprehensive' "SKILL.md lists valid depth values"

# --- --test-strategy flag validation ---
assert_grep "$SKILL" '\-\-test-strategy' "SKILL.md documents --test-strategy flag"
assert_grep "$SKILL" 'Unknown test strategy' "SKILL.md has invalid test strategy error message"
assert_grep "$SKILL" 'config-change' "SKILL.md references config-change handler"

# Verify stage graph has key slugs that --stage could reference
for slug in intent-capture market-research feasibility scope-definition \
  reverse-engineering requirements-analysis code-generation build-and-test \
  ci-pipeline deployment-pipeline observability-setup; do
  assert_grep "$SKILL" "$slug" "stage graph includes slug: $slug"
done

finish
