#!/bin/bash
# t60: validScopes() derives from scope-mapping.json (9 tests)
#
# Adding a scope to the mapping flows through every tool that validates
# scopes (init, scope-change, resolve-env-scope, doctor) with no code
# changes. MR 2 (#62) shipped validScopes(); MR 10 (#62) extended the
# de-hardcoding to NL keyword inference and the compiled summary table.
#
# Six pre-MR-10 assertions + three MR 10 extensions:
#   1. Static grep — VALID_SCOPES symbol is gone from tools/
#   2. Runtime — validScopes() on default mapping returns 9 alphabetical scopes
#   3. Fixture accept — init --scope fixture-scope succeeds
#   4. Fixture reject — init --scope bogus errors with fixture-scope in message
#   5. Fixture scope-change — scope-change to fixture-scope succeeds (state tool)
#   6. Fixture doctor — invalid env var fix hint lists fixture-scope
#   7. MR 10: fixture-scope with keywords → detect-scope --from-text matches it
#   8. MR 10: scope-table includes fixture-scope row when pointed at fixture JSON
#   9. MR 10: detect-scope emits SCOPE_DETECTED with Source=keyword for fixture-scope
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/tap.sh"
source "$SCRIPT_DIR/../lib/fixtures.sh"

export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

if ! command -v bun >/dev/null 2>&1; then
  echo "1..0 # SKIP bun not installed"
  exit 0
fi

plan 9

# --- Test 1: static grep — VALID_SCOPES gone from tools/ ---
HITS=$(grep -rE 'VALID_SCOPES' "$AIDLC_SRC/tools/" 2>/dev/null || true)
if [ -z "$HITS" ]; then
  ok "no VALID_SCOPES references in tools/"
else
  not_ok "no VALID_SCOPES references in tools/" "found: $HITS"
fi

# --- Test 2: runtime — validScopes() default returns 9 alphabetical scopes ---
LIB="$AIDLC_SRC/tools/aidlc-lib.ts"
EXPECTED="bugfix,enterprise,feature,infra,mvp,poc,refactor,security-patch,workshop"
ACTUAL=$(bun -e "import { validScopes } from '$LIB'; console.log([...validScopes()].join(','));" 2>&1 | tail -1)
assert_eq "$ACTUAL" "$EXPECTED" "validScopes() returns 9 alphabetically-sorted scopes"

# --- Shared fixture setup for tests 3-6 ---
# Start from an integration sandbox (copies .claude/ including tools/data/
# scope-mapping.json). Append a fixture-scope entry that reuses real
# stage slugs — stagesInScope() matches against stage-graph.json so slugs
# must exist. Uses poc's Minimal layout as a template.
setup_fixture_scope() {
  local proj="$1"
  local mapping="$proj/.claude/tools/data/scope-mapping.json"
  # Inject fixture-scope by splicing a sibling entry after "poc".
  # The body is minimal: just the 3 INITIALIZATION stages + intent-capture,
  # enough to exercise init without pulling in every downstream stage.
  bun -e "
    const fs = require('fs');
    const m = JSON.parse(fs.readFileSync('$mapping', 'utf-8'));
    m['fixture-scope'] = {
      depth: 'Minimal',
      stages: {
        'workspace-scaffold': 'EXECUTE',
        'workspace-detection': 'EXECUTE',
        'state-init': 'EXECUTE',
        'intent-capture': 'EXECUTE',
      },
    };
    // Fill in SKIP for every other real stage slug so stagesInScope() doesn't
    // misbehave. Copy from the canonical stage-graph.json.
    const graph = JSON.parse(fs.readFileSync('$proj/.claude/tools/data/stage-graph.json', 'utf-8'));
    for (const entry of graph) {
      if (!(entry.slug in m['fixture-scope'].stages)) {
        m['fixture-scope'].stages[entry.slug] = 'SKIP';
      }
    }
    fs.writeFileSync('$mapping', JSON.stringify(m, null, 2));
  "
}

# --- Test 3: fixture accept — init --scope fixture-scope succeeds ---
PROJ=$(setup_integration_project --no-aidlc-docs --strip-env-scope)
setup_fixture_scope "$PROJ"
set +e
OUT=$(bun "$PROJ/.claude/tools/aidlc-utility.ts" init --scope fixture-scope --project-dir "$PROJ" 2>&1)
RC=$?
set -e
if [ $RC -eq 0 ] && grep -qE '^- \*\*Scope\*\*: fixture-scope$' "$PROJ/aidlc-docs/aidlc-state.md"; then
  ok "init --scope fixture-scope succeeds against modified scope-mapping.json"
else
  not_ok "init --scope fixture-scope succeeds against modified scope-mapping.json" "rc=$RC, out=$OUT"
fi
cleanup_test_project "$PROJ"

