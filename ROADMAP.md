# AI-DLC Claude Code 1.0 Roadmap

## Context

This is the delivery plan for AI-DLC Claude Code 1.0. 1.0 means: structured stage contracts with a real dependency graph, a control-plane / data-plane cut (one compile at workflow start, two compiled artefacts, strict-additive rule resolution with admission-time conflict rejection at gates, recovery as emergent property of the data plane), a recomposed skill surface (entry-point + capability + persona roles all packaged per agentskills.io), designer skills for stages / agents / harness, methodology-led testing, project-level deployment architecture, Construction worktree isolation for parallel Bolts, a cross-workflow observer, LLM sensors with autoresearch, and a fitness contract compiler. Reshaped 2026-05-21 against the control-plane / data-plane explainer (v2 cut over 2026-05-24 to describe the strict-additive runtime + admission-time conflict-rejection model) after the v0.5.0 design changed shape.

1.0 work lands on main as a sequence of small themed releases. No long-lived branches. **There is no fixed v1.0.0 cut date.** 1.0 happens when reality forces a breaking change, not when a release plan says it should.

**Intellectual spine:** Martin Fowler's *Harness Engineering for Coding Agents* model — Agent = Model + Harness, where the Harness combines **guides** (feedforward: rules, knowledge, stage protocol) with **sensors** (feedback: tests, linters, LLM rubrics) across **computational** (deterministic) and **inferential** (LLM-as-judge) controls. AI-DLC today is feedforward-heavy and sensor-poor. Most 1.0 leverage sits in closing the sensor-shaped hole while preserving the feedforward strengths.

**The 1.0 plan prioritises consistency and quality over customer urgency.** The order of releases follows dependency: foundations (v0.3.0) → Construction worktrees (v0.4.0) → control-plane / data-plane substrate (v0.5.0) → skill surface recomposition (v0.6.0) → designer skills for stages, agents, and harness (v0.7.0) → testing strategy (v0.8.0) → deployment architecture (v0.9.0) → cross-workflow observer + ralph driver (v0.10.0) → LLM sensors + autoresearch (v0.11.0) → fitness contract compiler (v0.12.0). Each new-primitive release ships its designer-skill extension in-release, so designer skills never lag the primitives they author. Expect to learn along the way and reshape.

No timeline estimates. Ship when each release's acceptance is green.

**Cross-cutting design principles** (carry across every release):

- **What learns, where it goes** — the learning loop captures every learning at gate time as a candidate from `memory.md` (orchestrator-surfaced, verbatim) plus a free-text user-addition channel. The user picks one of four headings (Interpretation / Deviation / Tradeoff / Open question); destination derives from heading. Practices-discovery writes to the team and project rule files (`aidlc-{team,project}.md`); the memory gate writes rolling dated entries to the corresponding learnings files (`aidlc-{team,project}-learnings.md`). Both surfaces run admission-time section-level LLM conflict checks against `aidlc-org.md` before content lands on disk. The LLM never paraphrases, never routes, never classifies at the gate — that's deterministic-tool work.
- **Asymmetric scope hierarchy** — rules are scope-hierarchical (org / team / project / phase / stage), loaded into context at workflow start. Sensors are flat and ID-referenced, with `applies_to` declaring compatibility, resolved into per-stage `sensors_applicable` at workflow start. Both compile through the same pipeline (`aidlc-graph.ts compile`); two source shapes, one compiled view per stage.
- **Compile at workflow start, never mid-flight** — `aidlc-graph.ts compile` runs once at workflow start, reads stage frontmatter + `.claude/rules/` + `.claude/sensors/`, resolves the five-layer inheritance chain, and emits `stage-graph.json` with `rules_in_context` + `sensors_applicable` baked into each node. Steering-loop writes during a workflow update source files but don't affect the in-flight compiled view; they enter the next workflow's compile. BGP-style — no recompute mid-packet-flight. Determinism, audit integrity, and predictability all rest on this choice.
- **LLM does diary only** — in the learning loop, the LLM's only job is writing observations to `memory.md` during the stage. Counting entries (silent-skip detection), surfacing candidates at the gate, parsing headings, classifying, routing to destinations, and writing rule files are all deterministic-tool or user jobs. If a proposed design hands the LLM post-hoc cognitive work, it gets pushed back to a tool or to the user.
- **Deterministic-first, LLM-selective** — inside any loop iteration, fire deterministic sensors first. Only if they pass, fire LLM sensors for semantic judgment. Operationalises Fowler's "combine strategically" principle. (Loop drivers ship in v0.10.0; LLM sensors in v0.11.0.)
- **Reuse over rebuild** — existing utilities (`withAuditLock`, audit emission pattern, hook template, CLI entry pattern, state-file I/O) are the reuse surface for every new tool/hook. Each release calls out its reuse list.
- **Testing is a first-class deliverable in every release** — no feature merges without its tests green. CI parallel runner green across all tiers (unit, feature, integration, workflow, drift-sweep) is the merge gate. Release tag gate requires full suite green plus dogfood run.
- **Practices-discovery is the operational-truth precursor to v0.12.0 Phase 0 Harness Setup** — v0.4.0's `practices-discovery` (Inception 2.2) captures team branching, walking-skeleton stance, testing posture, deployment, and code style as team-authored prose in `.claude/practices/team.md`. v0.12.0's Phase 0 Harness Setup owns architectural rules via the fitness-contract compiler (DSL → rules + sensor bindings). Distinct concerns: practices is the team's voice on how they work; Phase 0 is the harness engineer's contract on what the project commits to. v0.12.0 plan-time decision resolves the boundary; until then, practices-discovery covers the operational-truth half and Phase 0 stays unscoped for architecture-fitness.

**Branch strategy:** evolve main. Tag releases. Feature flags for experimental runtime behaviour — `AIDLC_GRAPH_RESOLVE=1`, `AIDLC_SENSOR_UNLIMITED=1` (developer-local override), plus per-release flags as introduced. Graduation policy is pragmatic per release, not a framework. The `public` branch keeps its current role.

**Native Claude Code features the plan leans on:** PostToolUse hooks (deterministic sensor firing), Task / sub-agents (LLM-judge sensors, autoresearch variants), parallel Task calls (variant generation), Stop hook with `{decision: block}` (interactive ralph), `claude --print` with `--max-turns` / `--max-budget-usd` (headless ralph / autoresearch), `/loop` skill and CronCreate (scheduled observer runs), AskUserQuestion (approval flows), PreCompact hook (state validation).

**User-visible migration support:** none. User count is low; every release may break users of the previous release. Explicit.

## Versioning

Semver throughout: `vMAJOR.MINOR.PATCH`. Minor releases (`v0.3.0`, `v0.4.0`, ...) drive the roadmap spine. Patch releases (`v0.3.1`, `v0.3.2`, ...) land as needed for bug fixes without breaking the spine. The `v` prefix on version references distinguishes them in text from stage numbers (which share the same numeric shape — e.g., stage `0.3` is distinct from release `v0.3.0`). **No fixed v1.0.0 cut date** — 1.0 happens when reality forces a breaking change, not on a calendar.

## Release spine

```
v0.3.0    Foundation
v0.4.0    Construction worktrees + split-safe state/audit + practices discovery
v0.5.0    Control plane / data plane cut + learning loop
v0.6.0    Skill recomposition (orchestrator unbundled, three skill shapes per agentskills.io)
v0.7.0    Designer skills (agent designer + harness designer + stage designer)
v0.8.0    Testing strategy
v0.9.0    Deployment architecture
v0.10.0   Cross-workflow observer + ralph driver
v0.11.0   LLM sensors + autoresearch
v0.12.0   Phase 0 Harness Setup + fitness contract compiler
v1.0.0    Cut when reality forces a breaking change — no fixed schedule
```

Ten pre-1.0 minor releases. Each themed, each tagged, each fully documented.

## Risk flags (carried across the whole roadmap)

These items are the hardest to actually complete or the likeliest to bite. Scope them aggressively, spike early, feature-flag at rollout.

