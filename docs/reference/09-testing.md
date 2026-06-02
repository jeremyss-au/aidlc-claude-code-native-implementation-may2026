# Testing

## Overview

The AI-DLC test suite is organized as a three-layer pyramid that balances speed vs. thoroughness.

```
            /\
           /  \    ACCEPTANCE — full workflows, artifact + experience verification
          / L3 \   When: before releases (weekly or pre-merge to main)
         /------\
        /        \
       /   L2     \  STAGE — individual stages with stub input, verify artifacts
      /------------\ When: CI push (every PR)
     /              \
    /      L1        \  PROTOCOL — contracts, structure, cross-references
   /------------------\ When: every local change
```

## Layer 1: Protocol (every change, no LLM, seconds)

Verifies the orchestrator's structural correctness without invoking the LLM. If these pass, the protocol is internally consistent — stages reference valid files, inputs/outputs chain correctly, routing tables match stage files.

**Tiers:** smoke, unit, feature

**What it tests:**
- File existence, permissions, naming conventions (smoke)
- Hook scripts (9 TypeScript via bun), stage frontmatter, knowledge inventory (unit)
- Scope-stage mapping, graph consistency, stage I/O contract chains, protocol compliance (feature)
- Stage output-to-step validation: all declared outputs referenced in instruction steps (feature, deterministic via the `aidlc-validate.ts` CLI tool)

**Run:** `bash tests/run-tests.sh` (default, no flags needed)

## Layer 2: Stage (CI push, LLM, minutes)

Runs individual stages in isolation with known workspace + state fixtures. Verifies each stage produces correct artifacts when given deterministic input.

**Tiers:** integration, stage

**What it tests:**
- Preflight health gate: Claude CLI on PATH, AWS credentials valid, Claude responds (exit 0), response non-empty (preflight)
- CLI tool utility handlers: --init, --doctor, --status, --stage, --phase (integration)
- Individual stages with greenfield/brownfield stubs, artifact verification (stage)

**Run:** `bash tests/run-tests.sh --ci`

## Layer 3: Acceptance (release, LLM, hours)

Runs full workflows and verifies the experience — not just state transitions, but artifact content, cross-stage coherence, and domain correctness.

**Tiers:** workflow

**What it tests:**
- Full bugfix lifecycle with brownfield stub + artifact assertions
- Full POC lifecycle with greenfield stub + artifact assertions
- State progression, scope routing, audit completeness, jump mechanics
- LLM semantic review of stage instruction quality (clarity, logical flow, ambiguity detection)

**Run:** `bash tests/run-tests.sh --release`

## Cross-Platform Coverage

The test suite runs on macOS, Linux, and Windows (via Git Bash). At runtime the AI-DLC hooks and CLI tools only require `bun` — the Bash dependency is strictly a test-harness concern. The same `tests/run-tests.sh` script executes identically on all three platforms.

**Validated MR 24 (2026-04-17)** on Windows Server 2022 via EC2 SSM:

| Tier | macOS | Windows Server 2022 | Notes |
|---|---|---|---|
| L1 (smoke + unit + feature) | 1273 / 1273 | 1273 / 1273 | Identical |
| L1 + L2 + L3 (`--all --debug`) | 1516 / 1516 | 1516 / 1516 | Identical after the portability fixes in this MR |

**Portability constraints baked into the suite:**

- **Paths**: `create_test_project` in `tests/lib/fixtures.sh` uses `cygpath -m` on Windows to return forward-slash absolute paths (`C:/Users/.../aidlc-test-X`). These round-trip cleanly through JSON (backslash escapes are an error in JSON) and are readable by both Git Bash utilities and native Windows `bun`.
- **In-place sed**: `sed -i ''` is BSD-only; `sed -i` is GNU-only. Use the portable `sed_i` helper in `tests/lib/fixtures.sh` — it writes to a tempfile and `mv`s, which behaves identically on every platform.
- **`grep -qiF`**: Git Bash has a known bug combining `-i` and `-F`. Use `-i` alone if your pattern has no regex metacharacters. Tests hit this in t16 before it was fixed.
- **`tar` archives**: macOS `tar` injects `._*` AppleDouble sidecar files by default. When bundling source for cross-platform test runs, use `COPYFILE_DISABLE=1 tar …` or `git archive`.
- **LLM timing on Windows**: Bedrock calls from Windows EC2 can be meaningfully slower than from macOS (first-call cold start, MSYS process fork overhead). Tests that invoke `claude -p` should respect the `CLAUDE_RC` convention documented in `tests/lib/fixtures.sh` — skip post-condition assertions when `CLAUDE_RC == 124` (timeout) rather than failing loudly on incomplete state. t70/t71 are canonical examples.

**Running the suite on Windows:**

1. Install Git for Windows (provides Git Bash + GNU coreutils `timeout`).
2. Install `bun` — prefer the official PowerShell installer or release zip over `npm install -g bun`, which can silently fail under unattended provisioning (SYSTEM account).
3. For L2/L3 only: install the Claude Code CLI with the native installer — PowerShell `irm https://claude.ai/install.ps1 | iex`. It drops a standalone `claude` binary on your user PATH and auto-updates. Ensure that PATH entry is also visible to Git Bash (a Machine/User PATH entry is; a PowerShell-session-only one is not) so `claude` resolves from the bash test runner.
4. Run `bash tests/run-tests.sh [--ci | --all]` from Git Bash.

No WSL. No Docker. Native Windows works.

## Preflight Validation

Before running any LLM-dependent tier (integration, stage, or workflow), the runner executes `t19-preflight-health.sh` as a gate. If the preflight fails, all LLM tiers are skipped.

| # | Assertion | On fail |
|---|-----------|---------|
| 1 | `claude` CLI on PATH | bail — no point continuing |
| 2 | `claude -p "echo ok"` exits 0 | bail — API unreachable |
| 3 | Response is non-empty | bail — API unresponsive |

After critical assertions pass, the script logs advisory diagnostics as TAP comments:
- **Response time** — warns if > 30s (API degradation)
- **Skill loading** — runs `/aidlc --help` and reports whether "AI-DLC" appeared

Advisory failures don't affect the exit code or gate. They appear in `--verbose` logs for debugging degradation.

## Test Registry

Complete inventory of all test files across tiers. Each entry is extracted from the `# tNN:` comment header in the source file.

> **Note:** t19 appears in both unit (`t19-tool-jump.sh`) and integration (`t19-preflight-health.sh`). The integration t19 is the preflight gate; the unit t19 tests the jump CLI tool.

### Smoke Tests