# --- Test 4: fixture reject — init --scope bogus includes fixture-scope in error ---
PROJ=$(setup_integration_project --no-aidlc-docs --strip-env-scope)
setup_fixture_scope "$PROJ"
set +e
OUT=$(bun "$PROJ/.claude/tools/aidlc-utility.ts" init --scope bogus-notascope --project-dir "$PROJ" 2>&1)
set -e
assert_contains "$OUT" "fixture-scope" "init --scope bogus error message lists fixture-scope (derivation flowing through)"
cleanup_test_project "$PROJ"

# --- Test 5: fixture scope-change — scope-change to fixture-scope succeeds ---
PROJ=$(setup_integration_project --no-aidlc-docs --strip-env-scope --with-state "$REPO_ROOT/tests/fixtures/state-mid-ideation.md" --with-audit)
setup_fixture_scope "$PROJ"
set +e
bun "$PROJ/.claude/tools/aidlc-utility.ts" scope-change --scope fixture-scope --project-dir "$PROJ" >/dev/null 2>&1
set -e
if grep -qE '^- \*\*Scope\*\*: fixture-scope$' "$PROJ/aidlc-docs/aidlc-state.md"; then
  ok "scope-change --scope fixture-scope succeeds (covers aidlc-state.ts surface)"
else
  not_ok "scope-change --scope fixture-scope succeeds (covers aidlc-state.ts surface)"
fi
cleanup_test_project "$PROJ"

# --- Test 6: fixture doctor — invalid env var fix hint derives from mapping ---
PROJ=$(setup_integration_project --no-aidlc-docs --strip-env-scope)
setup_fixture_scope "$PROJ"
set +e
OUT=$(AWS_AIDLC_DEFAULT_SCOPE=still-bogus bun "$PROJ/.claude/tools/aidlc-utility.ts" doctor --project-dir "$PROJ" 2>&1)
set -e
assert_contains "$OUT" "fixture-scope" "doctor fix hint for invalid AWS_AIDLC_DEFAULT_SCOPE lists fixture-scope"
cleanup_test_project "$PROJ"

# --- Tests 7-9: MR 10 fixture-scope with keywords end-to-end ---
# Inject a fixture scope with its own NL trigger, then verify the MR 10
# surfaces (detect-scope --from-text, scope-table) pick it up without
# any SKILL.md edit. Closes the MR 10 acceptance criterion at tool level.
PROJ=$(setup_integration_project --no-aidlc-docs --strip-env-scope)
setup_fixture_scope "$PROJ"
# Add keywords to fixture-scope so detect-scope --from-text can find it.
bun -e "
  const fs = require('fs');
  const path = '$PROJ/.claude/tools/data/scope-mapping.json';
  const m = JSON.parse(fs.readFileSync(path, 'utf-8'));
  m['fixture-scope'].keywords = ['fixturetrigger'];
  fs.writeFileSync(path, JSON.stringify(m, null, 2));
"

# Test 7: inferScopeFromText picks up fixture-scope when its keyword fires.
# Note: `_resetScopeMappingForTests` is exported from lib.ts only (not from
# aidlc-utility.ts). Import the lib.ts symbol and call it before the
# aidlc-utility.ts helper reads the mapping through the freshly-set env.
ACTUAL=$(AIDLC_SCOPE_MAPPING="$PROJ/.claude/tools/data/scope-mapping.json" \
  MR10_INPUT="fixturetrigger test" bun -e "
    import { _resetScopeMappingForTests } from '$PROJ/.claude/tools/aidlc-lib.ts';
    import { inferScopeFromText } from '$PROJ/.claude/tools/aidlc-utility.ts';
    _resetScopeMappingForTests();
    console.log(inferScopeFromText(process.env.MR10_INPUT).scope);
  " 2>&1 | tail -1)
assert_eq "$ACTUAL" "fixture-scope" "inferScopeFromText picks fixture-scope from its keyword"

# Test 8: scope-table includes fixture-scope row via env-seam.
OUT=$(AIDLC_SCOPE_MAPPING="$PROJ/.claude/tools/data/scope-mapping.json" \
  bun "$PROJ/.claude/tools/aidlc-utility.ts" scope-table 2>&1)
assert_contains "$OUT" "| fixture-scope" "scope-table includes fixture-scope row when pointed at fixture mapping"

# Test 9: detect-scope --from-text emits SCOPE_DETECTED with Source=keyword.
AIDLC_SCOPE_MAPPING="$PROJ/.claude/tools/data/scope-mapping.json" \
  bun "$PROJ/.claude/tools/aidlc-utility.ts" detect-scope --from-text \
  --input "fixturetrigger" --project-dir "$PROJ" >/dev/null 2>&1
if grep -q "Detected scope.*: fixture-scope" "$PROJ/aidlc-docs/audit.md" && \
   grep -q "Source.*: keyword" "$PROJ/aidlc-docs/audit.md"; then
  ok "detect-scope --from-text emits SCOPE_DETECTED for fixture-scope (Source=keyword)"
else
  not_ok "detect-scope --from-text emits SCOPE_DETECTED for fixture-scope (Source=keyword)" \
    "audit: $(tail -20 "$PROJ/aidlc-docs/audit.md")"
fi
cleanup_test_project "$PROJ"

finish