- **Steering-loop concurrency under `withAuditLock`** (NEW for v0.5.0) — concurrent `aidlc-graph.ts compile` invocations against the same project must serialise; atomic temp-rename writes prevent torn reads under crash mid-write. Both patterns reuse v0.4.0's existing `withAuditLock` primitive, but the compile is the first read-then-write hotspot under concurrent load and warrants its own integration test.
- **Skill-recomposition back-compat** (NEW for v0.6.0) — `/aidlc` is a public surface today; the recomposition (orchestration logic moves out of the entry-point skill into a capability skill) must not break invocation. Every existing scope, flag, and gate keeps working. The recomposition is internal; users notice only that more `/aidlc-*` skills appear in the picker.
- **Designer-skill / primitive lockstep** (NEW for v0.7.0+) — every new-primitive release (v0.10.0 ralph driver, v0.11.0 LLM sensors, v0.12.0 fitness contracts) must extend its designer skill in-release. If a release ships a primitive without designer support, the surface decoheres — users hit a primitive they can't author through the skill they were taught to use. Process commitment, not feature.
- **Cross-workflow observer ordering** (was: "LLM sensors + observer ordering") — observer (v0.10.0) must ship BEFORE LLM sensors (v0.11.0) reach users. LLM sensors without a retirement mechanism accumulate false-positive noise and train users to ignore findings. Observer retirement rule (`sensor-never-correlates`) is the backstop.
- **Stop-hook conflict with official `ralph-loop` plugin** (was: "in v0.8.0", now: "in v0.10.0" with the ralph-driver slide) — both register Stop hooks at the same mount point. Execution order is non-deterministic in Claude Code. Coexistence requires explicit yield-when-plugin-active detection. Ship the integration test before MR merges.
- **`--doctor` rule↔sensor coherence check is file-existence, not semantic** (kept) — v0.5.0's coverage pass and `--doctor --rule-drift` flag verify paired files exist and surface rule drift between org and existing team/project content for review, but cannot verify the sensor faithfully detects violations of its paired rule. True semantic coherence of that pairing requires an LLM-judge. Acknowledged limitation for 1.0; documented in doctor output. (Separately: doctor's graph-level checks shipped in v0.3.0 — cycles, scope validation, schema + references, keyword overlap — are structural, not rule-coherence, and are not subject to this limitation.)
- **Maintenance burden after 1.0** (kept) — sensor registry, observer rules, loop configs, rubric thresholds all rot without ongoing attention. Estimated ~20% of one engineer's time once sensor count exceeds ~10. Not a feature that ships; an operational commitment. If not made, the harness decays.

---

## v0.3.0 — Foundation

**Theme:** A formal stage definition. A real stage graph with real graph utilities. De-hardcoded scope and agent enumerations. Typed artifact contracts. Published stability policy with archive-and-reinit + count-pin patterns. Migration tooling deferred to v0.4.0 (first real state-schema field delta). No new user-facing features.

**Headline deliverables:** the stage definition format (the contract every stage file conforms to) and the graph utilities that consume it. Everything downstream rests on these two.

**Work areas**

- **Stage definition format (new)** — design how every stage file exposes graph primitives (inputs, outputs, produces, consumes, requires_stage, pre/postconditions) to the parser while keeping the stage **body fully LLM-executable prose**. Stage bodies today are 60-140 lines of step-by-step instructions ("Load prior context from X", "Generate questions about Y") that the LLM reads and follows. That must not change. The graph primitives are additional machine-readable metadata, not a replacement for the prose. **Two architectural options to decide in v0.3.0**:
  - Option A: structured YAML frontmatter at the top of each stage file carries graph primitives; body stays prose; one file, two audiences.
  - Option B: a central graph-state file carries all graph primitives keyed by slug; stage files stay 100% prose; two sources of truth linked by slug.
  Decide during v0.3.0 implementation. Output regardless of option: **a written stage-definition spec** in `aidlc-claude-code/.claude/skills/aidlc/stage-definition.md` (or a reference chapter in `docs/reference/`) covering all fields, types, validation rules, worked example, and the LLM-executability guarantee.
- **Stage schema (new)** — a machine-checkable schema expressing the format (JSON Schema, Zod, or similar). Both `aidlc-graph.ts` (validates on load) and `--doctor` (lint pass) use it. Adding a new stage without conforming to the schema fails validation. Schema covers only the graph primitives; prose body is schema-free.
- **`aidlc-claude-code/.claude/tools/lib.ts`** — `parseStageFrontmatter` (or equivalent) helper. Accepts the new structured form. Back-compat with today's prose-bullet form for one release so the existing test suite keeps working during migration.
- **Typed artifact vocabulary** — define every `produces`/`consumes` artifact name. Lowercase-kebab. Namespaced by phase where useful. Implicit registry from union of all `produces`. Document in `docs/reference/`.
- **`aidlc-claude-code/.claude/tools/data/stage-graph.json`** — extend schema. New fields per stage entry: `produces: string[]`, `consumes: {artifact: string, required: boolean, conditional_on?: "brownfield"|"greenfield"|"always"}[]`, `requires_stage: string[]`, `multiplicity: "singleton"|"per-unit"`, `consumption: "scalar"|"glob"`. Migrate all 31 stages.
- **Migrate 31 stage files** to the new stage definition format. Existing prose body preserved. Header block converts from prose bullets to structured YAML with the fields above plus pre/postconditions.
- **`aidlc-claude-code/.claude/tools/aidlc-graph.ts`** (new) — graph module. Library + CLI. Consumes the stage definition via `parseStageFrontmatter`. API: `loadGraph`, `producersOf(artifact)`, `consumersOf(artifact)`, `topoSort(stages)`, `findCycles(stages)`, `upstreamOf(stage)`, `downstreamOf(stage)`, `subgraphForScope(scope)`, `validateScope(scope)`, `diffGraphs(a, b)`, `exportForDesigner()`. CLI subcommands mirror the library. A `resolve` subcommand emits `.aidlc-plan.json` for the active scope; plan-identity parity test asserts it matches the legacy scope-mapping-derived plan across all 9 scopes. Rollout feature-flagged via `AIDLC_GRAPH_RESOLVE=1` so the orchestrator can fall back during rollout.
- **`aidlc-claude-code/.claude/tools/aidlc-utility.ts`** — remove `VALID_SCOPES` constant; derive from `scope-mapping.json` keys. Remove `AGENT_KNOWLEDGE` map; derive from `.claude/agents/*.md` frontmatter.
- **`aidlc-claude-code/.claude/tools/aidlc-state.ts`** — remove all `VALID_SCOPES` consumers.
- **`aidlc-claude-code/.claude/agents/*.md`** (11 files) — strip numeric stage IDs from "Stages Owned" sections and body prose. Reference stages by slug only.
- **`aidlc-claude-code/.claude/skills/aidlc/SKILL.md`** — replace the 9 hardcoded scope routing blocks with one generic procedure directing the orchestrator to call `bun .claude/tools/aidlc-state.ts lookup stages-in-scope <scope>`, plus a compiled summary table between BEGIN/END markers regenerated via `bun .claude/tools/aidlc-utility.ts scope-table` (with `--check` as a CI drift guard). Remove hardcoded scope enum in error messages. Fold natural-language keyword→scope inference into `scope-mapping.json` as a new `keywords[]` field per scope, consumed by `detect-scope --from-text`.
- **`aidlc-graph.ts export`** — emit a single designer-consumable JSON bundle (stages + scopes + artifacts + agents + support_agents). Versioned schema. Becomes the designer skills' input in v0.7.0 (and the visual GUI's input post-1.0).
- **Doctor extensions** — `aidlc-claude-code/.claude/tools/aidlc-utility.ts` doctor function: cycles, orphan producers, orphan files, stale stage files, scope graph-walk validation.
- **State template bump** — state template schema v5 → v6. No field delta in v0.3.0 Foundation; the bump signals the release's state revision. Migration tooling (`aidlc-state.ts migrate` subcommand + `aidlc-migrations.ts` registry) ships in v0.4.0 alongside its first real field delta (worktree path, Bolt refs). Users in-flight on v5 state archive-and-reinit per the v4→v5 precedent, consistent with the "no user-visible migration support" policy above.
- **Audit taxonomy reconciliation** — today is 41 events. `aidlc-claude-code/.claude/tools/aidlc-audit.ts` comment, `aidlc-claude-code/.claude/aidlc-knowledge/shared/audit-format.md`, docs all updated. Add a unit test asserting `VALID_EVENT_TYPES.size === 41`.
- **Stage count correction** — `find .../stages -name "*.md" | wc -l` is 31. Any docs citing "32 stages" get corrected.
- **`docs/reference/` stability and deprecation policy** — published in v0.3.0. What breaks at minor vs major. How long deprecations live. Honoured from v0.3.0 forward; the policy now lives inline in the artifact-vocabulary chapter.
- **Test coverage (critical)** — v0.3.0 is what every later release builds on; bugs here cascade through v1.0.0. Test authoring is a first-class deliverable, not an afterthought. Coverage requirements:
  - Unit: stage schema validation exhaustive (every field, every type, every required/optional combination, every invalid input); `parseStageFrontmatter` round-trips (parse → re-emit → parse) for new and back-compat forms.
  - Feature: graph module API surface with cycle fixtures, disjoint-subgraph fixtures, missing-producer fixtures. Performance sanity: 31-stage traversal under 100ms.
  - Integration: for each of 9 existing scopes, graph walk resolves every required consume to an enabled producer; fixture custom scopes valid and invalid with correct failure reasons; per-Unit multiplicity fixtures; conditional-on brownfield/greenfield fixtures.
  - Feature: doctor lint extensions — orphan producers, orphan stage files on disk, cycle detection, stale references — each with a failing fixture.
  - Feature: stage migration golden tests for all 31 stages.
  - Integration: state v5 → v6 migration round-trip; fixture custom scope + custom agent resolve correctly.
  - Unit: audit taxonomy asserts `VALID_EVENT_TYPES.size === 41`.
  - Existing adjacent tests extended (not replaced): t32 stage-graph-consistency, t43 stage-io-contracts, t44 stage-instruction-completeness, t45 stage-output-validation, drift-sweep (t55).
  - CI parallel runner green across all tiers is the merge gate.

