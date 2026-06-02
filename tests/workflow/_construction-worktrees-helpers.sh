#!/bin/bash
# Helpers for v0.4.0 MR 13 workflow tests t60-t67 (construction-worktrees per scope).
#
# Each per-scope test (one per Construction-bearing scope) asserts the MR 13
# orchestration contract holds for that scope without running a full `claude -p`
# end-to-end (which would add ~minutes per test to the workflow tier). The
# contract is:
#
#   1. scope-mapping.json has the expected `code-generation` execution mode
#      for the scope (skeleton-on scopes EXECUTE; bugfix/refactor/security-patch
#      EXECUTE but skip Inception-design stages; infra SKIPs entirely — not in
#      this test set).
#   2. Stub bolt-plan.md with N Bolts → SKILL.md per-Bolt loop is structurally
#      reachable for the scope (CONSTRUCTION region present, parallel-batch
#      block present, dispatch instrumentation prose present, halt-and-ask
#      prose present).
#   3. The `aidlc-bolt dispatch-event` subcommand runs cleanly inside an
#      initialized project for the scope — emits MERGE_DISPATCH_INVOKED audit
#      row at the right position in the per-Bolt audit sequence.
#   4. For skeleton-on scopes: SKILL.md walking-skeleton block respects the
#      practices fallback chain (assertions probe the U3 dynamic-stance prose).
#   5. For skeleton-off scopes: SKILL.md U3 prose names the scope as
#      skeleton-off in the fallback list.
#
# This avoids the multi-minute `claude -p` round-trip of the original workflow
# tests (t50 etc.) while still proving MR 13's per-scope contract holds.

# Source guard — only meaningful when sourced from per-scope test files.
: "${AIDLC_SRC:?AIDLC_SRC must be set (source tests/lib/fixtures.sh first)}"

# Sets up an integration project AND runs `aidlc-utility init` for $1 (scope).
# Returns the project path on stdout. Prefer this over the bare
# setup_integration_project for MR 13 workflow tests because we need
# aidlc-docs/aidlc-state.md to exist (the orchestrator and dispatch-event
# tools both probe that path).
setup_construction_project() {
  local scope="$1"
  local proj
  proj=$(setup_integration_project --with-greenfield-stub)
  bun "$AIDLC_SRC/tools/aidlc-utility.ts" init \
    --project-dir "$proj" --force --scope "$scope" >/dev/null 2>&1
  echo "$proj"
}

# Asserts the scope-mapping.json entry for $1 has the expected
# code-generation mode ("EXECUTE" or "SKIP").
assert_scope_codegen_mode() {
  local scope="$1"
  local expected="$2"
  local mapping="$AIDLC_SRC/tools/data/scope-mapping.json"
  local actual
  actual=$(bun -e "
    const m = require('$mapping');
    const s = m['$scope'];
    if (!s) { console.log('MISSING'); process.exit(0); }
    console.log(s.stages['code-generation'] || 'UNDEFINED');
  ")
  if [ "$actual" = "$expected" ]; then
    ok "scope-mapping.json: $scope code-generation = $expected"
  else
    not_ok "scope-mapping.json: $scope code-generation should be $expected" "got: $actual"
  fi
}

# Asserts CONSTRUCTION region is present in SKILL.md with the MR 13
# parallel-batch + dispatch-instrumentation + halt-and-ask prose intact.
assert_construction_prose_intact() {
  local skill="$AIDLC_SRC/skills/aidlc/SKILL.md"
  if grep -q "### CONSTRUCTION Flow" "$skill" \
    && grep -q "Parallel batch dispatch" "$skill" \
    && grep -q "MERGE_DISPATCH_INVOKED" "$skill" \
    && grep -q "Halt-and-ask failure handling" "$skill"; then
    ok "SKILL.md CONSTRUCTION flow has parallel-batch + dispatch + halt-and-ask"
  else
    not_ok "SKILL.md missing one of the MR 13 prose surfaces" "check CONSTRUCTION region"
  fi
}

# Asserts MR 13 dispatch-event subcommand emits a MERGE_DISPATCH_INVOKED row
# inside an initialized project for $scope.
assert_dispatch_event_runs_for_scope() {
  local scope="$1"
  local proj="$2"
  local audit="$proj/aidlc-docs/audit.md"
  bun "$AIDLC_SRC/tools/aidlc-bolt.ts" dispatch-event \
    --event MERGE_DISPATCH_INVOKED \
    --slug "t-$scope-bolt-1" \
    --practices-excerpt "scope=$scope" \
    --project-dir "$proj" >/dev/null 2>&1
  if grep -q "MERGE_DISPATCH_INVOKED" "$audit" \
    && grep -q "Bolt slug.*t-$scope-bolt-1" "$audit"; then
    ok "dispatch-event MERGE_DISPATCH_INVOKED emits cleanly for scope=$scope"
  else
    not_ok "dispatch-event failed to emit for scope=$scope" "$(grep -c MERGE_ "$audit" || echo 0)"
  fi
}

# Asserts SKILL.md walking-skeleton dynamic-stance prose names $scope in the
# correct list (skeleton-on or skeleton-off).
assert_skill_skeleton_stance_for_scope() {
  local scope="$1"
  local stance="$2"  # "on" or "off"
  local skill="$AIDLC_SRC/skills/aidlc/SKILL.md"
  # Pull the skeleton-stance fallback paragraph (U3 prose).
  local fallback_block
  fallback_block=$(awk '/scope-mapping defaults/{flag=1} flag && /^$/{exit} flag' "$skill" | head -10)
  if [ "$stance" = "on" ]; then
    if echo "$fallback_block" | grep -q "skeleton-on for.*$scope"; then
      ok "SKILL.md U3 names $scope as skeleton-on"
    else
      not_ok "SKILL.md U3 should name $scope as skeleton-on" "$fallback_block"
    fi
  elif [ "$stance" = "off" ]; then
    if echo "$fallback_block" | grep -q "skeleton-off for.*$scope"; then
      ok "SKILL.md U3 names $scope as skeleton-off"
    else
      not_ok "SKILL.md U3 should name $scope as skeleton-off" "$fallback_block"
    fi
  fi
}

# Asserts SKILL.md U1 preamble is present (orchestrator reads practices once).
assert_practices_preamble_present() {
  local skill="$AIDLC_SRC/skills/aidlc/SKILL.md"
  if grep -q "Read team practices once at Construction start" "$skill" \
    && grep -q "extractMarkdownSection" "$skill" \
    && grep -q "PRACTICES_SECTION_EMPTY" "$skill"; then
    ok "SKILL.md U1 practices preamble present (extractMarkdownSection + PRACTICES_SECTION_EMPTY)"
  else
    not_ok "SKILL.md U1 practices preamble missing" "check ~line 622"
  fi
}

# Asserts SKILL.md U5 multi-failure HOLD-MERGE invariant prose is present.
assert_hold_merge_invariant_present() {
  local skill="$AIDLC_SRC/skills/aidlc/SKILL.md"
  if grep -q "HOLD-MERGE invariant" "$skill" \
    && grep -q "Merge-Held: true" "$skill"; then
    ok "SKILL.md U5 HOLD-MERGE invariant + Merge-Held marker present"
  else
    not_ok "SKILL.md U5 HOLD-MERGE prose missing" "check halt-and-ask region"
  fi
}