| Test ID | File | Description |
|---------|------|-------------|
| t01 | `tests/smoke/t01-file-structure.sh` | Verify all expected files exist in aidlc-claude-code/.claude/ |
| t02 | `tests/smoke/t02-hook-executability.sh` | All 9 hooks are executable |
| t03 | `tests/smoke/t03-settings-json.sh` | settings.json schema validation |
| t04 | `tests/smoke/t04-shell-lint.sh` | Guard two shell anti-patterns in tests/ (#34 trailing `[ ] && action`, #41 unbraced `$VAR` + non-ASCII) (2 tests) |
| t05 | `tests/smoke/t05-run-tests-parallel.sh` | Smoke guard for `--parallel N`: invalid-value handling, serial-vs-parallel parity, interleaving detection, failure propagation, sidecar cleanup, plus `--worktree` tier dispatch under `--ci` (14 tests) |
| t06 | `tests/smoke/t06-claude-md-paths.sh` | Distributable CLAUDE.md describes post-Wave-1 layout — no legacy `practices/`, `aidlc-knowledge/`, or `rules/aidlc/guardrails/` paths; mentions `.claude/sensors/` and `aidlc-org` rule file (6 tests) |
| t86 | `tests/smoke/t86-stage-protocol-section-13.sh` | v0.5.0 MR 4 (+ MR 16) — stage-protocol §13 (Learnings Ritual) prose pin + MEMORY_EMPTY registry placement + the SKILL.md Stage-Advancement wiring that makes the orchestrator call the gate; asserts `## 13. Learnings Ritual` heading, four canonical memory.md headings, two-surface learnings + `sensors:` bind (no `applies_to` fossil), MEMORY_EMPTY in three sources (TS / audit-format.md / 12-state-machine.md), the immutability invariant subsection, the SKILL.md Stage-Advancement call to `aidlc-learnings.ts surface` + `persist` (TEST_RUN_MODE-guarded), and the Test-Run-block §13 skip declaration (7 tests) |

### Unit Tests

| Test ID | File | Description |
|---------|------|-------------|
| t04 | `tests/unit/t04-agent-frontmatter.sh` | 11 agents have valid frontmatter (55 tests) |
| t05 | `tests/unit/t05-stage-files.sh` | 32 stages parse to slug + phase matching filename and directory (64 tests: 2 per stage) |
| t06 | `tests/unit/t06-skill-frontmatter.sh` | SKILL.md frontmatter valid (9 tests) |
| t07 | `tests/unit/t07-hook-audit-logger.sh` | Unit tests for audit-logger.ts via bun (16 tests) |
| t08 | `tests/unit/t08-hook-validate-state.sh` | Unit tests for validate-state.ts via bun (14 tests) |
| t09 | `tests/unit/t09-hook-log-subagent.sh` | Unit tests for log-subagent.ts via bun (8 tests) |
| t10 | `tests/unit/t10-hook-session-start.sh` | Unit tests for session-start.ts via bun (17 tests) |
| t11 | `tests/unit/t11-hook-statusline.sh` | Unit tests for aidlc-statusline.ts (62 tests) |
| t13 | `tests/unit/t13-hook-input-robustness.sh` | Adversarial input testing for all 9 hooks via bun (20 tests) |
| t14 | `tests/unit/t14-stage-content-validation.sh` | Validates content structure inside each of 32 stage files (160 tests) |
| t15 | `tests/unit/t15-knowledge-file-inventory.sh` | Validates knowledge file inventory and non-emptiness (~80 tests) |
| t16 | `tests/unit/t16-phase-rules-structure.sh` | Phase rules file structure validation (12 tests) |
| t17 | `tests/unit/t17-tool-state.sh` | Unit tests for aidlc-state.ts CLI tool (83 tests) |
| t18 | `tests/unit/t18-tool-audit.sh` | Unit tests for aidlc-audit.ts CLI tool (13 tests) |
| t19 | `tests/unit/t19-tool-jump.sh` | Unit tests for aidlc-jump.ts CLI tool (16 tests) |
| t20 | `tests/unit/t20-unit-workspace-scanner.sh` | Unit tests for the deterministic workspace scanner + --force semantics inside aidlc-utility init (21 tests) |
| t26 | `tests/unit/t26-delivery-agent-timeline-guardrail.sh` | Content guardrail — aidlc-delivery-agent surface must not use human-timeline framing (dynamic) |
| t27 | `tests/unit/t27-tool-utility.sh` | Unit tests for aidlc-utility.ts CLI tool (81 tests) |
| t28 | `tests/unit/t28-audit-event-sync.sh` | Validates audit event types are in sync between aidlc-audit.ts and audit-format.md (7 tests). See [State Machine](12-state-machine.md) for the canonical taxonomy this test guards. |
| t29 | `tests/unit/t29-hook-sync-statusline.sh` | Unit tests for sync-statusline.ts via bun (7 tests) |
| t30 | `tests/unit/t30-hook-session-end.sh` | Unit tests for session-end.ts hook (7 tests) |
| t31 | `tests/unit/t31-tool-log.sh` | Unit tests for aidlc-log.ts (decision, answer subcommands) (21 tests) |
| t33 | `tests/unit/t33-tool-bolt.sh` | Unit tests for aidlc-bolt.ts (start, complete, fail, set-autonomy) (25 tests) |
| t34 | `tests/unit/t34-tool-error-logged.sh` | Unit tests for ERROR_LOGGED emission via lib.ts emitError() across tool CLIs (11 tests) |
| t35 | `tests/unit/t35-tool-recovery-completed.sh` | Unit tests for RECOVERY_COMPLETED emission via acknowledge-compaction flow (11 tests) |
| t36 | `tests/unit/t36-utility-scope-change.sh` | Unit tests for /aidlc --scope <x> mid-workflow scope change (7 tests) |
| t37 | `tests/unit/t37-utility-doctor-drift.sh` | Unit tests for --doctor drift detection + graph-level checks (23 tests) |
| t38 | `tests/unit/t38-utility-status-gate-awareness.sh` | Unit tests for /aidlc --status gate awareness — who is the blocker (5 tests) |
| t46 | `tests/unit/t46-agent-no-numeric-stage-ids.sh` | Agent files reference stages by slug, not numeric ID (22 tests) |
| t60 | `tests/unit/t60-valid-scopes-derived.sh` | Scope validation derives from `scope-mapping.json`; fixture custom scope flow (9 tests) |
| t61 | `tests/unit/t61-agent-metadata-derived.sh` | Agent display name + examples derive from `.claude/agents/*.md` frontmatter (5 tests) |
| t62 | `tests/unit/t62-stage-schema.sh` | Stage frontmatter schema — 13 fields, types, enums, reserved keys (59 tests) |
| t63 | `tests/unit/t63-tool-graph.sh` | Unit tests for aidlc-graph.ts `artifactsRegistry()` + `artifacts` CLI (14 tests) |
| t64 | `tests/unit/t64-stage-parser.sh` | Unit tests for `parseStageFrontmatter` and `emitStageFrontmatter` (45 tests) |
| t67 | `tests/unit/t67-scope-table.sh` | aidlc-utility `scope-table` subcommand emission + `--check` drift guard + `detect-scope --from-text` keyword inference (28 tests) |
| t68 | `tests/unit/t68-version-changelog-sync.sh` | Validates `AIDLC_VERSION` in `version.ts` agrees with the latest `## [N.N.N]` heading + link reference in `CHANGELOG.md`, no duplicate headings, CLI output matches, and the `README.md` version badge matches `version.ts` (6 tests) |
| t69 | `tests/unit/t69-worktree-path.sh` | Behavioural contract for `worktreePath(projectDir, boltSlug)` — `.gitignore` anchored `/.aidlc/` entry, output absolute, output ends `/bolt-<slug>`, slug passes through unsanitised (4 tests) |
| t70 | `tests/unit/t70-worktree-kb-and-skill.sh` | v0.4.0 MR 7 KB and orchestrator wiring — `shared/rules-reading.md` + `branching-strategies.md` runbook structure; aidlc-pipeline-deploy-agent practices-loading position; SKILL.md per-Bolt Steps 0/0.5/6.5/6.75; halt-and-ask Verify-failed shape (14 tests) |
| t71 | `tests/unit/t71-markdown-section-helpers.sh` | Behavioural contract for `extractMarkdownSection` / `appendUnderHeading` / `replaceSection` in `lib.ts`; load-bearing for MR 8 practices-discovery cross-row promotion (12 tests) |
| t72 | `tests/unit/t72-worktree-info.sh` | v0.4.0 MR 12 — deterministic contract for `aidlc-worktree info --slug` halt-and-ask correlation lookup; pins JSON shape, most-recent semantics on multiple matching blocks, non-zero exit + stderr on miss/malformed (10 tests) |
| t76 | `tests/unit/t76-state-fork-merge.sh` | Behavioural contract for `aidlc-state.ts fork` / `merge` (v0.4.0 MR 9 state fork/merge) — byte-identical round-trip, slug validation, audit-first Parts A+B, alphabetical-slug tiebreak, idempotency, lock timeout, concurrent forks; B1/B2/M1 fold-in regressions (16 tests) |
| t77 | `tests/unit/t77-bolt-worktree-flags.sh` | v0.4.0 MR 11 — `aidlc-bolt.ts` worktree flag branches; atomicity ordering, complete 5-field envelope shape, abort sub-classifier, default-abort worktree preservation, regression guards (28 tests) |
| t79 | `tests/unit/t79-dispatch-event-validation.sh` | v0.4.0 MR 13 — `aidlc-bolt dispatch-event` subcommand contract for the three pre-registered MERGE_DISPATCH_* audit events; literal-per-branch `appendAuditEntry` calls (t48 invariant), per-variant flag validation, JSON envelope shape, audit-row schema fields per audit-format.md:147-149 (12 tests) |
| t80 | `tests/unit/t80-practices-runtime.sh` | v0.4.0 MR 13 — extractMarkdownSection regex edges (lib.ts:1081) + practices-event --type empty emit; pins helper behaviour for body-less section, comments-only body, trailing-whitespace headings, sub-heading collision; PRACTICES_SECTION_EMPTY emit via the new fourth case; post-merge fold-in: helper ignores `## Heading` lines inside fenced code blocks (7 tests) |
| t81 | `tests/unit/t81-bolt-plan-override.sh` | v0.4.0 MR 13 — discriminator-field disambiguation for PRACTICES_OVERRIDE (v5 §3a); pins that practices-event --type override accepts MR 13's full field set; t28 audit count stays at 55 (no new event); MR 8 write-failure path coexists with MR 13 marker-conflict path under the same event name (4 tests) |
| t82 | `tests/unit/t82-hold-merge-invariant.sh` | v0.4.0 MR 13 post-merge fold-in — HOLD-MERGE invariant tooling on aidlc-bolt.ts; pins hold-merge / release-merge subcommands set Merge-Held in the per-Bolt forked state file, complete --merge refuses with `reason:"merge-held"` envelope while held, refusal does not emit BOLT_COMPLETED, merge proceeds after release-merge, hold-merge errors when the Bolt has no per-Bolt forked state (10 tests) |
| t83 | `tests/unit/t83-doctor-orphan-worktree.sh` | v0.4.0 MR 15 doctor orphan-reconciliation family (Checks 1, 3, 4, 6) — orphan worktrees (incl. preserved-by-abort sub-classification), orphan state files, orphan audit (incl. PRACTICES_OVERRIDE Reason discriminator routing per audit-format.md:138 + ms-precision AFFIRMED reconciliation + unknown-Reason advisory), MERGE_DISPATCH_INVOKED pair-matched advisory pass=true (multi-INVOKED + 1 RETURNED reports 1 orphan); merged-and-cleaned Bolts do not flag (regression for terminal-short-circuit hoist); fail-clean on no-worktrees per issue 75 line 215 (16 tests) |
| t84 | `tests/unit/t84-doctor-stale-branch.sh` | v0.4.0 MR 15 doctor stale-branch detection (Check 2 per ROADMAP.md:143) — skips silently when not a git repo; flags `bolt-<slug>` branches whose worktree dir is gone but no terminal WORKTREE_DISCARDED/WORKTREE_MERGED audit row landed (5 tests) |
| t85 | `tests/unit/t85-doctor-practices-staleness.sh` | v0.4.0 MR 15 doctor practices-staleness check (Check 5 per MR 6 forward-note) — empty/template-default reads as never-affirmed; within `PRACTICES_STALENESS_DAYS` (90) passes ✓ with day count; beyond is advisory pass=true; invalid ISO 8601 string flagged readable; future-dated timestamp produces clock-skew advisory (6 tests) |
| t86 | `tests/unit/t86-sensor-manifest-schema.sh` | v0.5.0 MR 3 + MR 7b sensor manifest schema — pins filename↔id contract, `kind: deterministic` enum, `command:` canonical invocation prefix, `applies_to` ABSENCE (pull authoring), `default_severity`/`description` presence across the 4 framework manifests; legacy negative fixtures cover unknown-kind, applies_to-still-present, missing `id:` (28 tests) |
| t87 | `tests/unit/t87-stage-compartment-headers.sh` | v0.5.0 MR 5 — every stage file under `skills/aidlc/stages/` contains both `^## Sensors$` and `^## Learn$` H2 headings. Sentinel against future stage authors silently omitting compartments (64 tests) |
| t88 | `tests/unit/t88-parse-memory-headings.sh` | v0.5.0 MR 8 — `parseMemoryHeadings()` in `aidlc-lib.ts` counts entries under each of the four canonical §13 H2 headings (Interpretations / Deviations / Tradeoffs / Open questions). Pure function shared by MR 8's runtime-compile, MR 12's gate ritual, and MR 13's lifecycle. Covers empty input, mixed bullets/prose/ISO lines, fenced-code/blockquote/HTML-comment exclusion, non-canonical-heading termination, CRLF/BOM tolerance, exact-match heading strictness (18 tests) |
| t94 | `tests/unit/t94-sensor-fire-hook-unit.sh` | v0.5.0 MR 10 — PostToolUse Write|Edit hook `aidlc-sensor-fire.ts` 12-step flow. Asserts TTY/stdin-parse/empty-path guards, `.aidlc-sensors/` recursion guard, audit + state-existence pre-init guards, Test Run Mode skip (sensor-fire.skipped append), heartbeat ISO-timestamp shape, missing/`none` Current Stage early-exit, missing stage-graph + stage-not-in-graph guards, empty `sensors_applicable` (workspace-scaffold), and G1 lock-in (entries without `matches` do not fire) (18 tests) |
| t96 | `tests/unit/t96-runtime-fragment-primitives.sh` | v0.5.0 MR 11 — `aidlc-runtime fragment-fork` / `fragment-merge` primitives; asserts fragment-fork happy path + source-absent fallback + one-shot guard + worktree-missing guard + slug validation; fragment-merge happy path + idempotent fragment-absent path + slug validation + defensive fragment-absent on missing worktree; --help lists both subcommands; --project-dir plumbing in spawnSibling-style invocation order (B1 prerequisite for the bolt-start wiring) (14 tests) |
| t97 | `tests/unit/t97-learnings-primitives.sh` | v0.5.0 MR 12 — `aidlc-learnings.ts` primitives + new `parseMemoryEntries` parser (one-entry-per-counted-line, `length === parseMemoryHeadings.total` invariant); subcommand contract (`--help`, unknown → 2, missing flags → 1); `surface` partition (candidates vs parked open questions, test-run skip, slug-not-Active → 1); `persist` (project/team scope routing + cid-marker idempotency, two-write sensor bind, framework-tier rejection, free-text source tagging, recovery, false-negative guard, test-run skip) (32 tests) |
| t100 | `tests/unit/t100-memory-template-lifecycle.sh` | v0.5.0 MR 13 — per-stage `memory.md` template structure + parser-safety + `aidlc-state.ts` advance/approve `memory_path` JSON key; asserts the template exists with the four canonical `## ` H2 headings (lowercase-q `## Open questions`, column 0, no stray heading), a verbatim blockquote ownership header, and single-line HTML-comment seed examples so `parseMemoryHeadings(template)` returns `total === 0`; append one bullet → `total === 1`; `advance` JSON carries `memory_path === aidlc-docs/<phase>/<slug>/memory.md` (forward-slash, relative) and `approve` inherits it via `handleAdvance` delegation (19 tests) |
| t103 | `tests/unit/t103-doctor-rule-drift-coverage.sh` | v0.5.0 MR 14 — doctor rule-drift + paired-coverage primitives; asserts `loadRules()` surfaces `frontmatter.pairing` (consumer) + `validateRuleFrontmatter` rejects bad shapes; `parseRuleHeadings` (private in `aidlc-graph.ts`, surfaced via `RuleFile.headings`) splits `## ` bodies and skips fenced / blockquote / single-line AND multi-line `<!-- -->` comments (`## Corrections` multi-line-comment-only → empty); `.headings` is the `AIDLC_RULES_DIR` read seam; rule-drift detect (populated org `## Testing Posture` overlap, empty-/absent-org no-overlap, `*-learnings.md` participation); paired-coverage prefix-strip, unpaired ghost, feedforward-only in X, M-X=0 branch, determinism (19 tests) |
| t110 | `tests/unit/t110-mcp-server-grants.sh` | MCP registry integrity + the inheritance access model — `.mcp.json` exists and is valid JSON; declares exactly the 5 expected public servers (`context7`, `aws-mcp`, `aws-pricing`, `aws-iac`, `aws-serverless`) as the sole top-level key whose value is a non-null object (no 6th entry, no stray sibling key, no array/null shape); `threat-composer-ai` is intentionally absent (deferred); each server's config shape is usable (context7 is `type: http` with a url + `CONTEXT7_API_KEY` header; each aws-* is `command: uvx` with a non-empty args array whose first element is the expected `<pkg>@latest`, and aws-mcp carries `AWS_REGION=us-east-1`); no committed secrets (every credential-position header value is a `${VAR}` placeholder and no high-entropy/literal-key shape appears anywhere); and the inheritance invariant — no agent carries a bare `mcp__<server>` grant token, and every fully-qualified `mcp__<server>__<tool>` entry names a declared server (servers are inherited, not per-agent-granted; bare tokens are no-ops; fully-qualified restriction entries are permitted but must reference a live server). Deterministic, bun-only (no `jq`) (32 tests) |

### Feature Tests

| Test ID | File | Description |
|---------|------|-------------|
| t12 | `tests/feature/t12-state-fixture-validation.sh` | Meta-test — verify fixture state files match real template structure (20 tests) |
| t30 | `tests/feature/t30-scope-stage-mapping.sh` | Scope-to-Stage Mapping consistency — SKILL.md compiled-table region shape + per-scope EXECUTE count matches `scope-mapping.json` (17 tests) |
| t31 | `tests/feature/t31-help-text-consistency.sh` | Help text compiled by `renderHelpText()` from `scope-mapping.json`; stage counts stay fresh (19 tests) |
| t32 | `tests/feature/t32-stage-graph-consistency.sh` | Cross-reference Stage Graph table in SKILL.md against actual stage files |
| t33 | `tests/feature/t33-hook-concurrency.sh` | Test audit-logger lock contention under parallel writes |
| t34 | `tests/feature/t34-stage-protocol-structure.sh` | Stage protocol structure and cross-reference validation |
| t35 | `tests/feature/t35-stage-protocol-recovery.sh` | Stage protocol recovery and change handling validation |
| t36 | `tests/feature/t36-stage-protocol-governance.sh` | Stage protocol governance and phase boundary validation |
| t37 | `tests/feature/t37-stage-protocol-compliance.sh` | Cross-file protocol compliance — every stage references protocol, state template fields match sed commands, knowledge dirs match agents |
| t38 | `tests/feature/t38-stage-agent-cross-check.sh` | Cross-check Lead Agent in each stage file against Stage Graph table in SKILL.md (32 tests) |
| t39 | `tests/feature/t39-scope-stage-count-validation.sh` | For each of 9 scopes, read EXECUTE counts from scope-mapping.json and verify ranges (9 tests) |
| t39 | `tests/feature/t39-per-scope-phase-sequence.sh` | Per-scope phase sequence test — 9 scopes, data-driven assertions on phase ordering (27 tests) |
| t40 | `tests/feature/t40-settings-hook-config.sh` | Validate settings.json hook configuration (6 tests) |
| t41 | `tests/feature/t41-jump-flag-validation.sh` | Validate SKILL.md handler structure for --stage/--phase/--scope (32 tests) |
| t42 | `tests/feature/t42-state-jumped-fixture.sh` | Validate state-jumped.md fixture structure (12 tests) |
| t43 | `tests/feature/t43-stage-io-contracts.sh` | Stage I/O contract chain — verify inputs/outputs chain between stages (19 tests) |
| t44 | `tests/feature/t44-stage-instruction-completeness.sh` | Stage instruction completeness — verify steps describe how to produce declared outputs (41 tests) |
| t45 | `tests/feature/t45-stage-output-validation.sh` | Feature test — deterministic validation that stage file outputs are referenced in Steps |
| t47 | `tests/feature/t47-construction-bolts.sh` | Construction Bolt-by-Bolt flow — vocabulary, audit events, state field, and Glossary (15 tests) |
| t48 | `tests/feature/t48-audit-event-emitters.sh` | Drift test for audit event taxonomy — every emitter-registry row matches an emission call site (16 tests) |
| t49 | `tests/feature/t49-state-machine-lifecycle.sh` | Walk through the full stage lifecycle `[ ] → [-] → [?] → [R] → [?] → [x]` via state-tool commands (14 tests) |
| t52 | `tests/feature/t52-drift-meta-validation.sh` | Meta-test — verify t48 actually catches each failure class it claims to guard (5 tests) |
| t54 | `tests/feature/t54-compaction-and-test-run.sh` | Structural assertions for compaction-awareness flow and --test-run terminal state (8 tests) |
| t55 | `tests/feature/t55-test-suite-drift.sh` | Drift guard for test-suite metadata — `plan N` vs header `(N tests)` vs `tests/README.md` vs `docs/reference/09-testing.md`, plus path + version-marker drift sweep (6 tests) |
| t65 | `tests/feature/t65-stage-file-migration.sh` | All 32 stage files parse + validate against MR 5 schema, produces/consumes integrity, round-trip, topo-sort (22 tests) |
| t66 | `tests/feature/t66-graph-library.sh` | aidlc-graph.ts 8-function library + CLI — compile, traversal, parity, env-seam + designer-export `--check` drift guard + `rules_in_context` resolution (MR 7a) + `sensors_applicable` resolution (MR 7b) + `withAuditLock` reentrancy guards (88 tests) |
| t75 | `tests/feature/t75-practices-promote.sh` | Behavioural contract for `aidlc-state.ts practices-promote` — section-replace on `team.md`, append-with-date-stamp on project-guardrails.md, atomicity (guardrails-first), partial-draft tolerance, idempotency, fail-closed on missing draft/target with `PRACTICES_OVERRIDE` emit (24 tests) |
| t76 | `tests/feature/t76-halt-and-ask-prose-shape.sh` | v0.4.0 MR 12 + MR 13 — line-anchored prose-shape contract for halt-and-ask across SKILL.md, stage-protocol.md, branching-strategies.md, aidlc-pipeline-deploy-agent.md; pins slug-derivation paragraph, visible-vs-no-worktree subheading carve-out, AUQ template `[path]`/`[branch_name]` interpolation, Skip/Abort same-line preservation phrasing, sibling-doc cross-link, MR 13 italic carve-outs for prefix-hash failure mode + orphan-BOLT_STARTED recovery seam (15 tests) |
| t78 | `tests/feature/t78-bolt-worktree-lifecycle.sh` | v0.4.0 MR 11 — end-to-end Bolt-with-worktree lifecycle (Issue 75 line 216): start --worktree → complete --merge round-trip with canonical 6-event audit sequence; abort --discard tear-down (BOLT_FAILED + directory removed) vs abort-without-discard preservation; two parallel-batch Bolts cleanly round-trip without state interference (13 tests) |
| t88 | `tests/feature/t88-compile-rules-in-context.sh` | v0.5.0 MR 7a + MR 7b — strict-additive rule resolution at compile (pull authoring) via 5 fixture sub-dirs (org-only, org-team-project, all-four, pairing-feedforward-only, bom-frontmatter); asserts per-stage `rules_in_context` shape across full subset, `pairing` schema accept/reject, BOM-prefixed frontmatter parsing, `--check` drift, round-trip determinism (11 tests) |
| t89 | `tests/feature/t89-compile-sensors-applicable.sh` | v0.5.0 MR 7b — pull-authoring sensor resolution at compile via 11 fixture sub-dirs; asserts per-stage `sensors_applicable` resolution + `matches` passthrough + compile-snapshot semantics + schema rejections + FIELD_ORDER positioning + round-trip determinism + `--check` drift on sensor-manifest edits (22 tests) |
| t90 | `tests/feature/t90-runtime-compile.sh` | v0.5.0 MR 8 — `aidlc-runtime.ts compile` walks audit + memory.md to materialise `runtime-graph.json`. Asserts approved/pending pairing, re-jump, v0.4.0-backfill, MEMORY_EMPTY emit + --test-run propagation, byte-equivalent re-compile, missing state.md skip, approved+non-zero negative case, ISO-second collision determinism, --init --force re-init filtering, re-emit suppression (exactly one per (slug, gate-completion)), re-approve still-empty → fresh emit, schema nullable on instance-bearing rows (29 tests) |
| t91 | `tests/feature/t91-runtime-compile-hook.sh` | v0.5.0 MR 8 — PostToolUse Bash hook `aidlc-runtime-compile.ts`; asserts dispatch on GATE_APPROVED, terminal-WORKFLOW via WORKFLOW_COMPLETED, gate-start via STAGE_AWAITING_APPROVAL, command-regex skip, recursion guard (standalone and composite), no-transition skip, TTY/empty-stdin and malformed-JSON guards, Test-Run propagation (13 tests) |
| t92 | `tests/feature/t92-sensor-fire.sh` | v0.5.0 MR 9 — behavioural contract for `aidlc-sensor.ts fire`; asserts argv validation, PASSED + FAILED round-trip per sensor with findings-count derivation, tool-unavailable + script-error → PASSED + Note, budget override → SENSOR_BUDGET_OVERRIDE, concurrency (lock A + B + orphan recovery), detail-file body shape + Fire-id-keyed paths, audit-row required-fields per event type, manifest `command:` resolution, validation order, upstream-coverage `--consumes` via `loadGraph()`. Groups B/C/F-defensive use REAL fixtures under `tests/fixtures/v05-mr9-sensor-fire/` (passing-markdown, failing-required-sections, failing-upstream-coverage, passing-typescript, failing-linter, failing-type-check, slow-command) so the four shipped per-sensor scripts are exercised against authentic markdown + TS inputs (43 tests) |
| t93 | `tests/feature/t93-sensor-list-describe.sh` | v0.5.0 MR 9 (rows updated by MR 10) — behavioural contract for `aidlc-sensor.ts` read-only subcommands; asserts `list` deterministic alpha order across 4 framework sensors, per-sensor `describe` field shape (markdown sensors include `matches: **/aidlc-docs/**` post-MR-10 G1.5; ts/tsx sensors include `matches: **/*.{ts,js}` and `matches: **/*.{ts,tsx}`), `describe <unknown-id>` exits non-zero with known-ids hint, `--help`/`-h` prints usage, no-subcommand exits non-zero with usage hint (12 tests) |
| t95 | `tests/feature/t95-sensor-fire-hook-feature.sh` | v0.5.0 MR 10 — end-to-end behaviour for `aidlc-sensor-fire.ts` against a mock dispatcher. Asserts argv shape (`fire <id> --stage <slug> --output-path <path>`), single-entry + multi-entry fire, multi-glob per stage (TS write fires only code sensors / markdown write fires only doc-shape sensors at the same Construction stage), glob-filter selection across mixed entries, subprocess timeout → SIGTERM-recorded `recordHookDrop` (uses a patched-timeout fast-fixture copy of the hook), subprocess exit 1 → dispatcher-exit drop, exit-code contract (no `{decision: block}`), heartbeat mtime advances on sequential calls, `sensor-fire.skipped` accumulates ISO-timestamped lines under Test Run Mode (19 tests) |
| t96 | `tests/feature/t96-runtime-instances-compile.sh` | v0.5.0 MR 11 — `aidlc-runtime compile` `instances[]` populator. Asserts single-Bolt → no instances[]; 3-Bolt parallel → instances[].length=3 with parent fields nulled per L5/L10 + memory_path kept; outcome rollup (all approved → approved; any failed → failed; pending mix → pending); alphabetical-by-slug ordering with shuffled STATE_FORKED Timestamps; determinism on re-compile; MR-11 contract (sensor_firings:[], memory_entries:null, memory_breakdown:null on every BoltInstance) (10 tests) |
| t98 | `tests/feature/t98-sensor-firings-populator.sh` | v0.5.0 MR 12 — `aidlc-runtime compile` `sensor_firings[]` + `learnings_captured` populators. Asserts fire_id pairing (passed/failed+detail_path/budget-override), orphan handling (closed → incomplete; open past 60s → incomplete; open under 60s → omitted; cutoff from baseline_ts, no wall-clock), 4-parallel interleaved pairing, ts-ascending sort, byte-equal re-compile; BoltInstance attribution (per-instance + worktree-scoped not double-counted on parent); `learnings_captured` (approved → {from_orchestrator, from_user_addition}, pending → null, instance-bearing parent → null); 4-state enum + fire_id invariant (16 tests) |
| t104 | `tests/feature/t104-doctor-rule-drift.sh` | v0.5.0 MR 14 — real `/aidlc --doctor` rule-drift row rendering against `AIDLC_RULES_DIR` fixtures; asserts the N=1 headline `Rule drift: 1 team/project rule(s) overlap org policy (review for contradiction)`, detail carries file + `## Testing Posture` + quoted org sentence, `✓` advisory render (never pushes failed), N=0 quiet render, org-absent informational pass, fixture isolation (fixture posture drives N=1 — `.headings` read seam end-to-end) (6 tests) |
| t105 | `tests/feature/t105-doctor-paired-coverage.sh` | v0.5.0 MR 14 — real `/aidlc --doctor` paired-coverage row + `GUARDRAIL_LOADED` emit pin; asserts the exact `P/(M-X)` label (`1/2 guardrails paired (1 feedforward-only)`), unpaired detail (`unpaired: … → aidlc-ghost (no stage binds it)`), `✓` advisory render, `GUARDRAIL_LOADED` row in `aidlc-docs/audit.md` with Scope/Path/Rule count fields, and the no-`pairing` M-X=0 branch still emitting `GUARDRAIL_LOADED` (6 tests) |
| t106 | `tests/feature/t106-runtime-summary.sh` | `aidlc-runtime.ts summary` deterministic aggregate over `runtime-graph.json`; asserts stage-outcome tallies (approved/failed/pending), per-phase rollup keyed by stage-graph phase, memory-entry aggregation by canonical category, `duration_minutes` (start → latest completed; null when pending-only), `--json` determinism, human-readable header render, missing-graph → exit 1 (13 tests) |
| t107 | `tests/feature/t107-session-skills-readonly.sh` | Read-only session skills (session-cost / replay / outcomes-pack); asserts each `SKILL.md` exists, declares `name` + `user-invocable: true` + `classification: read-only`, sources numbers from `aidlc-runtime.ts summary --json`, carries no retired token heuristic, emits no audit / no state advance, only outcomes-pack writes a file (24 tests) |
| t111 | `tests/feature/t111-session-skills-contract.sh` | Behavioural contract between the session skills and the `aidlc-runtime.ts summary --json` data plane; compiles a synthetic graph, then asserts the tool emits the 8 top-level keys the skills depend on, every dotted field the skills reference resolves in real tool output (phantom/renamed-field guard), and every emitted scalar is consumed by at least one skill (dark-field guard) (10 tests) |

### Integration Tests

| Test ID | File | Description |
|---------|------|-------------|
| t19 | `tests/integration/t19-preflight-health.sh` | Preflight health check — validates Claude CLI before integration tests |
| t20 | `tests/integration/t20-integration-status.sh` | Integration test for /aidlc --status (7 tests) |
| t21 | `tests/integration/t21-integration-init.sh` | Integration test for /aidlc --init — first run (10 tests) |
| t21b | `tests/integration/t21b-integration-init-idempotent.sh` | Integration test for /aidlc --init — --force semantics (6 tests) |
| t22 | `tests/integration/t22-integration-doctor.sh` | Integration test for /aidlc --doctor (10 tests) |
| t23 | `tests/integration/t23-integration-help.sh` | Integration test for /aidlc --help (6 tests) |
| t24 | `tests/integration/t24-integration-stage-jump.sh` | Integration test — forward --stage jump via claude CLI (12 tests) |
| t25 | `tests/integration/t25-integration-phase-jump.sh` | Integration test — backward --phase jump via claude CLI (6 tests) |
| t26 | `tests/integration/t26-integration-backward-jump.sh` | Integration test — backward jump via claude CLI (8 tests) |
| t27 | `tests/integration/t27-integration-depth-override.sh` | Integration test — --depth flag override via claude CLI (7 tests) |
| t28 | `tests/integration/t28-integration-test-strategy.sh` | Integration test — --test-strategy flag via claude CLI (6 tests) |
| t29 | `tests/integration/t29-integration-env-scope.sh` | Integration test — AWS_AIDLC_DEFAULT_SCOPE env var via claude CLI (5 tests) |
| t45 | `tests/integration/t45-revision-loop.sh` | Integration test — gate → reject → revise → gate cycle on a gated stage (10 tests) |
| t46 | `tests/integration/t46-parallel-bolt.sh` | Parallel-bolt concurrency test — 5 processes racing on audit.md (5 tests) |
| t47 | `tests/integration/t47-failure-injection.sh` | Failure-injection test — chaos conditions the state machine must handle without data loss (8 tests) |
| t48 | `tests/integration/t48-runtime-graph-end-to-end.sh` | v0.5.0 MR 8 — runtime-graph compile end-to-end against a real `bugfix` workflow; asserts pre-approve pending → post-approve approved transition, ≥2 rows after first approve, v0.4.0 backfill, byte-equivalent re-compile (10 tests) |
| t49 | `tests/integration/t49-bolt-sensor-failures.sh` | v0.5.0 MR 11 — end-to-end real-tool flow for Bolt fork/merge runtime-graph + parallel instances[] + failure modes; asserts 3-Bolt parallel batch → instances[auth, cart, pay] alphabetical, sensors are advisory (synthesized SENSOR_FAILED in pay's worktree audit propagates to main on audit-merge but all instances stay outcome:approved), MR-11 contract under live SENSOR_FAILED, Bolt failure rollup (pay BOLT_FAILED + abort --discard → instance pay:failed + parent:failed), idempotent re-merge (state-merge errors first), lock-acquire failure ordering (planted lock-dir + AIDLC_AUDIT_LOCK_RETRIES=1 → fragment-merge never reached), soft-gap closure (fragment-merge fails after audit-merge succeeds → BOLT_COMPLETED → STATE_MERGED → AUDIT_MERGED → BOLT_FAILED partial-success audit signature), determinism under failure mix (8 tests) |
| t99 | `tests/integration/t99-learnings-gate-flow.sh` | v0.5.0 MR 12 — §13 learning-gate end-to-end (surface → simulated-AUQ glue → persist); asserts mixed-memory surface → project + team learnings + 2 audit rows, test-run skip, sensor proposal → manifest + `aidlc-graph compile` binds the id into `sensors_applicable` (two-write install) + `SENSOR_PROPOSED` Destinations array, admission conflict-check with stubbed verdict (reject no-writes / escalate writes through), idempotent re-run, concurrent persist serialises to exactly one row + line, recovery re-writes line + skips emit, glue label↔candidate_id mapping + §13 fossil sweep (16 tests) |
| t102 | `tests/integration/t102-memory-roundtrip.sh` | v0.5.0 MR 13 — `memory.md` producer → MR 8 runtime-compile round-trip (scripted, deterministic); asserts a stage's `memory.md` is created from the real template at start (4 headings, total 0), after N real entries + approval the compile records `memory_entries === N` with breakdown summing to N, a template-only approved stage emits one `MEMORY_EMPTY` while N≥1 entries emit none, the file persists across a second compile, and an absent `memory.md` compiles to `memory_entries: null` with no `MEMORY_EMPTY` (no-storm backfill) (6 tests) |

### Stage Tests

| Test ID | File | Description |
|---------|------|-------------|
| t70 | `tests/stage/t70-stage-workspace-detection-greenfield.sh` | Stage test — workspace detection classifies greenfield stub (8 assertions, 25 turns) |
| t71 | `tests/stage/t71-stage-workspace-detection-brownfield.sh` | Stage test — workspace detection classifies brownfield stub (10 assertions, 25 turns) |
| t72 | `tests/stage/t72-stage-reverse-engineering.sh` | Stage test — reverse engineering on brownfield stub (15 assertions, 25 turns) |
| t73 | `tests/stage/t73-stage-intent-capture.sh` | Stage test — intent capture with greenfield stub (12 assertions, 25 turns) |
| t74 | `tests/stage/t74-stage-requirements-analysis.sh` | Stage test — requirements analysis with brownfield stub + RE artifacts (12 assertions, 25 turns) |
| t101 | `tests/stage/t101-stage-memory-lifecycle.sh` | v0.5.0 MR 13 — per-stage `memory.md` start→approval lifecycle on a gated stage; asserts init-from-template at stage start (four canonical headings, verbatim blockquote ownership header), logged observation carries an ISO-8601 prefix under a canonical heading, persist-on-approval (no cleanup), idempotent re-entry, `parseMemoryHeadings` ↔ disk agreement, and the hook-fired runtime-compile read seam carries `memory_path`; LLM-output-dependent assertions skip on timeout or copy-approximation (8 assertions) |

### Worktree Tests

L2 tier without LLM dependency. Fires after the preflight gate so a missing `claude` CLI doesn't skip it. Tests exercise `git worktree`-related primitives: fixture creation via `mktemp + git init`, worktree-list assertions, idempotent cleanup, and the `aidlc-worktree` CLI's create/merge/discard/list/verify subcommands. v0.4.0 Wave 1 MR 3 landed the tier infrastructure + the helpers meta-test; v0.4.0 MR 7 added five tool-exercising tests (t02-t06); v0.4.0 MR 10 added one audit-fork/merge test (t07).

| Test ID | File | Description |
|---------|------|-------------|
| t01 | `tests/worktree/t01-helpers.sh` | Meta-test for `tests/lib/worktree-helpers.sh` — fixture creation, worktree assertions, defence-in-depth path guard, idempotent cleanup (7 tests) |
| t02 | `tests/worktree/t02-worktree-create.sh` | `aidlc-worktree create` — happy path emits `WORKTREE_CREATED` and registers worktree on `bolt-<slug>` branch; pre-audit guards reject bad slug, missing base branch, double-create on same slug; 3 parallel creates with distinct slugs all succeed (15 tests) |
| t03 | `tests/worktree/t03-worktree-merge.sh` | `aidlc-worktree merge` — squash strategy emits `WORKTREE_MERGED` and removes the worktree; defensive HEAD check rejects merge from wrong branch; conflict envelope shape (`status`/`detail` + `conflict_files` lists the actual conflicting path via `git diff --diff-filter=U`) with worktree preserved; rebase strategy errors when no remote configured (13 tests) |
| t04 | `tests/worktree/t04-worktree-discard-list-verify.sh` | `aidlc-worktree discard` removes the worktree + branch and emits `WORKTREE_DISCARDED`; idempotent on already-gone slugs; `list` filters to `bolt-*` worktrees only; `verify` exits 0 when the matching event is fresh, non-zero with `absent` reason when missing, non-zero with `stale` reason when older than `--max-age-seconds` (12 tests) |
| t05 | `tests/worktree/t05-worktree-audit-first.sh` | Audit-first invariant — Part A: chmod `audit.md` to read-only, create exits non-zero pre-git with no worktree directory created and no `WORKTREE_CREATED` row in audit.md. Part B: induce git-time failure post-audit (chmod parent dir read-only); `WORKTREE_CREATED` audit-of-intent row landed before git failure, `ERROR_LOGGED` row appended with `[slug=<slug>]` for doctor correlation (7 tests) |
| t06 | `tests/worktree/t06-worktree-sibling-rejection.sh` | `aidlc-worktree` refuses to run from inside a sibling worktree (Construction's `.aidlc/worktrees/bolt-*` are siblings of the main checkout, not nested); error message names the main-checkout requirement (3 tests) |
| t07 | `tests/worktree/t07-audit-fork-merge.sh` | `aidlc-audit audit-fork` / `audit-merge` primitive — fork creates byte-identical worktree audit + AUDIT_FORKED in both audits with matching Fork Boundary; merge appends delta + AUDIT_MERGED in main only; edge cases (empty delta, missing aidlc-docs subdir auto-created, missing main audit fails loud, prefix-hash mismatch refusal, lock contention via 50ms-staggered N=2 mergers, lock-timeout failure path with planted stuck lock, 65-char slug rejected with length error, post-emit failure ERROR_LOGGED carries [fork-emitted:<iso-ts>] for doctor correlation); property — N=4 alphabetical / reverse-alphabetical / same-second-timestamps / one-empty-delta scenarios all preserve per-Bolt fork→merge bracket order in the merged main audit (31 tests) |
| t09 | `tests/worktree/t09-halt-and-ask-preservation.sh` | v0.4.0 MR 12 — halt-and-ask preserves the worktree on simulated `BOLT_FAILED`; pins on-disk persistence, `Bolt slug` field correlation, zero-discard invariant, info still resolves (8 tests) |
| t10 | `tests/worktree/t10-halt-and-ask-discard.sh` | v0.4.0 MR 12 — explicit `aidlc-worktree discard --slug` cleans up: directory gone, `WORKTREE_DISCARDED` with `Reason: agent-discard`, idempotent second discard, info still resolves from audit (8 tests) |
| t11 | `tests/worktree/t11-halt-and-ask-retry-correlation.sh` | v0.4.0 MR 12 — retry-then-fail correlation: `info` returns same path across multiple `BOLT_FAILED` emits, exactly one `WORKTREE_CREATED` (retry doesn't re-create), worktree preserved across multiple failures (6 tests) |
| t12 | `tests/worktree/t12-bolt-runtime-graph-fork.sh` | v0.5.0 MR 11 — Bolt runtime-graph fork/merge round-trip + parallel batch + abort-discard. Three scenarios: (a) single-Bolt round-trip (fragment created on start --worktree, removed on complete --merge, no instances[] on compile per L5 ≥2 threshold); (b) 3-Bolt parallel batch in non-alphabetical start order → instances[] always alphabetical [auth, cart, pay] regardless of merge order, all 3 fragments removed; (c) abort --discard removes worktree + fragment transitively, abort without --discard preserves both, manual aidlc-worktree discard cleans up the orphan via git worktree remove (defense-in-depth) (9 tests) |

### Workflow Tests

| Test ID | File | Description |
|---------|------|-------------|
| t50 | `tests/workflow/t50-workflow-bugfix-scope.sh` | Workflow test — bugfix scope full lifecycle via --test-run (24 tests) |
| t51 | `tests/workflow/t51-workflow-poc-scope.sh` | Workflow test — POC scope via --test-run (19 tests) |
| t51 | `tests/workflow/t51-bugfix-event-parity.sh` | End-to-end event parity test for the bugfix scope — full audit stream vs expected (15 tests) |
| t52 | `tests/workflow/t52-workflow-state-progression.sh` | Workflow test — state file progression during bugfix (10 tests) |
| t53 | `tests/workflow/t53-workflow-scope-routing.sh` | Workflow test — bugfix scope routing (skip Ideation) (11 tests) |
| t54 | `tests/workflow/t54-workflow-audit-completeness.sh` | Workflow test — audit trail completeness during bugfix (10 tests) |
| t55 | `tests/workflow/t55-workflow-init-then-resume.sh` | Workflow test — two-phase: --init then bugfix --test-run resume (8 tests) |
| t56 | `tests/workflow/t56-workflow-forward-jump.sh` | Workflow test — forward jump + auto-init with --test-run (8 tests) |
| t57 | `tests/workflow/t57-workflow-backward-jump.sh` | Workflow test — backward jump + replay with --test-run (5 tests) |
| t58 | `tests/workflow/t58-workflow-workshop-scope.sh` | Workflow test — workshop scope routing (skip Ideation) (14 tests) |
| t59 | `tests/workflow/t59-workflow-depth-override.sh` | Workflow test — depth override persists through bugfix workflow (6 tests) |
| t60 | `tests/workflow/t60-construction-worktrees-enterprise.sh` | v0.4.0 MR 13 — Construction-worktrees per-scope contract for enterprise; scope-mapping + SKILL.md prose surfaces + dispatch-event + skeleton stance (9 tests) |
| t61 | `tests/workflow/t61-construction-worktrees-feature.sh` | v0.4.0 MR 13 — Construction-worktrees per-scope contract for feature (skeleton-on, practices-discovery EXECUTE) (9 tests) |
| t62 | `tests/workflow/t62-construction-worktrees-mvp.sh` | v0.4.0 MR 13 — Construction-worktrees per-scope contract for mvp; exercises FALLBACK observability (9 tests) |
| t63 | `tests/workflow/t63-construction-worktrees-poc.sh` | v0.4.0 MR 13 — Construction-worktrees per-scope contract for poc (skeleton-on, practices-discovery SKIP); exercises PRACTICES_SECTION_EMPTY advisory (9 tests) |
| t64 | `tests/workflow/t64-construction-worktrees-workshop.sh` | v0.4.0 MR 13 — Construction-worktrees per-scope contract for workshop (multi-engineer parallel scenario); pins workshop-resume + Merge-Held-marker resume-persistence (9 tests) |
| t65 | `tests/workflow/t65-construction-worktrees-bugfix.sh` | v0.4.0 MR 13 — Construction-worktrees per-scope contract for bugfix (skeleton-off, practices-discovery SKIP) (8 tests) |
| t66 | `tests/workflow/t66-construction-worktrees-refactor.sh` | v0.4.0 MR 13 — Construction-worktrees per-scope contract for refactor (skeleton-off, practices-discovery SKIP) (8 tests) |
| t67 | `tests/workflow/t67-construction-worktrees-security-patch.sh` | v0.4.0 MR 13 — Construction-worktrees per-scope contract for security-patch (skeleton-off, practices-discovery SKIP) (8 tests) |

## Trigger Points

| Trigger | Layer | Command | Where |
|---------|-------|---------|-------|
| `git commit` | L1 | `bash tests/run-tests.sh` | Local (pre-commit hook) |
| CI pipeline | L2 | `bash tests/run-tests.sh --ci` | CI/CD pipeline |
| Release / merge to main | L3 | `bash tests/run-tests.sh --release` | CI/CD pipeline |

L1 can be enforced via a git pre-commit hook: `bash tests/run-tests.sh || exit 1`.

## Stubs

### Greenfield Stub: `tests/fixtures/greenfield-todo/`

A project description with no source code. Workspace-detection classifies as greenfield. Gives the LLM deterministic intent context for ideation stages.

Contents: Just `README.md` describing a React Todo App with TypeScript and Vite.

### Brownfield Stub: `tests/fixtures/brownfield-todo/`

Minimal React+TypeScript+Vite source (~10 files, ~200 LOC). Workspace-detection classifies as brownfield. RE, requirements, and design stages have concrete code to analyze.

Contents:
- `package.json` — react, react-dom, typescript, vite, vitest
- `tsconfig.json`, `vite.config.ts`, `index.html`
- `src/main.tsx`, `src/App.tsx`
- `src/types/todo.ts` — Todo interface (id, title, completed)
- `src/components/TodoList.tsx` — list + add form (~40 lines)
- `src/components/TodoItem.tsx` — checkbox + title + delete button
- `src/hooks/useTodos.ts` — addTodo, toggleTodo, deleteTodo

### RE Artifacts Fixture: `tests/fixtures/re-artifacts/`

Pre-seeded reverse-engineering output for downstream stage tests. Copied into `$PROJ/aidlc-docs/inception/reverse-engineering/` during setup.

Contents: 4 minimal .md files (architecture-overview, technology-stack, codebase-analysis, integration-points) describing the brownfield-todo app.

### Inception Artifacts Fixture: `tests/fixtures/inception-artifacts/`

Pre-seeded inception phase output for tests that jump into construction. Copied into `$PROJ/aidlc-docs/inception/{requirements-analysis,application-design,units-generation}/` during setup.

Contents: 7 minimal .md files (requirements, components, component-methods, services, component-dependency, unit-of-work, unit-of-work-story-map) describing the Todo app. Unit name: `todo-core`.

### Construction Artifacts Fixture: `tests/fixtures/construction-artifacts/`

Pre-seeded construction phase output for tests that jump to mid-construction stages (e.g., code-generation). Copied into `$PROJ/aidlc-docs/construction/todo-core/functional-design/` during setup.

Contents: 1 minimal .md file (functional-design) describing the todo-core unit's component specs and state management.

## State Fixtures

| Fixture | Project Type | Scope | State | Used By |
|---------|-------------|-------|-------|---------|
| `state-pre-workspace-detection.md` | -- | feature | Welcome+scaffold done, workspace-detection next | t70, t71 |
| `state-initialization-done.md` | Greenfield | feature | Init done, intent-capture next | t73 |
| `state-brownfield-init-done.md` | Brownfield | bugfix | Init done, RE next | t72 |
| `state-mid-inception.md` | Brownfield | bugfix | RE done, requirements-analysis next | t74 |
| `state-mid-ideation.md` | Greenfield | feature | Intent+market done, feasibility next | t08, t10, t11, t12, t20, t22, t24, t25, t37 |
| `state-construction.md` | -- | -- | Construction phase | t07, t10, t11, t26, t57 |
| `state-operation.md` | -- | -- | Operation phase | t07, t10, t11 |
| `state-completed.md` | -- | -- | All stages done | t08, t11 |
| `state-jumped.md` | Brownfield | bugfix | Mid-workflow with jump history | t11, t37, t42 |
| `state-corrupted.md` | -- | -- | Invalid/corrupted state | t08, t10 |

## How to Add a Stage Test

1. Choose the stage to test and identify what state fixture it needs (the state must show that stage as the current/next stage)
2. Create or reuse a state fixture in `tests/fixtures/`
3. Create `tests/stage/tNN-stage-SLUG.sh`:

```bash
#!/bin/bash
# tNN: Stage test — SLUG (N assertions, M turns)
# Requires: claude CLI
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/tap.sh"
source "$SCRIPT_DIR/../lib/fixtures.sh"

command -v claude >/dev/null 2>&1 || { echo "Bail out! claude CLI not found"; exit 1; }

plan N

# Setup: scaffold project with stub + state fixture
PROJ=$(setup_integration_project \
  --with-state "$FIXTURES_DIR/state-FIXTURE.md" \
  --with-brownfield-stub)  # or --with-greenfield-stub

# Run the stage
run_claude "$PROJ" "/aidlc --stage SLUG --test-run" --max-turns M

STATE="$PROJ/aidlc-docs/aidlc-state.md"

# Assertions...
# 1. Check state marks stage [x] completed
# 2. Check artifact directory exists
# 3. Check artifact files exist and have content
# 4. Check artifacts reference domain concepts
# 5. Check artifact size bounds

cleanup_test_project "$PROJ"
finish
```

4. Run with `bash tests/run-tests.sh --stage` or directly: `bash tests/stage/tNN-stage-SLUG.sh`

## How to Add Acceptance Assertions

To add artifact assertions to existing workflow tests (t50-t58):

1. Read the current test and understand what it already checks
2. Add assertions after the existing ones (increment the `plan` count)
3. Use flexible patterns: `grep -ri "[Tt]odo" "$DIR"` not exact strings
4. Use `skip` for assertions that depend on LLM output format
5. Use `assert_file_min_size` for size-bound checks

## Assertion Design Principles

- **Keyword classes** — Use case-insensitive regex: `[Tt]odo`, `[Rr]eact`, `[Bb]rownfield`
- **Flexible discovery** — Use `find` + `wc -l` to count files rather than checking exact names
- **Size bounds** — Use `assert_file_min_size` or `wc -c` + `assert_gt` for minimum content
- **Graceful degradation** — Use `skip` when an assertion depends on non-deterministic LLM output
- **Structure over content** — Check for markdown headings (`^#`), file existence, directory creation before checking content

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `AIDLC_TEST_TIMEOUT` | `1800` | Per-`claude -p` call timeout in seconds. Set to `0` to disable. |

## CLI Reference

```bash
# Tier flags (combinable)
--smoke         # Structural validation
--unit          # Single-component isolation
--feature       # Cross-component contracts
--integration   # CLI tool utilities via claude
--stage         # Individual stage tests with stubs
--workflow      # Full multi-stage workflows
--worktree      # Worktree primitive tests (git worktree add/remove + helpers)

# Profile flags (shortcuts)
(default)       # L1: smoke + unit + feature
--ci            # L2: + integration + stage + worktree
--release       # L3: + workflow + worktree
--all           # Same as --release

# Output modifiers
--verbose       # Write per-test logs to tests/logs/
--debug         # Implies --verbose; adds bash -x traces
--filter PAT    # Only run tests whose filename matches extended regex PAT
--parallel N    # Run up to N test files concurrently within a tier (alias: -P N).
                # Default: 1 (serial). Smoke and unit tiers are always serial.
```

## Parallel Execution

`--parallel N` (or `-P N`) runs up to N test files concurrently within a tier. Default is serial (`1`).

**When it helps.** Integration, stage, and workflow tiers each spend most of their wall-clock on `claude -p` subprocess startup and LLM turns. These tests are already filesystem-isolated — `setup_integration_project` scaffolds a fresh `$PROJ` per test — so they can run side-by-side without interfering.

**Spike results (2026-05-06, Opus 4.7 via Bedrock):**

| Scenario | Serial | `--parallel 4` | `--parallel 8` |
|---|---|---|---|
| 4 × `/aidlc --help` | 56s | 16s (3.5x) | — |
| 8 × `/aidlc --help` | — | — | 31s |

All 8 parallel calls observed `cache_read=73789` — Bedrock prompt caching stays warm across concurrent workers. No throttling or corruption observed at 8-way.

**What stays serial.** Smoke and unit tiers ignore `--parallel` and run serially regardless. They already complete in seconds and their interleaved output would hurt debuggability for no wall-clock gain. The preflight gate (`t19-preflight-health.sh`) also runs serially because the LLM tiers depend on its exit status.

**Output under parallelism.** `START` markers stream live (several can appear back-to-back before the first `DONE` — that's the visible signal workers are concurrent), but each worker's TAP body is buffered and flushed to stdout as one contiguous block under a directory-mutex (`mkdir $LOG_DIR/.stdout.lock`, atomic on POSIX — works on macOS bash 3.2 without `flock`). So `ok`/`not ok` lines from different files never interleave; stdout reads top-to-bottom like a serial run, just with the file completion order determined by how long each test took rather than dispatch order. The trade-off: you don't see individual `ok` lines tick as a worker runs — you see its entire block when it finishes. For a live per-test stream, run serially (`--parallel 1`, the default). Per-test logs (`$LOG_DIR/<name>.log`) and trace files (`$LOG_DIR/<name>.trace.log`) are always per-file — there is no combined trace file, since concurrent workers would interleave writes. `cat $LOG_DIR/*.trace.log` reproduces the combined view on demand.

**Worker coordination.** The parent backgrounds `run_test_file` with `&` and holds a slot gate via `jobs -rp | wc -l`. Each worker writes an atomic `.meta` sidecar to `$LOG_DIR/_results/`; the parent reads them after `wait` to populate the summary tables. macOS ships bash 3.2.57 (no `wait -n`), so the gate polls every 200ms — negligible next to minute-long LLM calls.

**Guidance.** Start with `--parallel 4`. Raise to `8` if Bedrock capacity and your bill tolerate it. Drop back to serial for debugging a single failing test — or use `--filter` to isolate it.