**Acceptance**
- Stage definition spec written and published in `docs/reference/`.
- Stage schema (machine-checkable) validates all 31 migrated stages.
- `aidlc-graph.ts` loads the graph from stage files cleanly; all graph-module APIs have unit and feature tests with golden fixtures.
- `/aidlc --doctor` runs graph checks (cycles, orphans, scope validation, schema lint) and passes on main.
- A fixture custom scope passes validation and runs end-to-end.
- A fixture custom agent loads and is dispatchable.
- All 9 existing scopes run unchanged; all 31 stages run unchanged in behaviour.
- Migration tool round-trips v5 → v6 cleanly; state-fixture test confirms resume works post-migration.
- Audit event count test passes (asserts 41).
- Stage migration golden tests pass for all 31 stages.
- No `VALID_SCOPES` or `AGENT_KNOWLEDGE` literal in TypeScript source; fixture custom entries in data files resolve correctly.
- CI parallel runner green across all tiers.

---

## v0.4.0 — Construction worktrees + split-safe state/audit + practices discovery

**Theme:** Bolts execute in git worktrees so parallel Bolt batches and workshop-group scenarios (multiple groups each building a Bolt in parallel, AI-driven with humans driving gates) don't race. State and audit model split + merge cleanly across worktrees. A new Inception stage `practices-discovery` at slot 2.2 discovers and affirms team branching, walking-skeleton stance, testing posture, deployment, and code style — read by the Construction orchestrator at start so worktree dispatch and walking-skeleton sequencing reflect the team's voice rather than scope-hardcoded defaults.

**Work areas**

- **`aidlc-claude-code/.claude/skills/aidlc/SKILL.md`** — Construction flow: when the orchestrator starts a Bolt, create a worktree at `.aidlc/worktrees/bolt-<name>/` on branch `bolt-<name>` from current HEAD. All 3.x stages for that Bolt run inside the worktree.
- **`aidlc-claude-code/.claude/tools/aidlc-bolt.ts`** — extend with `start --worktree`, `complete --merge`, `abort --discard` subcommands. Track worktree path in state.
- **Split-safe state** (`aidlc-claude-code/.claude/tools/aidlc-state.ts`, `aidlc-docs/aidlc-state.md` schema) — state file forks to worktree on `BOLT_STARTED`. State in worktree records the Bolt's stage progression. On `BOLT_COMPLETED` and gate approval, state merges back to main workspace's state. Collision resolution: deterministic by Bolt slug order when two Bolts commit simultaneously.
- **Split-safe audit** (`aidlc-claude-code/.claude/tools/aidlc-audit.ts`, `aidlc-docs/audit.md`) — audit entries in the Bolt worktree append in isolation during the Bolt. On Bolt completion, merge: audit entries from the worktree append to main's audit.md preserving chronological order.
- **Merge strategy** — decided at implementation time (candidates: git merge with explicit commit, squash merge for Bolt = one commit, rebase for linear history). Document the choice.
- **Audit events** — new: `WORKTREE_CREATED`, `WORKTREE_MERGED`, `WORKTREE_DISCARDED`, `STATE_FORKED`, `STATE_MERGED`, `AUDIT_FORKED`, `AUDIT_MERGED`. Update v0.3.0's event-count test.
- **Parallel batch dispatch** (SKILL.md) — update to create N worktrees and dispatch N Task calls, each pinned to its worktree. Walking-skeleton Bolt is solo but still uses its own worktree (single-item batch).
- **Workshop mode** — document the multi-human-AI-pair flow: N developers each on their own machine, each claiming a Bolt, each getting a worktree. Push-pull semantics via the shared remote. Claim semantics ride on `git push` of `bolt-<slug>` to the shared remote (first push wins, late claimants get a non-fast-forward rejection); the manual recipe uses `aidlc-worktree create` + `git push` and is documented in `docs/guide/workshop-mode.md`. A dedicated `--claim-bolt` utility was deferred — see Post-1.0 extension vectors.
- **Halt-and-ask integration** — Bolt failure inside a worktree: present retry/skip/abort with the worktree state visible. Worktrees for aborted Bolts are preserved for inspection unless the user explicitly discards.
- **Test coverage (required)**:
  - Unit: worktree-create / merge / discard primitives; state fork and merge; audit fork and merge; conflict resolution deterministic ordering.
  - Feature: `aidlc-bolt.ts` new subcommands all cases.
  - Integration: two-Bolt parallel batch runs cleanly; three-claimant workshop fixture with state/audit split/merge produces coherent final state; aborted Bolt leaves inspectable worktree; simultaneous gate approvals serialise via deterministic ordering.
  - Workflow: each of 9 scopes runs Construction through worktrees without regression; `--test-run` walks the new path.
  - Drift guards: worktree-path registry kept in sync with state; doctor detects orphaned worktrees and stale branches.
  - Performance: worktree creation under 500ms on a 100MB repo fixture.

---

## v0.5.0 — Control plane / data plane cut + learning loop

**Theme:** Borrow networking's three-plane discipline. The framework gets a **control plane** (stage definitions, rules, sensors — schema), a **data plane** (workflow execution, agents, Bolts, sensor firings — runs), and a **management plane** (doctor, designer, audit queries — observability). One compile at workflow start resolves the five-layer inheritance chain (org → team → project → phase → stage) and emits two compiled artefacts. The learning loop captures learnings during a workflow but writes for the *next* workflow's compile (BGP-style — no recompute mid-flight). Recovery from session compaction emerges as a property of the data plane, not as a feature added on top. Source of truth for this release is the control-plane / data-plane explainer (v2 cut over 2026-05-24 to describe the strict-additive runtime + admission-time conflict-rejection model); MR-level detail lives in issue #78 (rewrite pending against the explainer).

**User-facing additions**

- **New gate-ritual interaction.** At every stage gate, a "what did I miss?" free-text prompt appears alongside any orchestrator-surfaced candidates from `memory.md`. User picks one of four headings (Interpretation / Deviation / Tradeoff / Open question); destination derives from heading. The user never picks a file path — promotion to `.claude/rules/aidlc-project.md` is automatic, with one click to widen scope.
- **Auto-recovery on session resume.** A fresh harness session after compaction reads the artefact tree, per-stage `memory.md`, audit log, state docs, and `runtime-graph.json` in order to reconstruct workflow state. No explicit resume command — the data plane self-describes. Generalises today's `Test Run Mode` compaction-survival pattern.
- **Doctor surfaces rule drift** via a new `/aidlc --doctor --rule-drift` flag. When org rules change after team or project content already lands on disk, doctor surfaces the drift on demand (non-blocking observation-time check via section-level LLM); admission-time rejection at practices-discovery and the memory gate prevents new conflicts before they reach disk.
- **`aidlc-` filename prefix sweep (BREAKING for users authoring overlays or pinning paths).** Every framework-shipped file under `.claude/` adopts the `aidlc-` prefix to distinguish framework-shipped from team-authored files (the [Two-Axis Configuration Model] from v0.4.0 MR 5 made this convention; v0.5.0 applies it everywhere). The full file-by-file rename diff (tools, hooks, agents, rules layout flatten) lives in issue #78's plan rewrite. High-level shape: tools like `lib.ts` / `version.ts` / `stage-schema.ts` become `aidlc-*.ts`; every hook gains the prefix; every agent persona file gains the prefix; the rules directory flattens from two-deep `.claude/rules/aidlc/guardrails/<name>-guardrails.md` to flat `.claude/rules/aidlc-<scope>.md` (`aidlc-org.md`, `aidlc-team.md`, `aidlc-project.md`, `aidlc-phase-<phase>.md`).
- **No breaking changes to `/aidlc` invocation.** Existing scopes, flags, and gates work as today; the surface change is internal (filenames, gate-ritual prompts, doctor extension).

**Work areas (high level — MR-level detail in #78)**

- **`aidlc-graph.ts compile` extension** — read `.claude/rules/` and `.claude/sensors/` at workflow start. Walk the five-layer inheritance chain per stage. Emit `stage-graph.json` with per-node `rules_in_context` (array of resolved rule paths + scope tags) and `sensors_applicable` (resolved manifest paths + their `applies_to` patterns). One compile, multiple sources, all pre-resolved.
- **Concurrent-safety for compile** — the compile runs under `withAuditLock` from v0.4.0 (`lib.ts:408`) so simultaneous invocations serialise. Writes go to `stage-graph.json.tmp` then atomically rename via POSIX `rename(2)`; readers see either the previous compile's output or the new one, never half-written.
- **`aidlc-runtime.ts compile`** (new tool) — post-stage hook fires after every stage gate and after audit-event-emitting writes. Aggregates `audit.md`, per-stage `memory.md`, Bolt forks, sensor firings into `aidlc-docs/runtime-graph.json`. Per-stage `memory_entries` is a deterministic count of non-blank lines under the four standard headings — silent diary-skip is detectable without asking the LLM whether it kept its diary.
- **Per-stage `memory.md`** at `aidlc-docs/<phase>/<stage>/memory.md`. Four standard headings: `## Interpretations` / `## Deviations` / `## Tradeoffs` / `## Open questions`. Persists across sessions; lives in the artefact tree on approval. The orchestrator writes during the stage; everything else (counting, surfacing, routing) is deterministic-tool work.
- **Stage-protocol §13 — Learnings Ritual (two-source candidate collection with strict LLM/tool/user boundaries).** Source 1: memory.md lines surfaced verbatim by `aidlc-runtime.ts` (post-stage hook), each carrying its source heading. Zero entries emit `MEMORY_EMPTY` — no user prompt about diary discipline. Source 2: free-text user-addition channel; user types observation and picks one of four headings; destination derives. User ticks candidates; deterministic tool writes confirmed text. Skipped in `TEST_RUN_MODE`. (Edit-inferred candidates from artefact diffs deferred to v0.6.0+.)
- **Strict-additive rule resolution.** Org → team → project guardrails all apply at runtime; conflicts are rejected at admission gates (practices-discovery, memory gate) by section-level LLM check, not at runtime. Doctor surfaces post-write drift via `--rule-drift`.
- **Recovery as data-plane property** — five sources combined (artefact tree → memory.md → audit log → state docs → runtime-graph.json) reconstruct workflow state at session start. Generalises today's `Test Run Mode` compaction-survival pattern at `SKILL.md:88`. v0.5.0 ships the data-plane shape; the polished resume command lands in a later release.
- **`aidlc-` filename prefix sweep across framework-shipped files** — apply the prefix uniformly to every file under `.claude/` that ships with the framework. Tools, hooks, agents, rules. The full file-by-file diff (paths, source-code import updates, hook frontmatter updates, test fixtures, docs cross-references) lives in issue #78's plan rewrite — too large to enumerate here.
- **Drops the three-sibling `guardrails/sensors/learn` reorg** that the previous v0.5.0 plan envisioned. The redesign keeps `.claude/rules/` (Claude Code's auto-load primitive) and adds `.claude/sensors/` as a sibling. No `learn/` directory — loop drivers and observer rules belong with their releases (v0.10.0+).
- **Three-compartment story** — `## Steps` and `## Sensors` are the parsed compartments at runtime. `## Learn` remains as uniform trigger-prose pointing at stage-protocol §13, not a per-stage authored compartment. Stages stay framework-immutable; learnings land in `.claude/rules/` / `.claude/sensors/`, not in stage compartments.
- **Audit events** — add `SENSOR_FIRED`, `SENSOR_PASSED`, `SENSOR_FAILED`, `SENSOR_BUDGET_OVERRIDE`, `GUARDRAIL_LOADED` (already pre-registered as `Reserved (v0.5.0 MR N)` in the [v0.5.0 MR 1 audit pre-register](https://github.com/OWNER/REPO/pull/76); MR sequence in #80 wires emitters). Add `MEMORY_EMPTY` for silent-skip detection; reserve `RULE_LEARNED` and `SENSOR_PROPOSED` for the §13 ritual emit set (MR 12).
- **Test coverage (required)**:
  - Unit: compile inheritance resolution exhaustive (org / team / project / phase / stage layers, plus section-level conflict-check at admission gates); `runtime-graph.json` schema validation; memory.md heading parser; gate-ritual destination-from-heading mapper.
  - Feature: `aidlc-graph.ts compile` produces stable output across repeated runs (byte-deterministic); `aidlc-runtime.ts compile` aggregates audit + memory correctly; `withAuditLock` serialises concurrent compiles; doctor `--rule-drift` renders rule-drift after org-rule changes correctly.
  - Integration: workflow-start compile → orchestrator reads pre-resolved fields off graph nodes → no inheritance walks at runtime; learning-loop write during workflow doesn't affect in-flight compiled view; next-workflow compile picks it up; recovery integration test — fresh session reconstructs workflow state from the five sources.
  - Drift guards: rules `aidlc-` prefix coverage; sensor manifest schema; gate-ritual heading enum.

---

## v0.6.0 — Skill recomposition (orchestrator unbundled, three skill shapes per agentskills.io)

**Theme:** The current `/aidlc` skill is a 881-line `SKILL.md` that conflates two roles: it's both the **entry point** the user types and the **orchestration logic** that drives the workflow. v0.6.0 unbundles those roles. The orchestration role moves out of the entry-point skill and becomes a capability skill the entry point dispatches into. Three entry-point shapes ship per the [agentskills.io](https://agentskills.io/specification) spec: full orchestrator, scope-runner, stage-runner / chain. Today everything is bundled into one skill; the recomposition lets multiple skills route into the same stages with different bargains over how much of the workflow the framework runs versus how much the human runs.

**User-facing additions**

- **`/aidlc` keeps working as today** — full orchestrator, no breaking changes to invocation. The recomposition is internal; users never see the orchestration logic move out of the entry-point skill.
- **New `/aidlc-<scope>` and `/aidlc-<stage>` skills become typeable.** Scope-runners (`/aidlc-bugfix`, `/aidlc-spike`, etc.) bake a fixed scope into the entry point — same workflow as today's `/aidlc bugfix`, but as its own command surface. Stage-runners (`/aidlc-plan`, `/aidlc-adr`, etc.) run one stage (or a small chain) in isolation; the human is the orchestrator.
- **Skill-picker discoverability.** Claude Code's skill picker surfaces every `/aidlc-*` skill on disk; no manual registration. Users discover skills by typing `/` and scrolling, the same way every other Claude Code skill works.
- **`state-modifying` vs `read-only` skill classification.** Skill frontmatter declares which class. Only the full orchestrator advances the main workflow's stage pointer; sub-runs and sensor-invocation skills are `read-only`.

**Work areas**

- **Orchestration logic extraction** — move the orchestration prose from `SKILL.md` into a capability skill the entry-point skill dispatches into. The entry-point skill keeps the dispatcher / routing / jump logic (read-only utility commands, composable flag extraction, stage/phase jump handling, etc.).
- **agentskills.io packaging across all three roles** — entry-point skills already use the spec; v0.6.0 extends it to capability skills (stage bodies as packaged capabilities) and persona skills (`.claude/agents/aidlc-*.md` files repackaged as agentskills.io-format skills). Format-convergence is the v0.6.0 commitment.
- **Initial scope-runner + stage-runner reference set** — ship a small representative sample (e.g., 1-2 scope-runners, 1-2 stage-runners) so the shape is visible. The road-to-aidlc-2 §16 14-skill list is a reference; specific skills follow as needed across later releases. v0.6.0 is the architectural recomposition, not a 14-skill bundle.
- **State-awareness convention for skills** — `lib.ts:readActiveWorkflow()` (or the `aidlc-`-prefixed equivalent post-rename) returns current stage / scope / phase / active agent without hand-rolling state parsing. Skills classified `state-modifying` fail the test suite if they advance the main workflow's stage pointer.
- **Audit events** — extend with `SKILL_INVOKED` (entry-point dispatch), `STAGE_DISPATCHED` (capability-skill activation). Update count test.
- **Docs** — new `docs/guide/18-skills.md`, new `docs/reference/18-skill-system.md` (reserved slots — the current top of each tree is chapter 16). Skill-vs-stage promotion heuristic documented as ongoing framework principle.
- **Test coverage (required)**:
  - Unit: skill frontmatter classifier (`read-only` / `state-modifying`); skill-picker discovery (every `aidlc-*` slug present); orchestration-logic extraction preserves dispatch behaviour byte-for-byte where it matters.
  - Feature: scope-runner with fixed scope produces same audit trail as `/aidlc <scope>`; stage-runner advances state correctly when invoked solo; `state-modifying` skill failing-test fixture (skill that tries to advance main workflow stage pointer).
  - Integration: each reference skill exercises against a fixture workflow.
  - Workflow: existing `/aidlc <scope>` invocations all run unchanged.
  - Back-compat: every test from v0.3.0 onward still passes.

---

## v0.7.0 — Designer skills (agent designer + harness designer + stage designer)

**Theme:** Three designer skills, packaged per agentskills.io, that author framework primitives via prompt-driven interaction. **Stage designer** authors new stages by collecting frontmatter primitives (inputs, outputs, produces, consumes, requires_stage, pre/postconditions) plus prose body. **Agent designer** authors new agent personas (persona body, knowledge pointers, model override, tool allowlist). **Harness designer** authors rules, sensors, sensor bindings, loop configs (when v0.10.0 ships them), fitness contracts (when v0.12.0 ships them). The designer skills are the authoring surface; the visual GUI defers post-1.0 (post-1.0 extension vector). **Each new-primitive release ships its designer-skill extension in-release** (e.g., v0.11.0 LLM sensors → harness-designer extension in the same MR), so designer skills never lag the primitives they author.

**User-facing additions**

- **Three designer skills become typeable.** Working slugs (finalised at implementation): `/aidlc-design-stage`, `/aidlc-design-agent`, `/aidlc-design-harness`. Each is a prompt-driven skill that authors source files in the right `.claude/` directory.
- **Authoring without filesystem surgery.** Users describe what they want; the designer skill writes the markdown source files, validates against the v0.3.0 schemas (stage definition, agent definition, sensor manifest), and confirms.
- **No breaking changes.** Hand-authoring still works; the designer skills are an alternative authoring surface for users who'd rather describe than write markdown.

**Work areas**

- **`aidlc-design-stage` skill** — packaged per agentskills.io. Walks the user through the stage-definition contract (v0.3.0 spec at `aidlc-claude-code/.claude/skills/aidlc/stage-definition.md`). Validates frontmatter against the schema (`aidlc-stage-schema.ts` post-rename). Writes the new stage file to `.claude/skills/aidlc/stages/<phase>/<slug>.md`. Updates the stage graph by triggering a recompile.
- **`aidlc-design-agent` skill** — packaged per agentskills.io. Walks the user through the agent-definition contract (persona, knowledge pointers, model, tool allowlist). Validates against the agent schema. Writes to `.claude/agents/aidlc-<slug>-agent.md`.
- **`aidlc-design-harness` skill** — packaged per agentskills.io. Walks the user through rule authoring, sensor manifest authoring (when sensors are user-authored, not just framework-shipped), sensor-binding parameters per-stage. v0.7.0 ships the rule + sensor-binding shapes; later releases extend (loop configs in v0.10.0, fitness contracts in v0.12.0). The lockstep commitment is documented as a release-cycle invariant.
- **Designer-skill API surface** — designer skills read `stage-graph.json` and `runtime-graph.json` (read-only). They write source files via the same paths a hand-author would touch. No new write API beyond what `aidlc-graph.ts compile` already validates.
- **Audit events** — extend with `DESIGNER_INVOKED`, `STAGE_AUTHORED`, `AGENT_AUTHORED`, `RULE_AUTHORED`, `SENSOR_AUTHORED`. Update count test.
- **Docs** — new `docs/guide/19-designer-skills.md`, new `docs/reference/19-designer-system.md` (reserved slots).
- **Test coverage (required)**:
  - Unit: each designer-skill schema validator; round-trip (designer-authored file parses cleanly through the existing v0.3.0 loaders).
  - Feature: each designer skill authored against a fixture produces a file that compiles cleanly via `aidlc-graph.ts compile`.
  - Integration: stage authored by `aidlc-design-stage` runs end-to-end through the orchestrator; agent authored by `aidlc-design-agent` is dispatchable; rule authored by `aidlc-design-harness` resolves into the correct stages' `rules_in_context`.
  - Workflow: existing `/aidlc <scope>` invocations all run unchanged.
  - Drift guards: every designer skill ships with its schema; designer-authored output passes the same validation as hand-authored output.

---

## v0.8.0 — Testing strategy *(was v0.6.0 in the pre-reshape spine)*

**Theme:** Methodology-led testing. Testing Posture at Requirements Analysis captures the project's testing commitments once. New Test Strategy stage authors tests per-Unit before code generation. Walking skeleton actually walks — scoped integration runs between its Units' code-gen and its mandatory gate.

**User-facing additions**

- **New Testing Posture section at `requirements-analysis`** (Inception 2.2). Users answer methodology (TDD/BDD/ATDD/Classic), red-green-refactor cadence, required test types, quality thresholds, tooling preference, tests-first gate.
- **New stage at 3.5: `test-strategy`.** Authors test files per-Unit before code generation (tests-first contract).
- **Stage renumbering.** `code-generation` 3.5 → 3.6; `build-and-test` 3.6 → 3.7; `ci-pipeline` 3.7 → 3.8.
- **`--test-strategy` flag REMOVED (BREAKING).** Old volume-bucket model (`Nyquist`/`Standard`/`Comprehensive`) is gone; methodology captured at requirements-analysis instead. CI scripts using the flag must be updated.
- **Walking-skeleton scoped integration.** Multi-Unit walking-skeleton Bolts run a scoped suite between last-Unit code-gen and the mandatory gate.
- **Testing-posture content authored via the testing-side designer skill** (from v0.7.0 onward); hand-authoring still works.

**Work areas**

- **`aidlc-claude-code/.claude/skills/aidlc/stages/inception/requirements-analysis.md`** — Testing Posture section added (methodology TDD/BDD/ATDD/Classic, red-green-refactor cadence, required test types, quality thresholds, tooling preference, tests-first gate). Produces `testing-posture` artifact.
- **`aidlc-claude-code/.claude/skills/aidlc/stages/construction/test-strategy.md`** (new) — per-Unit stage led by quality-agent. `Per-Unit: Yes`. Display Order 3.5. Produces `test-plan-per-unit`, `authored-tests`, `test-strategy-master` (first Unit only). Consumes `testing-posture`, `unit-definition`, `bolt-plan` (optional), `application-design` (optional), `deployment-architecture` (optional — when v0.9.0 lands). Writes actual test files to the project test directory. Ships with Sensors and Learn compartments from day 1.
- **Stage renumbering** — `code-generation` 3.5 → 3.6, `build-and-test` 3.6 → 3.7, `ci-pipeline` 3.7 → 3.8. Bolt glossary: "3.1–3.5" → "3.1–3.6". Updated in stage-protocol.md, SKILL.md, agent files that still reference numbers, `aidlc-bolt.ts` comment, state template, state fixtures, docs.
- **`aidlc-claude-code/.claude/skills/aidlc/stages/construction/code-generation.md`** — renumbered 3.6. Updated Inputs. Plan Approval gate removed; tests are the contract. RGR-aware execution when posture=TDD+RGR.
- **`aidlc-claude-code/.claude/skills/aidlc/stages/construction/build-and-test.md`** — renumbered 3.7. Strategy-design steps deleted. Execution-only: aggregate Units' `test-plan.md`, activate deferred suites, run full suite, build.
- **Walking-skeleton scoped integration** — SKILL.md orchestrator runs the scoped suite between walking-skeleton Bolt's last Unit code-gen and its mandatory gate. Closes the GOOS/Cockburn gap. Emits `WALKING_SKELETON_INTEGRATION_RAN`, `WALKING_SKELETON_INTEGRATION_PASSED`, `WALKING_SKELETON_INTEGRATION_FAILED`.
- **Scope consistency work** — for every scope, formalise skip-cascade. Remove "if exists" escape hatches from stage files. Every `required: true` consume has an in-scope producer or explicit scope-level stub documented. Doctor enforces via graph walk.
- **Operation-phase per-Unit path bug** — `deployment-pipeline.md`, `observability-setup.md`, `incident-response.md`, `environment-provisioning.md` hardcode `aidlc-docs/construction/<stage>/` without `{unit-name}` placeholder. Fix under graph discipline.
- **`--test-strategy` flag removal** — `aidlc-utility.ts` remove `VALID_TEST_STRATEGIES`, `testStrategyOverride`, `effectiveTestStrategy`, all handler paths. Remove flag from SKILL.md, stage-protocol.md, CLAUDE.md. Remove `testStrategy: "Minimal"` from `scope-mapping.json` workshop entry. Remove `TEST_STRATEGY_CHANGED` from audit taxonomy.
- **Audit events** — new: `TESTING_POSTURE_CAPTURED`, `TEST_PLAN_AUTHORED`, `WALKING_SKELETON_INTEGRATION_*` events.
- **Test coverage (required)**:
  - Unit: Testing Posture field validation (methodology enum, RGR bool, gate mode); test-strategy stage artifact schema; scope skip-cascade resolver logic.
  - Feature: 3.5 Test Strategy stage produces expected outputs given posture fixtures; code-generation (3.6) reads on-disk tests correctly; build-and-test (3.7) execution-only path runs; walking-skeleton scoped integration run fires between last Unit code-gen and gate.
  - Integration: methodology-led workflow end-to-end (`/aidlc feature` with TDD + RGR posture) produces passing suite; classic posture path also works; scope skip-cascade integration (bugfix, poc, security-patch) validates via graph walk with no "if exists" fallbacks.
  - Workflow: all 9 scopes run through renumbered Construction; walking-skeleton integration fires in scopes that have multi-Unit walking-skeleton Bolts.
  - Drift guards: stage renumbering complete across stage files, SKILL.md, agent files, docs, state template, fixtures, test fixtures, agents' stage references. Drift-sweep catches any "3.5 code-generation" / "Bolt 3.1-3.5" strings remaining.
  - Regression: existing t30, t39, t45, t47 (construction-bolts) extended for new numbering.
  - Demolition: no `--test-strategy` flag, no `VALID_TEST_STRATEGIES`, no Nyquist/Minimal/Standard/Comprehensive terminology remaining anywhere in source or docs.

---

## v0.9.0 — Deployment architecture *(was v0.7.0 in the pre-reshape spine)*

**Theme:** Project-level deployment planning as a first-class Inception stage, feeding per-Unit Infrastructure Design and Operation-phase stages. Closes the pre-existing gap where per-Unit Infrastructure Design optimised locally without any project-level "we deploy to EKS, here's our BFF pattern" decision.

**User-facing additions**

- **New Inception stage at 2.6** (name decided at implementation). Project-level deployment decisions before per-Unit Infrastructure Design.
- **Stage renumbering.** `units-generation` 2.6 → 2.7; `delivery-planning` 2.7 → 2.8.
- **Shift-left artifacts.** Threat models, SLO catalogs, observability contracts produced at design-time stages, not Operation phase.
- **Stage authored via the harness designer skill** (from v0.7.0 onward); hand-authoring still works.

**Work areas**

- **Stage name decided at implementation time.** Candidates: `platform-architecture`, `target-architecture`, `deployment-planning`. Collides with current `infrastructure-design.md` output `deployment-architecture.md`. Pick a name that avoids collision.
- **`aidlc-claude-code/.claude/skills/aidlc/stages/inception/<stage-name>.md`** (new) — led by aws-platform-agent, supporting architect-agent. Produces `deployment-architecture`, `topology`, `cross-cutting-patterns` (BFF, API gateway, service mesh), `environment-strategy`, `platform-constraints`, `platform-contract`, `gitops-topology`, `finops-model`, `rollout-strategy`, `feature-flag-inventory`, `slsa-provenance` (modernised vocabulary). Ships with Sensors and Learn compartments.
- **Stage renumbering** — `units-generation` 2.6 → 2.7, `delivery-planning` 2.7 → 2.8. New stage at 2.6. Updated everywhere as in v0.8.0.
- **3.4 Infrastructure Design** — update consumes to include `deployment-architecture` (required when present; graceful degrade when scope SKIPs 2.6).
- **Operation-phase consumers** — `deployment-pipeline`, `environment-provisioning` consume `deployment-architecture` directly. Updated.
- **Shift-left artifacts** — `observability-contract` produced at 2.6 Application Design. `slo-catalog` produced at 3.2 NFR Requirements. `cost-model` produced at 3.3 NFR Design. `threat-model` produced at 2.6 Application Design (devsecops-agent support). `sbom` produced at 3.7 Build and Test. `sast-report` / `dast-report` / `sca-report` produced at 3.8 CI Pipeline. Small extensions that surface already-shipped devsecops/operations knowledge.
- **Audit events** — `DEPLOYMENT_ARCHITECTURE_CAPTURED`, `PLATFORM_CONTRACT_PUBLISHED`, `THREAT_MODEL_AUTHORED`, `SBOM_GENERATED`, `SAST_REPORT_GENERATED`, `DAST_REPORT_GENERATED`, `SCA_REPORT_GENERATED`, `SLO_CATALOG_CAPTURED`.
- **Test coverage (required)**:
  - Unit: deployment-architecture artifact schemas.
  - Feature: stage 2.6 produces all declared artifacts under fixture inputs; 3.4 Infrastructure Design reads 2.6 outputs correctly; Operation-phase deployment-pipeline reads platform-level deployment-architecture.
  - Integration: EKS + BFF fixture scenario flows through complete pipeline; scopes that SKIP 2.6 degrade gracefully (3.4 runs without deployment-architecture input, no crash); shift-left artifacts produced at correct design-time stages.
  - Workflow: `/aidlc enterprise` and `/aidlc feature` execute the new 2.6; `/aidlc infra` also executes it.
  - Drift guards: 2.6/2.7/2.8 renumbering clean across stage files, SKILL.md, agent files, docs, state template, fixtures.
  - Regression: t30, t32, t39 extended; t47 construction-bolts unchanged (operates at 3.x).
  - Security/observability shift-left: test that threat-model is produced at 2.6 not 4.5; slo-catalog at 3.2 not 4.6; observability-contract at 2.6 not 4.4.

---

## v0.10.0 — Cross-workflow observer + ralph driver *(was v0.8.0 in the pre-reshape spine)*

**Theme:** Cross-workflow learning. The single-workflow learning loop already shipped in v0.5.0 (gate ritual, memory.md, runtime-graph). v0.10.0 adds the **cross-workflow observer** that reads `runtime-graph.json` across many workflow runs, finds patterns ("sensor X failed 8 times across 12 workflows"), and proposes sensor / rule / knowledge candidates. Plus the **ralph loop driver** that wraps stage execution against deterministic sensors when a Learn binding selects it.

**User-facing additions**

- **Observer proposals surface across workflows.** New files `aidlc-docs/sensor-proposals.md`, `rule-proposals.md`, `knowledge-proposals.md` populate when patterns repeat across multiple workflow runs.
- **Approval flow command.** `bun .claude/tools/aidlc-utility.ts promote-learning <id>` subcommand moves approved proposals into rules / sensors / knowledge.
- **Ralph loop driver becomes available.** Loop bindings activate ralph against deterministic sensors at bound stages. Audit emits `LOOP_STARTED`, `LOOP_ITERATION`, `LOOP_TERMINATED`.
- **`/loop` skill scheduled scans** activate observer runs.
- **Loop bindings authored via the harness designer skill** (extended in-release per the lockstep commitment); hand-authoring still works.

**Work areas**

- **`aidlc-claude-code/.claude/tools/aidlc-loop.ts`** (new) — ralph driver. Two implementations: interactive (Stop-hook based, modelled on Claude Code's `ralph-loop` plugin) and headless (subprocess via `claude --print`). Interactive in main workspace or inside v0.4.0's worktrees. Headless for `--test-run` and automated runs.
- **`aidlc-claude-code/.claude/hooks/aidlc-ralph-enforcer.sh`** (new) — Stop hook. Reads active-loop state. Fires sensors against just-written artifact. On sensor-fail emits `{decision: block, reason: remediation_prompt}` per Claude Code Stop-hook protocol. On sensor-green or iteration cap, allows exit.
- **Ralph-loop plugin coexistence** — detect `.claude/ralph-loop.local.md` and yield if the plugin's loop is active in the current session. Use session-isolation field in AI-DLC's own active state to avoid cross-wires. Integration test covers both-installed case.
- **`aidlc-claude-code/.claude/tools/aidlc-observer.ts`** (new) — reads `runtime-graph.json` across multiple workflow runs (the v0.5.0 substrate). Matches cross-workflow patterns against observer rules. Proposes candidates to three destination files: `aidlc-docs/sensor-proposals.md`, `aidlc-docs/rule-proposals.md`, `aidlc-docs/knowledge-proposals.md`. Dedupe by signal hash. Minimum N occurrences (default 2) before a proposal is written. **The observer is genuinely cross-workflow** — single-workflow learnings are already captured by the v0.5.0 learning loop's gate ritual. v0.10.0's observer adds the "this pattern repeats across runs" detection layer on top.
- **Observer rules** — initial set: `sensor-never-correlates`, `loop-never-converges`, `rule-violated-n-times` (cross-workflow). The `MEMORY_EMPTY` event from v0.5.0 also feeds an observer rule for "diary discipline degrading".
- **Approval flow** — observer writes to proposals files. Session start or `/loop` skill scheduled scan. `aidlc-utility.ts promote-learning <id>` subcommand moves approved proposals into rules, sensor registry, or knowledge per proposal type.
- **Loop bindings** — bound to specific stages (e.g., `code-generation`, `build-and-test`, `infrastructure-design`) where deterministic sensors have a strong fit. Per-stage `max_iterations`, per-phase sensors. Authored via the harness designer skill (per the v0.7.0 lockstep commitment).
- **Strong-fit stages initial bindings** — stages with deterministic post-condition scripts: build-and-test, code-generation (per-unit), infrastructure-design, nfr-design (security aspects), pipeline-deploy (ci-pipeline), observability-setup, plus a few more selected at implementation. Weak-fit stages (requirements, design, mockups) retain approval gates unchanged — they have no deterministic success criterion.
- **Audit events** — new: `LOOP_STARTED`, `LOOP_ITERATION`, `LOOP_TERMINATED`, `OBSERVER_FIRED`, `PROPOSAL_GENERATED`, `PROPOSAL_APPROVED`, `PROPOSAL_REJECTED`.
- **`docs/guide/17-learn.md`** (new), **`docs/reference/17-learn-system.md`** (new) — reserved slots above the current chapter-16 top of each tree.
- **Honour-system `<promise>`** — ralph terminates on sensor-green primarily, with `<promise>` as complementary signal. No tamper detection yet — document gaming as known limitation for this release.
- **Test coverage (required)**:
  - Unit: ralph driver state transitions (start → iterate → converge / cap-hit / abort); observer pattern-matcher; signal-hash dedupe logic; approval-flow promotion paths (guardrail / sensor / knowledge).
  - Feature: `aidlc-loop.ts` interactive and headless modes; `aidlc-observer.ts` scan / list / propose subcommands; `aidlc-utility.ts promote-learning` subcommand; Stop-hook emits `{decision: block}` correctly; Stop-hook yields when `.claude/ralph-loop.local.md` exists.
  - Integration: ralph converges on a fixture within iteration cap; ralph hits cap and escalates cleanly; observer generates proposal from fixture audit with 2+ occurrences of a pattern; approval flow moves proposal into target file; ralph-loop-plugin coexistence under both-installed configuration.
  - Workflow: 3.6 code-generation optionally wraps in ralph when Learn compartment binds it; `--test-run` runs headless ralph deterministically.
  - Drift guards: Learn compartment schema kept in sync; observer rule schema validated.
  - Failure path: ralph iteration cap-hit emits the right audit event; observer dedupe doesn't double-count under race conditions; sensor-registry-change detection during a loop iteration (future-proof for v0.11.0 tamper detection).

---

## v0.11.0 — LLM sensors + autoresearch *(was v0.9.0 in the pre-reshape spine)*

**Theme:** Inferential sensors (LLM-as-judge) and the second loop driver (autoresearch, variant+score). Observer retirement mechanism active from day 1 of LLM-sensor deployment. **Harness designer extends in-release** to author LLM sensors (per the v0.7.0 lockstep commitment).

**User-facing additions**

- **LLM sensor findings appear in gate summaries** (advisory-only by default). `testability`, `invest-check`, `contradiction-scan`, `adr-quality` ship as initial set.
- **Autoresearch as a loop driver.** When stage Learn binding selects autoresearch, N variants generate via parallel Task calls; LLM-judge rubric scores; framework picks best.
- **Tamper detection.** Sensor registry / test files snapshot at loop start; mid-loop edits emit `SENSOR_TAMPERING_DETECTED`.
- **Harness designer extends in-release** to author LLM sensors; hand-authoring still works.

**Work areas**

- **`.claude/sensors/llm/`** (new directory) — initial LLM sensors: `testability`, `invest-check`, `contradiction-scan`, `adr-quality`. Each with manifest (`id`, `kind: llm`, `model`, `applies_to`, `description`, `category`, `icon`, `input_schema`, `output_schema`, optional `max_tokens`).
- **`aidlc-sensor.ts`** — extend dispatcher to fire LLM sensors via Task tool with rubric prompts. Budget model: per-sensor `max_tokens` cap, per-stage cap, depth-derived default. Haiku default model.
- **`aidlc-loop.ts`** — autoresearch driver. Generates N variants via parallel Task calls. Scores each via LLM-judge rubric. Picks best. Bounded by depth caps.
- **Ralph-RGR (phase-aware)** — `aidlc-loop.ts` gains red/green/refactor phase state. Learn compartment binding example: stage 3.6 code-generation with phase-specific sensors. On regression in refactor phase, revert-and-retry bounded by iteration cap.
- **Tamper detection** — diff-watching infrastructure. Snapshot test files and sensor registry state at loop start; re-snapshot per iteration; emit `SENSOR_TAMPERING_DETECTED` on delta. Complements checksum-of-planned-test-set from the test-planning stage.
- **Observer retirement rule** — `sensor-never-correlates` observer rule (shipped in v0.10.0) watches for LLM sensors firing but never correlating with gate rejection. After N such firings, proposes deprecation. Prevents LLM-sensor fatigue.
- **LLM sensor advisory-only default** — LLM sensors do not block gates in Inception. Computational sensors in Construction can block.
- **Scheduling** — `aidlc-sensor.ts` dispatcher runs deterministic sensors first; only fires LLM sensors when deterministic layer passes. Operationalises Fowler's deterministic-first-then-LLM-selective principle.
- **Audit events** — new: `PHASE_RED_COMPLETE`, `PHASE_GREEN_COMPLETE`, `PHASE_REFACTOR_COMPLETE`, `SENSOR_TAMPERING_DETECTED`, `VARIANT_GENERATED`, `VARIANT_SCORED`, `VARIANT_SELECTED`.
- **Test coverage (required)**:
  - Unit: LLM sensor manifest schema; autoresearch variant-scoring logic; ralph-RGR phase state machine; tamper-detection snapshot diff logic.
  - Feature: `aidlc-sensor.ts` LLM-mode dispatch via Task tool; `aidlc-loop.ts autoresearch` driver parallel variant generation; Stop-hook rejects `<promise>` when sensors fail (falsifiable promise); diff-watch infrastructure flags edits to test files and sensor registry.
  - Integration: fixture LLM sensor produces scored rubric deterministically with cached model response; autoresearch picks highest-scoring variant; ralph-RGR executes red → green → refactor on fixture with regression that reverts correctly; tamper-detection fires on fixture that edits a test mid-loop; observer (from v0.10.0) proposes deprecation of a consistently-wrong LLM sensor.
  - Workflow: deterministic-first-then-LLM scheduling honoured.
  - Budget guards: per-sensor max_tokens cap, per-stage cap, depth-derived default all enforced; budget-override emits audit event.
  - Drift guards: LLM sensor manifests conform to schema; every LLM sensor has an `applies_to` that resolves to a real artifact type.
  - Gaming protection: tamper-detection fixture covers all three known vectors — modify tests, skip/xfail failing tests, edit sensor config; each emits correct `SENSOR_TAMPERING_DETECTED` variant.

---

## v0.12.0 — Phase 0 Harness Setup + fitness contract compiler *(was v0.10.0 in the pre-reshape spine)*

**Theme:** Harness engineering as a first-class phase. Bootstrap for every project. Fitness contract DSL + compiler emits paired rules and sensor bindings from one source. **Harness designer extends in-release** to author fitness contracts (per the v0.7.0 lockstep commitment).

**User-facing additions**

- **New Phase 0 sub-stages** (0.4 - 0.10). Users running fresh-work scopes (`enterprise`, `mvp`, `poc`, `infra`, `workshop` first run) walk through team-knowledge capture, project-rules seed, fitness-contract draft, sensor selection, coherence check, learn-budget calibration. Brownfield runs include re-calibration (0.7).
- **`--calibrate-harness` flag** (opt-in for re-calibration outside Phase 0).
- **`bun .claude/tools/aidlc-fitness.ts` command.** `compile` / `validate` / `list` subcommands consume `aidlc-docs/harness-setup/fitness-contract-draft/contract.md` and emit rules + sensor bindings from one source.
- **Harness designer extends in-release** to author fitness contracts; hand-authoring still works.

**Work areas**

- **Phase 0 rename** — `Initialization` becomes `Harness Setup`. Stages 0.1, 0.2, 0.3 stay as workspace-scaffold, workspace-detection, state-init. Add stages 0.4 through 0.10 as the setup sub-stages.
- **New sub-stages** under `aidlc-claude-code/.claude/skills/aidlc/stages/harness-setup/`:
  - `0.4 team-knowledge-capture` — interview flow, populates `aidlc-docs/knowledge/`.
  - `0.5 project-guardrails-seed` — initial tech-stack and convention rules.
  - `0.6 fitness-contract-draft` — architecture rules. Input to the compiler.
  - `0.7 re-calibration` — brownfield only: observe existing code and derive proposals for **the harness** (not for agent personas). Proposals route by type per the v0.5.0 learning-loop heuristic: rules → `.claude/rules/aidlc-project.md` (scope picked by user at affirmation gate); domain facts → team knowledge (`aidlc-docs/knowledge/<agent>/`, scoped by agent name but orthogonal to the persona file); verification patterns → sensor registry; loop/budget tuning → learn registry. The 11 agent persona files under `.claude/agents/` stay unchanged — they are framework code, not a learning target. Mechanism: subagent flow where developer-agent scans code for patterns and architect-agent synthesises proposals; every proposed item requires human approval before landing. Marked experimental in v0.12.0; opt-in via `--calibrate-harness` flag; auto-derivation thresholds (e.g., 95%+ pattern frequency) are advisory-only.
  - `0.8 sensor-selection` — framework sensors → project bindings + parameters.
  - `0.9 coherence-check` — every guardrail has a paired sensor; gaps flagged.
  - `0.10 learn-budgets` — loop budgets calibrated to project reality.
- **Minimal depth contract** — every Phase 0 sub-stage has a Minimal depth that produces something usable (e.g., 0.4 at Minimal is three questions). Retrofit pattern onto existing stages as a side-effect.
- **Orchestrator check** — at workflow start, check `aidlc-state.md` for harness-setup completion. If not done, insist on it.
- **Scope mapping update** — scopes that imply harness-done (bugfix, refactor, security-patch, feature after first run) skip Phase 0. Scopes that imply fresh work (enterprise, mvp, poc, infra, workshop first run) execute it.
- **`aidlc-claude-code/.claude/tools/aidlc-fitness.ts`** (new) — fitness contract compiler. Parses `aidlc-docs/harness-setup/fitness-contract-draft/contract.md`, emits guardrail entries and sensor bindings from each rule. One source of truth; no drift between feedforward and feedback halves. This is **coherence by construction** — closes Fowler's architecture-coherence gap structurally, not via a semantic check.
- **Fitness contract schema** — YAML or markdown with structured blocks. Each rule: name, description, guardrail-text, sensor-ids (deterministic and llm), thresholds, applies-to. Compiler validates schema.
- **Three-dimension contract model** — one contract artifact per Fowler regulation dimension, all compiled via the same model: **architecture fitness** → `fitness-contract.md` authored at stage 0.5 (project-scoped, setup once, drift-updated); **behaviour** → test-planning output from v0.6.0 (feature-scoped, every feature has its own); **maintainability** → linter configs surfaced as bindings, read by stage 0.7 sensor-selection. Three subjects, three contracts, one compile model.
- **Partial-run recovery for Phase 0** — users must be able to re-enter Phase 0 stage-by-stage without losing prior work. Existing `--stage` jump covers the mechanism; Phase 0 sub-stages get explicit UX treatment in the `/aidlc-calibrate` and `/aidlc-recalibrate` skills (shipped via the v0.6.0 skill recomposition surface as scope-runners).
- **Recalibration triggers** — observer rule (`drift-exceeds-threshold` → propose recalibration), periodic (`/loop 90d /aidlc --harness-check`), user-initiated (`/aidlc --recalibrate`).
- **Audit events** — new: `HARNESS_SETUP_STARTED`, `HARNESS_SETUP_COMPLETED`, `FITNESS_CONTRACT_COMPILED`, `RECALIBRATION_TRIGGERED`, `RECALIBRATION_PROPOSED`.
- **Test coverage (required)**:
  - Unit: fitness-contract parser; contract-to-guardrails compiler; contract-to-sensor-bindings compiler; re-calibration pattern detector; Minimal-depth question reducer per sub-stage.
  - Feature: `aidlc-fitness.ts` compile / validate / list subcommands; each Phase 0 sub-stage produces expected artifacts for greenfield and brownfield fixtures; recalibration triggers.
  - Integration: greenfield fixture runs stages 0.1 → 0.9 (skip 0.7); brownfield fixture runs stages 0.1 → 0.10 with RE-calibration producing ≥1 proposal; fitness-contract round-trips (draft → compile → emitted guardrails/sensors match expected); coherence check detects a guardrail missing its paired sensor; learn-budgets adapt to fixture test-suite duration.
  - Workflow: scopes that skip Phase 0 (feature after first run, bugfix) don't regress; scopes that require Phase 0 (enterprise first run, mvp first run, infra, workshop) insist on it.
  - Drift guards: Phase 0 sub-stage numbering consistent across stage files, state template, scope-mapping, docs; fitness-contract schema and compiler output schema validated.
  - Minimal-depth contract: every Phase 0 sub-stage has a Minimal depth variant with ≤3 questions; integration test exercises each.

---

## v1.0.0 — When reality forces a breaking change

**Theme:** **1.0 happens when reality forces a breaking change, not on a fixed schedule.** Until then, ship `v0.X.0` and earn 1.0 through use. The framework is a customisation surface; by definition it always grows. There's no "we're done" moment that justifies a 1.0 cut on calendar grounds — only the moment when an existing surface has to break in a way that warrants a major bump.

**Work areas (when the cut happens)**

- Stability promise in force. Published in v0.3.0; the policy now lives inline in the [artifact-vocabulary chapter](docs/reference/16-artifact-vocabulary.md).
- All experimental features labelled in their manifest frontmatter and docs.
- `CHANGELOG.md` records v1.0.0 as a cumulative changelog across v0.3.0 through the last v0.X.0 minor that preceded the cut.
- `public` branch update decision: at v1.0.0 cut, snapshot main to `public`. Decide policy for subsequent releases (every minor? every patch? only major?) at cut time.
- Announce internally.
- **Test coverage (required for the tag)**:
  - Full test suite green across all tiers (unit, feature, integration, workflow, drift-sweep) via the parallel runner.
  - Every release's test deliverable from v0.3.0 onward still passing on main.
  - At least two consecutive dogfood runs (at least one greenfield, at least one brownfield) produce no BLOCKER-level issues before the rc.
  - v1.0.0 tag cuts only after rc bakes for at least one additional dogfood cycle.
  - Audit event count test reflects the cumulative total (starting from 41 in v0.3.0, growing with each release).

Post-1.0 research tracks open as 2.0 candidates. Whatever scope of this roadmap has shipped lands in 1.0; 2.0 starts from there.

---

## Work order (first things first)

v0.3.0, v0.4.0, and v0.5.0 are shipped (tagged on main; full per-MR detail in their respective issues #62 / #75 / #80 and CHANGELOG entries). The active queue runs in dependency order from v0.6.0 forward; each release ships through its own per-release MR plan (one per release, one issue per plan).

1. **v0.6.0 — Skill recomposition.** Per-release issue opens now that v0.5.0 has shipped.
2. **v0.7.0 — Designer skills.** Per-release issue opens when v0.6.0 ships.
3. **v0.8.0 — Testing strategy.**
4. **v0.9.0 — Deployment architecture.**
5. **v0.10.0 — Cross-workflow observer + ralph driver.**
6. **v0.11.0 — LLM sensors + autoresearch.** Includes harness-designer extension.
7. **v0.12.0 — Phase 0 Harness Setup + fitness contract compiler.** Includes harness-designer extension.

Each release opens after the prior one ships clean. Same pattern per release: per-release issue → per-MR sequence within the issue → release tag.

---

## Open decisions (parked until they block)

- **Skill-recomposition packaging boundary** (v0.6.0). Where do hooks live when the orchestrator is its own capability skill, separate from the entry-point skill? The orchestration capability skill needs PostToolUse / PreCompact / SubagentStop hooks today wired to the entry-point skill's frontmatter. Resolved at v0.6.0 implementation.
- **Designer-skill API surface** (v0.7.0). Designer skills read graph state and write source files. The exact mechanism (CLI subprocess to `aidlc-graph.ts` + direct file writes? or a higher-level designer-API abstraction?) is open. Resolved at v0.7.0 implementation.
- **Deployment architecture stage name** (v0.9.0). Candidates `platform-architecture` / `target-architecture` / `deployment-planning`; collides with current `infrastructure-design.md` output. Resolved at v0.9.0 implementation.
- **Cascade-guard re-entry sentinel mechanism for ralph** (v0.10.0) — prevent infinite hook loops during loop iterations.
- **`public` branch update policy** (v1.0.0 cut decision).

---

## What this plan explicitly does NOT include

- Migration tooling for end-users across releases. User count is low; not worth building.
- Rollback / revert guides per release.
- Feature-flag graduation policy (flags are per-release pragmatic, not a framework).
- Calendar-based timelines or deadlines.
- A fixed v1.0.0 cut date. 1.0 happens when reality forces a breaking change, not on a schedule.
- A long-lived 1.0 branch. Main evolves. Tags cut releases.
- **Visual designer GUI** — the v0.7.0 designer skills cover authoring; the visual GUI on top of them defers to Post-1.0 extension vectors.
- Cross-tool emitters (Kiro CLI, Cursor, Copilot) — post-1.0.
- Parallel stage execution beyond today's parallel Bolt batches — post-1.0.
- Replacement-extension override primitive, strict black-box stage abstraction, cross-stage invariant library, persona-level learning promotion — all post-1.0.

---

## Post-1.0 extension vectors

Known future directions that 1.0's foundations enable but don't deliver. Named here so 1.0 decisions stay compatible with them.

- **Visual designer GUI** — a graphical UI on top of the v0.7.0 designer skills. The skills are the authoring surface that ships pre-1.0; the GUI renders the same `stage-graph.json` + `runtime-graph.json` substrate as a node-and-edge canvas with inspector panels. Stack decided post-1.0 (candidates: React + JSON-RPC to bun CLI, Backstage plugin, standalone web app). Live connector validation, dry-run preview. Requires the v0.7.0 designer-skill API surface (read graph + write source files) — the GUI just dispatches into the same skills.
- **Init-time harness setup wizard** — `/aidlc --init` today scaffolds `aidlc-docs/` (stages 0.1–0.3). Extending `--init` to drive the full Phase 0 Harness Setup (0.4–0.10 from v0.12.0) as a first-run wizard is a natural next step. The orchestrator check from v0.12.0 ("has harness setup run for this project?") already supports this framing — the wizard is the UX on top.
- **`/aidlc --claim-bolt <slug>` utility** — automates the manual `aidlc-worktree create` + `git push bolt-<slug>` claim recipe shipped in v0.4.0's workshop mode. Candidates for inclusion: better error messages on first-push-wins race, audit-only offline mode for participants without network at claim time, automated stale-claim detection on the shared remote. Will ship in a future minor when a real workshop dogfood surfaces concrete requirements; until then, the manual recipe in `docs/guide/workshop-mode.md` is the contract.

**Design implication for 1.0:** the v0.7.0 designer skills should favour explicit API surfaces (read graph state, write source files via deterministic tools) over implicit conventions. If the designer-skill API is built narrowly, the post-1.0 visual GUI becomes an expensive retrofit. Document this in the v0.7.0 implementation notes.

None of these are in 1.0. All of them become tractable because 1.0 ships data-driven scopes/agents/graph, two compiled artefacts, typed contracts, and three designer skills as authoring surface.
