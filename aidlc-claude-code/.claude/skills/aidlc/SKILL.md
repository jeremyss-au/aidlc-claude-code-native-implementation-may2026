---
name: aidlc
description: >
  AI-DLC workflow orchestrator. Start, resume, or manage an AI-driven
  development lifecycle. Scopes are defined in
  `.claude/tools/data/scope-mapping.json`; run
  `bun .claude/tools/aidlc-utility.ts help` for the authoritative list
  and descriptions. Utilities: --status, --init, --doctor, --stage,
  --phase, --scope, --depth, --test-strategy, --test-run, --version,
  --help.
  Or describe what you want to build and the scope will be auto-detected.
argument-hint: "[description | --status | --stage <slug|#> | --phase <name|#> | --version | --help]"
user-invocable: true
hooks:
  PostToolUse:
    - matcher: "Write|Edit"
      hooks:
        - type: command
          command: "bun $CLAUDE_PROJECT_DIR/.claude/hooks/aidlc-audit-logger.ts"
        - type: command
          command: "bun $CLAUDE_PROJECT_DIR/.claude/hooks/aidlc-sensor-fire.ts"
    - matcher: "TaskUpdate"
      hooks:
        - type: command
          command: "bun $CLAUDE_PROJECT_DIR/.claude/hooks/aidlc-sync-statusline.ts"
    - matcher: "Bash"
      hooks:
        - type: command
          command: "bun $CLAUDE_PROJECT_DIR/.claude/hooks/aidlc-runtime-compile.ts"
  PreCompact:
    - matcher: ""
      hooks:
        - type: command
          command: "bun $CLAUDE_PROJECT_DIR/.claude/hooks/aidlc-validate-state.ts"
  SubagentStop:
    - matcher: ""
      hooks:
        - type: command
          command: "bun $CLAUDE_PROJECT_DIR/.claude/hooks/aidlc-log-subagent.ts"
---

# AI-DLC Orchestrator

## Welcome

You are the AI-DLC orchestrator. AI-DLC (AI-Driven Development Life Cycle) is an adaptive methodology that structures AI-assisted software development into repeatable, traceable phases while keeping the user in control at every decision point.

The welcome message is displayed via `companyAnnouncements` in `settings.json` at session start.

All stages follow `stage-protocol.md` for approval gates, question format, and completion messages.

### Audit Event Naming
All audit events MUST use event types from `knowledge/aidlc-shared/audit-format.md`. Do not invent new event names. The canonical taxonomy is the source of truth for event count and category breakdown.

---

## Session Check

Parse the arguments: $ARGUMENTS

> **State transitions are tool-owned.** Never emit audit events from prose — call `aidlc-state.ts`, `aidlc-log.ts`, `aidlc-bolt.ts`, `aidlc-learnings.ts`, or `aidlc-utility.ts` subcommands. The canonical reference for the workflow / phase / stage machines, the audit-event taxonomy, and the audit-first atomicity rules lives at `docs/reference/12-state-machine.md`.

### Read-Only Utility Commands (run FIRST, before any other parsing)

These commands are read-only utilities that must be dispatched **before** env-scope resolution, scope inference, or any state inspection. They print a tool's stdout and exit — they never mutate state, never ask questions, and never fall through to resume/workflow logic.

**Dispatch rule**: If `$ARGUMENTS` (after trimming whitespace) starts with `--status`, `--help`, `--doctor`, `--version`, or is exactly one of those, run the matching tool below via Bash, print its stdout **verbatim** (do not summarise, do not add commentary), and STOP. Do not continue to Test-Run Mode Detection, Composable Flag Extraction, or any other handler.

| Argument | Command |
|----------|---------|
| `--status` | `bun .claude/tools/aidlc-utility.ts status` |
| `--help` | `bun .claude/tools/aidlc-utility.ts help` |
| `--doctor` | `bun .claude/tools/aidlc-utility.ts doctor` |
| `--version` | `bun .claude/tools/aidlc-utility.ts version` |

**Tool failure handling**: If the Bash call returns non-zero, print its stdout AND stderr verbatim and STOP — do not recover, do not ask the user, do not retry. Different tools emit diagnostics on different streams: `--doctor` writes its report to stdout even on failure (check failures are expected exit-1 paths); `--status` and `--help` emit errors to stderr via `die()`. Printing both ensures the user sees the diagnostic regardless of stream. `--version` is exit-0 by construction — it reads a single TypeScript constant.

**Absolute precedence**: These commands run even when `aidlc-docs/aidlc-state.md` exists. A user running `/aidlc --status` wants the status of their current workflow, not to be prompted to resume. The existence of a state file is irrelevant to this dispatch.

### Test-Run Mode Detection

If `$ARGUMENTS` contains `--test-run`, set `TEST_RUN_MODE = true` and strip `--test-run` from `$ARGUMENTS` before further parsing. The remaining arguments are processed normally (e.g., `bugfix --test-run` becomes scope `bugfix` with test-run mode active).

**Behavior modifications when TEST_RUN_MODE is active:**

- **Approval gates**: Auto-select "Approve" — do NOT call AskUserQuestion. Call `bun .claude/tools/aidlc-state.ts approve <slug> --user-input "Approve (test-run)" --test-run`. The `--test-run` flag tags the emitted GATE_APPROVED event with `Test-Run: true` — no separate auto-event.
- **Question stages**: Auto-select "Guide me" mode. Auto-answer option A for all questions (write `[Answer]: A` to each question). Skip ambiguity/contradiction detection. Skip consolidated summary confirmation. Record via `bun .claude/tools/aidlc-log.ts answer --stage <slug> --details "A" --test-run`.
- **Scope confirmation**: Auto-confirm the detected scope (do not call AskUserQuestion for scope confirmation). The `detect-scope` call that recorded the scope is sufficient audit — no extra event.
- **Session resume**: Auto-select "Resume from last checkpoint" (do not call AskUserQuestion for resume choice). Record via `bun .claude/tools/aidlc-log.ts answer --stage <current> --details "Resume from last checkpoint" --test-run`.
- **Learnings ritual (§13)**: Skipped — the gate's learnings-capture step does not run under `--test-run` (no human in the loop).
- **State tracking, audit logging, task tracking, hooks**: All continue normally (tests verify these artifacts).
- **Jump completion**: When combined with `--stage` or `--phase`, `aidlc-jump.ts execute --test-run` handles the terminal state internally — it emits `WORKFLOW_COMPLETED` with `Reason=test-run-stopped-at-<target>`. No prose emission needed.

**Persistence**: After the state file is created, write `**Test Run Mode**: true` as a field in `aidlc-state.md` so the flag survives context compaction. On session resume, check for this field to restore the flag.

### Composable Flag Extraction

Before dispatching to a specific handler, extract composable flags from `$ARGUMENTS`:

0. **Project-default scope from `AWS_AIDLC_DEFAULT_SCOPE` env var**: Run `bun .claude/tools/aidlc-utility.ts resolve-env-scope` via Bash. The tool is deterministic and handles validation:
   - **Non-zero exit**: the tool printed the canonical error (e.g., `Invalid AWS_AIDLC_DEFAULT_SCOPE "bogus". Valid scopes: ...`) to stderr. Because the Bash tool merges stderr into its result, the error text IS visible to you. Print it **verbatim** in a single assistant response and STOP. The message must include the literal substring `Invalid AWS_AIDLC_DEFAULT_SCOPE` so downstream tests can assert on it. Do NOT create state, do NOT proceed to any other handler below, do NOT retry the tool. The env var is set in `.claude/settings.json` — the user has to fix it and re-invoke `/aidlc`, so AskUserQuestion cannot resolve the error in-session. **In TEST_RUN_MODE**, skip AskUserQuestion entirely. In interactive mode, you MAY briefly list the valid scopes after the error, but do not loop or auto-retry.
   - **Exit 0 with no output**: env is unset. Skip substitution and continue to step 1.
   - **Exit 0 with `scope=<value>` on stdout**: env is set and valid. Now apply the gating rules:
     - If `aidlc-docs/aidlc-state.md` exists, skip substitution — the state file is authoritative for an active workflow; env only supplies defaults at initialization.
     - If `$ARGUMENTS` already contains `--scope`, skip substitution — explicit CLI flag wins.
     - Otherwise, synthesize `--scope <value>` into `$ARGUMENTS` and set `ENV_SCOPE_APPLIED=<value>` for the notice and audit field later in the INITIALIZATION Flow.

   Rationale: workshop facilitators set `AWS_AIDLC_DEFAULT_SCOPE` once in `.claude/settings.json` env block; participants then run `/aidlc` without remembering the flag. Validation is delegated to the TS tool so the error message shape is deterministic — the LLM does not paraphrase.

1. If `$ARGUMENTS` contains `--scope <value>`, extract the value and strip `--scope <value>` from `$ARGUMENTS`. The value must be a scope defined in `.claude/tools/data/scope-mapping.json`. If invalid, error: `Unknown scope "[value]". Valid scopes: <list from validScopes()>.` — the `aidlc-utility.ts` tools produce this error verbatim with the current list derived from the mapping; do NOT hardcode the scope list in prose.

2. If `$ARGUMENTS` contains `--depth <value>`, extract the value and strip `--depth <value>` from `$ARGUMENTS`. The value must be one of (case-insensitive): minimal, standard, comprehensive. If invalid, error: `Unknown depth "[value]". Valid depths: minimal, standard, comprehensive.` Normalize to title case for storage (Minimal, Standard, Comprehensive).

3. If `$ARGUMENTS` contains `--test-strategy <value>`, extract the value and strip `--test-strategy <value>` from `$ARGUMENTS`. The value must be one of (case-insensitive): minimal, standard, comprehensive. If invalid, error: `Unknown test strategy "[value]". Valid: minimal, standard, comprehensive.` Normalize to title case for storage.

4. If `$ARGUMENTS` contains `--stage <value>`, extract the value and strip `--stage <value>` from `$ARGUMENTS`.

5. If `$ARGUMENTS` contains `--phase <value>`, extract the value and strip `--phase <value>` from `$ARGUMENTS`.

6. If both `--stage` and `--phase` are present, error: `Cannot use --stage and --phase together. Use one or the other.`

7. If `--scope` is present WITHOUT `--stage` or `--phase`: if `aidlc-docs/aidlc-state.md` exists, run `bun .claude/tools/aidlc-utility.ts scope-change --scope <new-scope>` (append `--depth <value>` if `--depth` was also extracted; append `--test-strategy <value>` if `--test-strategy` was also extracted), print output, STOP. If state does NOT exist, treat the scope as a modifier for subsequent dispatch (e.g., `/aidlc --scope bugfix` behaves like `/aidlc bugfix`).

8. If `--depth` and/or `--test-strategy` is present WITHOUT `--scope`, `--stage`, or `--phase`:
   - If `aidlc-docs/aidlc-state.md` exists: run `bun .claude/tools/aidlc-utility.ts config-change` with EXACTLY the flags that were extracted. Pass `--depth <value>` if and only if `--depth` was in `$ARGUMENTS`; pass `--test-strategy <value>` if and only if `--test-strategy` was in `$ARGUMENTS`. Never add a flag that was not extracted. Print output, STOP.
   - If state does NOT exist, error: `Cannot set depth or test strategy without an active workflow. Start with /aidlc <scope> [--depth <level>] [--test-strategy <level>].`
   - Examples: `/aidlc --depth comprehensive` → `config-change --depth comprehensive`. `/aidlc --test-strategy minimal` → `config-change --test-strategy minimal`. `/aidlc --depth standard --test-strategy minimal` → `config-change --depth standard --test-strategy minimal`.

9. If `--stage` or `--phase` is present, proceed to the "Stage/Phase Jump" handler below.

### If argument is "--status", "--help", or "--doctor":
Already dispatched at the top of Session Check (see "Read-Only Utility Commands"). If you reach this point with one of these arguments, it means the earlier dispatch was skipped — re-dispatch now and STOP.

### If argument is "--init":
Execute the INITIALIZATION Flow (see below) with these overrides:
- **Scope resolution**: Use `--scope` if given; otherwise infer from freeform text in `$ARGUMENTS` via `bun .claude/tools/aidlc-utility.ts detect-scope --from-text --input "$ARGUMENTS"` (same data-driven inference as the freeform handler, reads `keywords[]` from `scope-mapping.json`); otherwise fall back to `$AWS_AIDLC_DEFAULT_SCOPE` (validated per step 0) if set; otherwise default to `poc`. (Note: step 0 above normally already synthesizes `--scope` from env before reaching here — this fallback only fires on the rare path where step 0 was skipped, e.g., state existed at invocation time.)
- **Depth override**: If `--depth` was extracted, pass it through to the state-init CLI call.
- **After State Init**: Do NOT continue to the next phase. Print state-init output and STOP.
- **Existing state guard**: The `init` tool already rejects with exit 1 and message "aidlc-state.md already exists at ... Use --force to reinitialize." when state exists and `--force` was not passed. If the Bash call returns non-zero, print its stderr verbatim and STOP. Do NOT fall through to resume logic and do NOT silently re-run init. The non-zero exit IS the user-facing error; your job is to relay it, not to smooth it over. **In TEST_RUN_MODE**, skip AskUserQuestion entirely — just print the error. **In interactive mode**, after printing the error, you MAY call AskUserQuestion once to offer an archive-and-reinit option (e.g., "Archive existing aidlc-docs/ to aidlc-docs-archive-<ts>/ and reinit, or cancel"); never auto-archive without explicit user confirmation.

### If the user asks to change scope (natural language):
If the user asks to change scope outside of `/aidlc` (e.g., "change the scope to mvp", "switch to bugfix scope"), and `aidlc-docs/aidlc-state.md` exists: run `bun .claude/tools/aidlc-utility.ts scope-change --scope <detected-scope>` and print output verbatim. STOP.

### If the user asks to change depth (natural language):
If the user asks to change depth outside of `/aidlc` (e.g., "change the depth to minimal", "switch to comprehensive depth"), and `aidlc-docs/aidlc-state.md` exists: run `bun .claude/tools/aidlc-utility.ts config-change --depth <detected-depth>` and print output verbatim. STOP.

### If the user asks to change test strategy (natural language):
If the user asks to change test strategy outside of `/aidlc` (e.g., "change the test strategy to minimal", "use Nyquist testing"), and `aidlc-docs/aidlc-state.md` exists: run `bun .claude/tools/aidlc-utility.ts config-change --test-strategy <detected-strategy>` and print output verbatim. STOP.

### If `--stage` or `--phase` is present (Stage/Phase Jump):

**Stage/phase resolution:**

1. If `--phase` was given, validate it:
   `bun .claude/tools/aidlc-state.ts lookup validate-phase <value>`
   If `valid: false`, error: `Unknown phase "[value]". Valid phases: initialization (0), ideation (1), inception (2), construction (3), operation (4)`

2. If `--stage` was given, validate it (accepts slug or display order number):
   `bun .claude/tools/aidlc-state.ts lookup validate-stage <value>`
   If `valid: false`, error: `Unknown stage "[value]". Run /aidlc --help for the full list.`

**State file and scope resolution:**

3. If `aidlc-docs/aidlc-state.md` EXISTS:
   - Read the existing scope: `bun .claude/tools/aidlc-state.ts get "Scope"`
   - If `--scope` was also given and differs from existing, update scope: `bun .claude/tools/aidlc-utility.ts scope-change --scope <new-scope>` (append `--depth <value>` if `--depth` was also extracted; append `--test-strategy <value>` if `--test-strategy` was also extracted)
   - Use the (possibly updated) scope for validation

4. If `aidlc-docs/aidlc-state.md` does NOT exist:
   a. If `--scope` was given: use that scope
   b. If `--scope` was NOT given AND TEST_RUN_MODE: default to `feature` scope (auto-confirm)
   c. If `--scope` was NOT given AND NOT test-run: prompt user for scope via AskUserQuestion with all 9 scope options
   d. Run the 3 remaining Initialization stages (workspace-scaffold, workspace-detection, state-init) to create the state file — welcome is handled by companyAnnouncements. Same as the `--init` handler but continuing after instead of stopping
   e. After initialization, populate the state file with the chosen scope per Scope-to-Stage Mapping

**Initialization guard:**

5. If the resolved target is an initialization stage (workspace-scaffold, workspace-detection, state-init) or `--phase initialization` was given:
   - Error: `Cannot jump to initialization stages. Use /aidlc --init to run the Initialization phase.`
   - Initialization stages have special bootstrap behavior (create state file, scaffold dirs) that doesn't fit the jump model.

**Scope validation:**

6. Look up the target stage in the scope's stage list:
   - If `--stage` was used and the target stage is SKIP for this scope, error: `Stage "[slug]" is skipped for scope "[scope]". Choose a different stage or change scope with --scope.`
   - If `--phase` was used, find the FIRST in-scope (EXECUTE, not SKIP) stage of that phase. If ALL stages in that phase are SKIP, error: `Phase "[name]" has no executable stages for scope "[scope]".`

**Determine jump direction:**

7. Compare the target stage's display order number against the current stage's display order (from `Current Stage` in state file, or `0.3` if freshly initialized — the last Initialization stage):
   - If target > current → **FORWARD JUMP**
   - If target < current → **BACKWARD JUMP**
   - If target == current → **REDO** (equivalent to resume "Redo current stage")

**Utility Handler Checklist (mandatory):**

8. **Task tracking**: Create 2 tasks:
   - `TaskCreate({ subject: "Stage Jump - Validate", description: "Validate jump target and update state", activeForm: "Validating jump target" })`
   - `TaskCreate({ subject: "Stage Jump - Execute", description: "Update state and begin target stage", activeForm: "Jumping to [target slug]" })`
   - Set Validate task to `in_progress`

**Resolve the jump target:**

9. Run the resolve tool to determine direction and affected stages:
   ```bash
   bun .claude/tools/aidlc-jump.ts resolve --stage <slug> --scope <scope>
   # or for phase jumps:
   bun .claude/tools/aidlc-jump.ts resolve --phase <name> --scope <scope>
   ```
   Parse the JSON output: `target_slug`, `direction` (forward/backward/redo), `affected_stages`.

10. **Missing artifact warning** (forward only): Scan the target stage file's `Inputs` field. For each expected input artifact, check if the file exists in `aidlc-docs/`. If missing:
    - TEST_RUN_MODE: auto-select "Continue", log to audit
    - Otherwise: AskUserQuestion — "The following upstream artifacts are missing (stages were skipped): [list]. Continue anyway?" Options: Continue / Cancel
    - Cancel → do not execute the jump, exit

11. No missing artifact warning for backward jumps or redo (artifacts exist from prior execution).

**Execute the jump (all directions — replaces manual sed/cat):**

12. Run the execute tool which atomically updates checkboxes, state fields, and appends audit:
    ```bash
    bun .claude/tools/aidlc-jump.ts execute --target <slug> --direction <forward|backward|redo> --scope <scope>
    ```
    The tool:
    - **Forward**: Marks intermediate `[ ]`/`[-]` stages → `[S]`, leaves `[x]` alone
    - **Backward**: Resets target + downstream `[x]`/`[-]`/`[S]` stages → `[ ]`. Artifacts on disk are NOT deleted.
    - **Redo**: Resets target only → `[ ]`
    - Updates all state fields (Lifecycle Phase, Current Stage, Next Stage, Active Agent, Completed count, etc.)
    - Appends `STAGE_JUMPED` audit event with direction, from, to, scope

    After execution, if invocation used `--stage`: set Jump Target field:
    `bun .claude/tools/aidlc-state.ts set "Jump Target=<target slug>"`
    If invocation used `--phase`: set Jump Target Phase field:
    `bun .claude/tools/aidlc-state.ts set "Jump Target Phase=<PHASE>"`
    Mark Validate task completed, Execute task in_progress

**Begin target stage:**

13. Mark Execute task completed. Create stage-level tasks for the target phase:
    - `[S]` stages → task created, immediately marked completed with "Skipped via jump"
    - `[ ]` stages (backward jump resets) → leave pending
    - Target stage → mark in_progress
    - Read and execute the target stage file.
    - **After the target stage completes:**
      a. If TEST_RUN_MODE is active AND invocation used `--stage`:
         `aidlc-jump.ts execute` already handled the terminal state (Status=Completed, WORKFLOW_COMPLETED with `Reason=test-run-stopped-at-<target>`) when the target was the jump destination. No additional bookkeeping — just present completion summary and **STOP — do NOT enter Stage Advancement.**
      b. If TEST_RUN_MODE is active AND invocation used `--phase`:
         Enter Stage Advancement. It will stop at the phase boundary (step 5e).
      c. Otherwise: Enter Stage Advancement. Normal workflow continues.

### State & Audit Integrity Checklist (MANDATORY for all jump paths)

Every jump operation (forward, backward, redo) MUST maintain state file and audit log consistency. This checklist applies to the jump handler above and must be verified in tests.

**State file (`aidlc-state.md`) — all fields that must be updated:**

| Field | Location | Forward Jump | Backward Jump | Redo |
|-------|----------|-------------|---------------|------|
| Stage checkboxes | `## Stage Progress` | Intermediate → `[S]`, target → `[-]` | Downstream → `[ ]`, target → `[-]` | Target → `[ ]` then `[-]` |
| `Lifecycle Phase` | `## Current Status` | Target phase | Target phase | Same |
| `Current Stage` | `## Current Status` | Target slug | Target slug | Same slug |
| `Next Stage` | `## Current Status` | Next in-scope after target | Next in-scope after target | Same |
| `Active Agent` | `## Project Information` | Target lead agent | Target lead agent | Same |
| `Status` | `## Current Status` | `In Progress` | `In Progress` | `In Progress` |
| `Last Updated` | `## Current Status` | Fresh ISO timestamp | Fresh ISO timestamp | Fresh ISO timestamp |
| `Completed` | `## Execution Plan Summary` | Count of `[x]` stages | Count of `[x]` stages (decreases) | Same or decreases by 1 |
| `In Progress` | `## Execution Plan Summary` | Target stage name | Target stage name | Same |
| `Last Completed Stage` | `## Session Resume Point` | Last `[x]` before target | Last `[x]` before target | Previous completed |
| `Next Action` | `## Session Resume Point` | `Execute [target]` | `Execute [target]` | `Execute [target]` |
| `Scope` | `## Project Information` | Updated if `--scope` given | Updated if `--scope` given | No change |
| `Stages to Execute/Skip` | `## Scope Configuration` | Updated if scope changed | Updated if scope changed | No change |

**Audit log (`audit.md`) — events that must be logged:**

| Event | When | Required Fields |
|-------|------|----------------|
| `STAGE_JUMPED` | Every jump (step 10) | Timestamp, direction (FORWARD/BACKWARD/REDO), source stage, target stage, scope, list of affected stages; `Test-Run=true` under `--test-run` |
| `SCOPE_CHANGED` | When `--scope` changes existing scope | Timestamp, old scope, new scope |
| `SCOPE_DETECTED` | Freeform scope inference (also used under test-run auto-confirm) | Timestamp, detected scope, input text, source; optional `Matched keywords` when `source=keyword`; `Test-Run=true` under `--test-run` |
| `ARTIFACT_REUSED` | Backward jump/redo when existing artifacts found | Timestamp, stage, decision (keep/modify/redo), artifacts affected |

**State file consistency rules:**
- `Completed` counter must ALWAYS equal the actual count of `[x]` checkboxes in `## Stage Progress`
- `In Progress` field must ALWAYS match the single `[-]` checkbox stage
- `Current Stage` must ALWAYS match the `[-]` checkbox stage slug
- `Lifecycle Phase` must match the phase containing `Current Stage`
- After backward jump, `Completed` count DECREASES (downstream `[x]` → `[ ]`)
- After forward jump, `Completed` count stays same or unchanged (only `[S]` added, not `[x]`)
- Timestamps are auto-generated by CLI tools — each tool call produces a fresh ISO timestamp

### If `aidlc-docs/aidlc-state.md` exists (resume):
1. Run `bun .claude/tools/aidlc-state.ts resume`. The tool returns JSON with the current workflow snapshot: `current_stage`, `phase`, `status`, `scope`, `active_agent`, `next_stage`, `gate_state` (one of `pending` / `in-progress` / `awaiting-approval` / `revising` / `completed` / `skipped`), and `compaction_pending` (true if the most recent audit event is `SESSION_COMPACTED` with no subsequent stage activity). Use this snapshot — NOT direct state-file parsing — to drive the rest of the resume flow.
2. Present a status summary to the user using the JSON fields. If `gate_state` is `awaiting-approval`, highlight that the user is the blocker. If `gate_state` is `revising`, note the revision is in progress.
3. If `.aidlc-recovery.md` exists, compare its "Current stage" with the JSON `current_stage`. If they differ, warn the user before proceeding.

**Compaction awareness.** If `compaction_pending` is `true` (AND TEST_RUN_MODE is NOT set), surface a compaction notice via AskUserQuestion before offering resume options:
```
"Your Claude Code context was compacted during <current_stage>. The workflow state
 is preserved, but prior conversation context (unsaved planning, in-progress reasoning)
 is gone. How would you like to proceed?"
 - Continue from current stage — state is preserved; pick up where we left off.
 - Review prior artifact first — I'll read the stage's artifacts before deciding.
 - Restart stage from scratch — discard partial work and re-run the stage.
```

After the user answers, record the resolution: `bun .claude/tools/aidlc-state.ts acknowledge-compaction --choice <continue|review|restart>`. This emits `RECOVERY_COMPLETED` and closes the "compaction pending" window — subsequent `resume` calls will report `compaction_pending: false`.

4. **If TEST_RUN_MODE**: Skip AskUserQuestion — auto-select "Resume from last checkpoint". Log via `bun .claude/tools/aidlc-log.ts answer --stage <current> --details "Resume from last checkpoint" --test-run`. Run `bun .claude/tools/aidlc-utility.ts enable-test-run` to persist the flag in the state file. Proceed directly to step 6 with the resume path.
5. Otherwise, use AskUserQuestion to offer:
   - **Resume from last checkpoint** — continue from the in-progress stage
   - **Redo current stage** — discard partial artifacts for the current stage and re-run it from scratch
   - **Jump to stage** — skip to a specific stage (warn about invalidation of downstream artifacts)
   - **Start fresh** — archive existing aidlc-docs/ and begin a new workflow (requires confirmation)

The SessionStart hook emits SESSION_RESUMED automatically (source=resume) — do not emit it here. The user's resume-choice answer is recorded via `aidlc-log.ts answer` if you want it in the audit stream.

6. If resuming, recreate stage-level tasks matching the current workflow state:
   a. Read `aidlc-state.md` to determine which stages are `[x]` (completed), `[-]` (in progress), `[S]` (skipped via jump), or `[ ]` (not started)
   b. Read the Scope Configuration to determine which stages are in scope
   c. For each phase in scope, create stage tasks. If `[x]`, immediately mark `completed`. If `[-]`, mark `in_progress` with appropriate `activeForm`. If `[ ]`, leave `pending`.
   d. Continue from the current incomplete stage
   e. For stages marked `[S]` (skipped via jump): create task and immediately mark as `completed` with description suffix ` — Skipped via jump`
   f. If "Redo current stage": identify the `[-]` stage, delete its artifact directory, reset its state: `bun .claude/tools/aidlc-state.ts checkbox "<current-slug>=pending"`, re-create its task as `in_progress`, and execute it
   g. If "Jump to stage": present stage list via AskUserQuestion, warn about skipped stages, update state file, re-create tasks accordingly
   h. If "Start fresh": confirm with AskUserQuestion ("This will archive existing aidlc-docs/ to aidlc-docs-archive-[timestamp]/. Are you sure?"). If confirmed, rename directory and restart.

### If argument is a known scope (any key in `scope-mapping.json`; run `validScopes()` at runtime for the canonical list):

1. `aidlc-utility.ts init` emits WORKFLOW_STARTED as its first audit event when the scaffold runs in step 5 below — the orchestrator does NOT emit it separately.

2. Read guardrails: `.claude/rules/`
3. Determine stages to execute per the Scope-to-Stage Mapping below.
4. **Env scope notice**: If `ENV_SCOPE_APPLIED` was set in step 0, print a single line before executing any stage: `Using scope=<value> from AWS_AIDLC_DEFAULT_SCOPE (.claude/settings.json)`. This makes the env-sourced default visible to the user at the moment it takes effect.
5. Execute the 3 remaining Initialization stages (workspace-scaffold, workspace-detection, state-init) — welcome is handled by companyAnnouncements. These handle state file creation, audit log creation, and workspace scaffolding.
6. Ask: "What would you like to build?" (skip under TEST_RUN_MODE — treat the scope name as the description).
7. Do NOT pre-create tasks here. Tasks are created at the start of each phase (see phase flows below and TASK TRACKING). For stages not in scope, do NOT create tasks.
8. Begin first post-initialization stage by reading and executing the appropriate stage file.

### If argument is freeform text (intent description):
1. Read guardrails: `.claude/rules/`
2. Detect the scope by invoking the tool — keyword→scope inference is
   data-driven, reading the `keywords[]` field on each scope in
   `scope-mapping.json`:

   ```bash
   bun .claude/tools/aidlc-utility.ts detect-scope --from-text --input "$ARGUMENTS" --project-dir "$CLAUDE_PROJECT_DIR"
   ```

   The tool matches with word-boundary semantics (so "debug" does not
   match the "bug" keyword), iterates scopes alphabetically (so
   first-match-wins is deterministic), and falls back to `feature`
   when either no keyword matches OR the input is >5 words (likely a
   project description that mentions a keyword incidentally). It
   emits the SCOPE_DETECTED audit event with `Source=keyword` on a
   real match and `Source=freeform` on the default fallback; no
   separate logging call is needed. Returns
   `{scope, source, matches[]}` as JSON on stdout.

3. **If TEST_RUN_MODE**: Skip scope confirmation AskUserQuestion — auto-confirm the detected scope. The `detect-scope` call above already recorded the scope; no extra event needed. Proceed directly to step 4.
4. Otherwise, confirm with user: "This looks like a **[scope]** workflow. I'll run [stage count] stages. OK?" If `matches.length > 1` (multiple keywords matched), include the matched keywords in the prompt: "… (matched: [matches.join(', ')])" so the user can course-correct if the detection surprises them. Confirmation is mandatory for all freeform inputs — the user's text is ambiguous by definition, and a silent dispatch into the wrong scope burns artifacts and time.
5. If user confirms, proceed as with known scope above. Store the original freeform text as `Initial Intent` in aidlc-state.md so downstream stages do NOT re-ask "what do you want to build?"
6. If user overrides scope, use their chosen scope instead

### If no arguments:
1. If `aidlc-docs/aidlc-state.md` exists: resume workflow (read state, rebuild task sidebar, present current position, continue)
2. If no state: execute the Initialization phase (welcome is already displayed at session start via companyAnnouncements), then ask "What would you like to build?"

---

## TASK TRACKING (MANDATORY — do this before any stage work)

At the **start of each PHASE**, create one task per in-scope stage **for that phase only** using TaskCreate. Do this BEFORE executing the first stage of the phase. **DO NOT pre-create tasks for future phases** — this ensures the task sidebar displays stages in execution order.

```
TaskCreate({ subject: "[Phase] - [Stage Name]", description: "Brief stage objective", activeForm: "Running [Stage Name] [slug]" })
```

Examples:
- `TaskCreate({ subject: "Ideation - Intent Capture", description: "Capture business intent, problem statement, success metrics", activeForm: "Running Intent Capture [intent-capture]" })`
- `TaskCreate({ subject: "Inception - Requirements Analysis", description: "Analyse and document requirements", activeForm: "Running Requirements Analysis [requirements-analysis]" })`
- `TaskCreate({ subject: "Construction - Code Generation (Unit: Auth)", description: "Generate code for Auth unit", activeForm: "Running Code Generation [code-generation]" })`

**Before executing each stage** (including the very first), transition stage-level tasks:

```
TaskUpdate({ taskId: [previous stage task ID], status: "completed" })
TaskUpdate({ taskId: [current stage task ID], status: "in_progress", activeForm: "Running [Stage Name] [slug]" })
```

A task MUST be `in_progress` for the `activeForm` spinner to show — `pending` tasks display nothing.

**After compaction**, task IDs may be lost. Recover them: `TaskList` → match by subject string. Task naming conventions:
- Initialization: `"Initialization - [Stage Name]"` (e.g., `"Initialization - Workspace Scaffold"`)
- Ideation: `"Ideation - [Stage Name]"` (e.g., `"Ideation - Intent Capture"`)
- Inception: `"Inception - [Stage Name]"` (e.g., `"Inception - Reverse Engineering"`)
- Construction: `"Construction - [Stage Name] (Unit: [unit-name])"` (e.g., `"Construction - Code Generation (Unit: Auth)"`)
- Operation: `"Operation - [Stage Name]"` (e.g., `"Operation - Observability Setup"`)

---

## Scope-to-Stage Mapping

For a given scope, resolve stage-level routing by calling:

```bash
bun .claude/tools/aidlc-state.ts lookup stages-in-scope <scope>
```

Returns a JSON array of `{slug, phase, action}` where `action` is
`EXECUTE` or `SKIP`. Execute the `EXECUTE` stages in order; skip the
`SKIP` stages (no task, no approval gate). **If the array is empty,
the scope is unknown — emit an `Unknown scope "[value]". Valid scopes:
<list from validScopes()>.` error and STOP. Do NOT proceed with zero
stages.**

The JSON is a filter on the stage graph. The graph is structural
truth (32 stages + `requires_stage` edges, compiled from YAML); a
scope is a sub-DAG (the EXECUTE slice from `scope-mapping.json`,
plus whichever edges exist among those nodes); numeric order is a
valid topological sort of that sub-DAG, so the serial runtime
iterates the scope path in numeric order. Parallelism is an
instantiation property — `for_each: unit-of-work` stages fan out
per unit at runtime, captured structurally; concurrent scheduling
is deferred until the worktree driver ships.

Depth and test-strategy defaults:

```javascript
loadScopeMapping()[<scope>].depth          // "Minimal" | "Standard" | "Comprehensive"
loadScopeMapping()[<scope>].testStrategy   // optional — workshop only today
```

Source of truth: `.claude/tools/data/scope-mapping.json`. Adding a
scope is a JSON edit + `bun .claude/tools/aidlc-utility.ts scope-table`
to regenerate the summary table below + commit. No SKILL.md edit
required. CI runs `scope-table --check` to prevent drift.

<!-- BEGIN: compiled from scope-mapping.json via `bun aidlc-utility.ts scope-table` — do NOT hand-edit -->

| Scope          | Depth         | TestStrategy | EXECUTE / Total |
|----------------|---------------|--------------|-----------------|
| bugfix         | Minimal       | (default)    | 7 / 32          |
| enterprise     | Comprehensive | (default)    | 32 / 32         |
| feature        | Standard      | (default)    | 32 / 32         |
| infra          | Standard      | (default)    | 13 / 32         |
| mvp            | Standard      | (default)    | 22 / 32         |
| poc            | Minimal       | (default)    | 8 / 32          |
| refactor       | Minimal       | (default)    | 8 / 32          |
| security-patch | Minimal       | (default)    | 9 / 32          |
| workshop       | Standard      | Minimal      | 25 / 32         |

<!-- END: compiled from scope-mapping.json -->

---

## Stage Graph

| Slug | # | Stage | Phase | Execution | Lead Agent | Support Agents | Mode |
|------|---|-------|-------|-----------|------------|----------------|------|
| workspace-scaffold | 0.1 | Workspace Scaffold | Initialization | ALWAYS | (orchestrator) | — | inline |
| workspace-detection | 0.2 | Workspace Detection | Initialization | ALWAYS | (orchestrator) | — | inline |
| state-init | 0.3 | State Initialization | Initialization | ALWAYS | (orchestrator) | — | inline |
| intent-capture | 1.1 | Intent Capture & Framing | Ideation | ALWAYS | aidlc-product-agent | aidlc-architect-agent | inline |
| market-research | 1.2 | Market Research | Ideation | CONDITIONAL | aidlc-product-agent | — | inline |
| feasibility | 1.3 | Feasibility & Constraints | Ideation | CONDITIONAL | aidlc-architect-agent | aidlc-aws-platform-agent, aidlc-compliance-agent | inline |
| scope-definition | 1.4 | Scope Definition | Ideation | ALWAYS | aidlc-product-agent | aidlc-delivery-agent | inline |
| team-formation | 1.5 | Team Formation | Ideation | CONDITIONAL | aidlc-delivery-agent | — | inline |
| rough-mockups | 1.6 | Rough Mockups | Ideation | CONDITIONAL | aidlc-design-agent | aidlc-product-agent | inline |
| approval-handoff | 1.7 | Approval & Handoff | Ideation | ALWAYS | aidlc-delivery-agent | aidlc-product-agent | inline |
| reverse-engineering | 2.1 | Reverse Engineering | Inception | CONDITIONAL | aidlc-developer-agent | aidlc-architect-agent | subagent (aidlc-developer-agent → aidlc-architect-agent) |
| practices-discovery | 2.2 | Practices Discovery | Inception | CONDITIONAL | aidlc-pipeline-deploy-agent | aidlc-quality-agent, aidlc-developer-agent, aidlc-devsecops-agent | inline |
| requirements-analysis | 2.3 | Requirements Analysis | Inception | ALWAYS | aidlc-product-agent | — | inline |
| user-stories | 2.4 | User Stories | Inception | CONDITIONAL | aidlc-product-agent | aidlc-design-agent | inline |
| refined-mockups | 2.5 | Refined Mockups | Inception | CONDITIONAL | aidlc-design-agent | aidlc-product-agent | inline |
| application-design | 2.6 | Application Design | Inception | CONDITIONAL | aidlc-architect-agent | aidlc-aws-platform-agent, aidlc-design-agent | inline |
| units-generation | 2.7 | Units Generation | Inception | ALWAYS | aidlc-architect-agent | aidlc-delivery-agent | inline |
| delivery-planning | 2.8 | Delivery Planning | Inception | ALWAYS | aidlc-delivery-agent | aidlc-architect-agent | inline |
| functional-design | 3.1 | Functional Design | Construction | CONDITIONAL | aidlc-architect-agent | aidlc-developer-agent | inline |
| nfr-requirements | 3.2 | NFR Requirements | Construction | CONDITIONAL | aidlc-architect-agent | aidlc-devsecops-agent, aidlc-compliance-agent, aidlc-quality-agent | inline |
| nfr-design | 3.3 | NFR Design | Construction | CONDITIONAL | aidlc-architect-agent | aidlc-aws-platform-agent | inline |
| infrastructure-design | 3.4 | Infrastructure Design | Construction | CONDITIONAL | aidlc-aws-platform-agent | aidlc-devsecops-agent, aidlc-compliance-agent | inline |
| code-generation | 3.5 | Code Generation | Construction | ALWAYS | aidlc-developer-agent | — | subagent (aidlc-developer-agent) |
| build-and-test | 3.6 | Build and Test | Construction | ALWAYS | aidlc-quality-agent | aidlc-devsecops-agent | inline |
| ci-pipeline | 3.7 | CI Pipeline | Construction | CONDITIONAL | aidlc-pipeline-deploy-agent | — | inline |
| deployment-pipeline | 4.1 | Deployment Pipeline | Operation | CONDITIONAL | aidlc-pipeline-deploy-agent | — | inline |
| environment-provisioning | 4.2 | Environment Provisioning | Operation | CONDITIONAL | aidlc-aws-platform-agent | aidlc-devsecops-agent, aidlc-compliance-agent | inline |
| deployment-execution | 4.3 | Deployment Execution | Operation | CONDITIONAL | aidlc-pipeline-deploy-agent | aidlc-developer-agent | inline |
| observability-setup | 4.4 | Observability Setup | Operation | CONDITIONAL | aidlc-operations-agent | — | inline |
| incident-response | 4.5 | Incident Response | Operation | CONDITIONAL | aidlc-operations-agent | — | inline |
| performance-validation | 4.6 | Performance Validation | Operation | CONDITIONAL | aidlc-quality-agent | — | inline |
| feedback-optimization | 4.7 | Feedback & Optimization | Operation | CONDITIONAL | aidlc-operations-agent | aidlc-aws-platform-agent | inline |

---

## Routing

Read and execute each stage from `stages/initialization/`, `stages/ideation/`, `stages/inception/`, `stages/construction/`, or `stages/operation/`.
**Stage protocol loading — MANDATORY:**
- `stage-protocol.md`: load every stage (core gates, question format, state tracking, completion messages)
- `stage-protocol-recovery.md`: load on session resume or when a change event is detected mid-stage
- `stage-protocol-governance.md`: load at phase boundaries (approval-handoff→reverse-engineering, delivery-planning→functional-design, ci-pipeline→deployment-pipeline) to run phase-boundary traceability verification

Note: The Initialization→Ideation boundary has no governance check.

**MANDATORY: Task transitions.** Before executing ANY stage below:
1. Mark the previous stage task (if any) as `completed`: `TaskUpdate({ taskId: [previous stage task ID], status: "completed" })`
2. Activate the current stage task: `TaskUpdate({ taskId: [current stage task ID], status: "in_progress", activeForm: "Running [Stage Name] [slug]" })`
   The `[slug]` suffix is required — a PostToolUse hook parses it to automatically sync the state file.
This applies to every stage in all five phases. No exceptions. If task IDs are not in conversational context (e.g., after compaction), use `TaskList` and find the task by its subject (e.g., "Initialization - Workspace Scaffold", "Ideation - Intent Capture", "Inception - Requirements Analysis", "Construction - Code Generation (Unit: Auth)", "Operation - Observability Setup").

**MANDATORY: Per-stage memory.md.** Every stage keeps an observation diary at `aidlc-docs/<phase>/<stage>/memory.md`. At stage start (after `advance`/`approve` emits the `memory_path` key, or derive it as `aidlc-docs/<phase>/<stage>/memory.md` from the stage's phase + slug; for the INITIALIZATION stages derive `aidlc-docs/initialization/<slug>/memory.md`):
1. If `memory.md` does NOT exist at that path, copy `.claude/knowledge/aidlc-shared/memory-template.md` to it. Idempotent — never overwrite an existing file; re-entry or resume must keep accumulated entries.
2. During the stage, append timestamped bullets under the matching canonical heading as observations arise — Interpretation, Deviation, Tradeoff, or Open question. This is your diary-keeping (see `stage-protocol.md` §13); the four headings already exist in the template.
3. On approval, leave `memory.md` in place. It is the stage's permanent record — do NOT delete or move it. The §13 gate reads it; this block does not.

This applies to every stage in all five phases. No exceptions.

### INITIALIZATION Flow (stages 0.1–0.3)

The welcome message is displayed at session start via `companyAnnouncements` in `settings.json`. The three init stages (workspace-scaffold, workspace-detection, state-init) run as a single deterministic tool call — no per-stage subagent delegation, no per-stage `advance` calls.

**FIRST, create all 3 tasks and wire up dependencies** (sidebar observability — the tool itself runs in a fraction of a second):
- TaskCreate({ subject: "Initialization - Workspace Scaffold", description: "Bootstrap state/audit files and create aidlc-docs/ directory tree", activeForm: "Running Workspace Scaffold [workspace-scaffold]" }) → save taskId as scaffoldId
- TaskCreate({ subject: "Initialization - Workspace Detection", description: "Scan and classify workspace", activeForm: "Running Workspace Detection [workspace-detection]" }) → save taskId as detectionId
- TaskCreate({ subject: "Initialization - State Init", description: "Create full state file and determine routing", activeForm: "Running State Init [state-init]" }) → save taskId as stateInitId
- TaskUpdate({ taskId: detectionId, addBlockedBy: [scaffoldId] })
- TaskUpdate({ taskId: stateInitId, addBlockedBy: [detectionId] })

**Run init deterministically:**
Run `bun .claude/tools/aidlc-utility.ts init --scope <scope> --arguments "$ARGUMENTS"` via Bash (append `--depth <value>` if `--depth` was extracted; append `--test-strategy <value>` if `--test-strategy` was extracted; append `--test-run` if TEST_RUN_MODE is active) and print its stdout verbatim.

The tool writes WORKFLOW_STARTED, STAGE_STARTED/COMPLETED × 3, WORKSPACE_SCAFFOLDED, WORKSPACE_SCANNED, and WORKSPACE_INITIALISED to audit.md. SESSION_STARTED is hook-owned (SessionStart) and fires independently per Claude Code session. The tool also populates the full `aidlc-state.md` with the first post-init stage already marked in progress.

**After the tool returns**, mark all three tasks completed in order: scaffoldId → detectionId → stateInitId.

All 3 stages auto-proceed (no approval gates). The Initialization→Ideation transition has no governance boundary check.

### IDEATION Flow (stages 1.1–1.7)

**FIRST, before executing any stage**, create tasks for ALL IDEATION stages in scope (sidebar displays in creation order):
- TaskCreate({ subject: "Ideation - Intent Capture", description: "Capture business intent, problem statement, success metrics", activeForm: "Running Intent Capture [intent-capture]" })
- TaskCreate for each subsequent ideation stage in scope

1. **1.1 Intent Capture**: Execute `stages/ideation/intent-capture.md`
   - Inline with aidlc-product-agent persona framing
   - If freeform intent was provided in $ARGUMENTS, pass it as seed context — do NOT re-ask "what do you want to build?"
   - Approval gate required

2. **1.2 Market Research** (CONDITIONAL — per scope-mapping.json):
   - Execute `stages/ideation/market-research.md`
   - Inline with aidlc-product-agent persona
   - Approval gate required

3. **1.3 Feasibility & Constraints** (CONDITIONAL):
   - Execute `stages/ideation/feasibility.md`
   - Multi-agent: aidlc-architect-agent (lead) + aidlc-aws-platform-agent + aidlc-compliance-agent
   - Invoke lead first, then support agents with lead's output
   - Approval gate required

4. **1.4 Scope Definition**: Execute `stages/ideation/scope-definition.md`
   - Inline with aidlc-product-agent + aidlc-delivery-agent
   - Approval gate required

5. **1.5 Team Formation** (CONDITIONAL — per scope-mapping.json):
   - Execute `stages/ideation/team-formation.md`
   - Inline with aidlc-delivery-agent persona
   - Approval gate required

6. **1.6 Rough Mockups** (CONDITIONAL — skip if no UI):
   - Execute `stages/ideation/rough-mockups.md`
   - Inline with aidlc-design-agent persona
   - Approval gate required

7. **1.7 Approval & Handoff**: Execute `stages/ideation/approval-handoff.md`
   - Inline with aidlc-delivery-agent persona
   - Phase boundary verification: run traceability check per stage-protocol.md §13
   - Approval gate: go/no-go decision for Inception
   - On approval, transition to INCEPTION Flow

### INCEPTION Flow (stages 2.1–2.8)

**FIRST, before executing any stage**, create tasks for ALL INCEPTION stages in scope (sidebar displays in creation order):
- TaskCreate({ subject: "Inception - Reverse Engineering", description: "Scan and analyse existing codebase", activeForm: "Running Reverse Engineering [reverse-engineering]" })
- TaskCreate for each subsequent inception stage in scope

1. **2.1 Reverse Engineering** (CONDITIONAL — brownfield only, always rerun for freshness):
   - Execute `stages/inception/reverse-engineering.md`
   - Two-step delegation: developer subagent (code scan) → architect subagent (synthesis)
   > **Policy: always-rerun.** RE is always re-executed for brownfield projects even when prior artifacts exist.

2. **2.2 Practices Discovery** (CONDITIONAL — always rerun for freshness on EXECUTE scopes):
   - Execute `stages/inception/practices-discovery.md`
   - Inline; orchestrator dispatches four parallel Task calls (pipeline-deploy + quality + developer + devsecops) on brownfield, then runs interview gate, then affirmation gate
   - On affirmation, content is promoted to `.claude/rules/aidlc-team.md` and `.claude/rules/aidlc-project.md` (the cross-row promotion — only stage that writes both rows of the two-axis configuration model)
   - Approval gate required

3. **2.3 Requirements Analysis**: Execute `stages/inception/requirements-analysis.md`
   - Inline with aidlc-product-agent persona framing
   - Approval gate required

4. **2.4 User Stories** (CONDITIONAL):
   - Execute `stages/inception/user-stories.md`
   - IF user-facing features or complex business logic: Execute
   - Inline with aidlc-product-agent persona framing
   - Approval gate required

5. **2.5 Refined Mockups** (CONDITIONAL — skip if no UI or if rough mockups were skipped):
   - Execute `stages/inception/refined-mockups.md`
   - Inline with aidlc-design-agent persona
   - Approval gate required

6. **2.6 Application Design** (CONDITIONAL per scope/execution plan):
   - Execute `stages/inception/application-design.md`
   - Inline with aidlc-architect-agent persona framing
   - Approval gate required

7. **2.7 Units Generation**: Execute `stages/inception/units-generation.md`
   - Inline with aidlc-architect-agent persona framing
   - Produces the dependency DAG that 2.8 consumes for Bolt sequencing
   - Approval gate required

8. **2.8 Delivery Planning**: Execute `stages/inception/delivery-planning.md`
   - Inline with aidlc-delivery-agent + aidlc-architect-agent persona framing
   - Chooses the economic path through 2.7's DAG — Bolt sequence, per-Bolt DoD, risk rationale, external dependencies
   - Phase boundary verification: run traceability check per stage-protocol.md §13
   - Approval gate required (user can override stage inclusion/exclusion)

### CONSTRUCTION Flow (stages 3.1–3.7)

Construction runs **Bolt by Bolt**, driven by the Bolt sequence from 2.8's `bolt-plan.md` and the dependency DAG from 2.7's `unit-of-work-dependency.md`. A Bolt covers stages 3.1–3.5 for a Unit (or a small group of dependency-linked Units). Stages 3.6 (Build and Test) and 3.7 (CI Pipeline) run **once** at the end across all Bolts.

The first Bolt is the **walking skeleton** — always gated and interactive so the user can confirm the overall shape before the rest of Construction runs. Immediately after the walking-skeleton gate, the **ladder prompt** asks whether the remainder should run autonomously or stay gated per Bolt. The answer is recorded in `aidlc-state.md` (`Construction Autonomy Mode`) and governs every subsequent Bolt in this workflow (including resumed sessions).

Bolts whose dependencies are satisfied and that don't depend on each other run in a **parallel batch** — the orchestrator issues N `Task` calls in a single assistant message so the framework runs them concurrently.

_Read team practices once at Construction start:_ before any per-Bolt step, read two sections from team practices via `extractMarkdownSection` (`aidlc-lib.ts:1081`) per the `knowledge/aidlc-shared/rules-reading.md` fallback chain (`rules/aidlc-team.md → rules/aidlc-org.md → hardcoded scope defaults`): `## Walking Skeleton` (drives the dynamic skeleton stance — see Walking-skeleton block below) and `## Way of Working` (informational; the actual branch resolution happens at aidlc-pipeline-deploy-agent dispatch time per Bolt). When a section read returns empty after the full fallback chain (layer-3 hardcoded default fires), emit an advisory `PRACTICES_SECTION_EMPTY` audit row via `bun .claude/tools/aidlc-state.ts practices-event --type empty --field "Section: <heading>" --field "Fallback: <source>"` (advisory-only — does not block execution). This single read services the entire Construction phase; per-Bolt reads are not needed.

**FIRST, before executing any stage**, read `aidlc-docs/inception/delivery-planning/bolt-plan.md` to determine the Bolt sequence and identify the walking-skeleton Bolt. Create tasks for Construction (sidebar displays in creation order):

- For each Bolt in the plan (in sequence):
  - TaskCreate({ subject: "Construction — Bolt: [bolt-name]" + (walking-skeleton ? " (walking skeleton)" : ""), description: "Execute stages 3.1–3.5 for Bolt's Units" })
  - For each Unit in the Bolt:
    - TaskCreate({ subject: "Construction — Code Generation (Unit: [unit-name])", description: "Generate code for [unit-name]" })
- TaskCreate({ subject: "Construction — Build and Test", description: "Build, test, and validate all Bolts" })
- If CI Pipeline is in scope:
  - TaskCreate({ subject: "Construction — CI Pipeline", description: "Configure CI pipeline with quality gates" })

For stages marked SKIP in the execution plan, still create the task but immediately mark completed:
- TaskCreate + TaskUpdate({ taskId: [returned ID], status: "completed", description: "[original] — Skipped: [reason]" })

If `bolt-plan.md` is missing a walking-skeleton marker, warn the user and treat the first Bolt in the sequence as the walking skeleton.

**Per-Bolt execution (applies to every Bolt, walking skeleton or not)**

_Slug derivation:_ the per-Bolt slug is derived from the Bolt's name field in `bolt-plan.md` via lowercase + kebab-case (spaces → hyphens, non-alphanumerics stripped). Example: "Onboarding wizard" → slug `onboarding-wizard`. The `aidlc-worktree` tool prepends a `bolt-` prefix to the slug when constructing the worktree directory and branch (`.aidlc/worktrees/bolt-onboarding-wizard` on branch `bolt-onboarding-wizard`) — see `lib.ts:139` `worktreePath()`. The bare slug is what's passed to every per-Bolt tool call: `aidlc-worktree create/verify/merge/discard --slug <slug>`, `aidlc-bolt fail --slug <slug>`, and `aidlc-worktree info --slug <slug>` (halt-and-ask correlation). The Bolt's human-prose name is passed separately to `aidlc-bolt start/complete/fail --name`.

For the Bolt (or each Bolt in a parallel batch):

0. **Worktree create dispatch** — _Dispatch instrumentation:_ before the Task call, emit `MERGE_DISPATCH_INVOKED` via `bun .claude/tools/aidlc-bolt.ts dispatch-event --event MERGE_DISPATCH_INVOKED --slug <slug> --practices-excerpt "<first 200 chars of the ## Way of Working section read above>"`. Then dispatch `Task(subagent_type="aidlc-pipeline-deploy-agent", prompt="Create worktree for Bolt <slug>. Read .claude/rules/aidlc-team.md per knowledge/aidlc-shared/rules-reading.md; fall back to aidlc-org.md, then to hardcoded defaults. Pick aidlc-worktree create flags from knowledge/aidlc-pipeline-deploy-agent/branching-strategies.md. Invoke bun .claude/tools/aidlc-worktree.ts create --slug <slug> --base <resolved-base> from the main repo checkout. Return the JSON envelope per branching-strategies.md § Response contract.")`. After the Task returns: on a parsable JSON envelope with strategy/target/confidence/notes, emit `MERGE_DISPATCH_RETURNED` via `bun .claude/tools/aidlc-bolt.ts dispatch-event --event MERGE_DISPATCH_RETURNED --slug <slug> --strategy <s> --target <t> --confidence <c> --notes "<n>"`. On timeout / malformed YAML / confidence below 0.5, emit `MERGE_DISPATCH_FALLBACK` via `bun .claude/tools/aidlc-bolt.ts dispatch-event --event MERGE_DISPATCH_FALLBACK --slug <slug> --reason <timeout|malformed|low-confidence> --defaults "<defaults applied, e.g., squash + main>"` then proceed with the org-default flags. Audit-of-intent: an `MERGE_DISPATCH_INVOKED` row without a matching `_RETURNED` or `_FALLBACK` within ~60s is an orphan reconciled by `--doctor` via slug + timestamp window.
0.5. **Verify create** — run `bun .claude/tools/aidlc-worktree.ts verify --event WORKTREE_CREATED --slug <slug>`. Deterministic backstop confirming the agent's emit landed. On non-zero exit: halt-and-ask "agent reported worktree creation but audit log does not record it. Options: retry / abort."
1. **Emit `BOLT_STARTED` and fork state + audit + runtime-graph fragment into the worktree** via `bun .claude/tools/aidlc-bolt.ts start --name "<bolt-names>" --batch <n> --walking-skeleton <true|false> --worktree --slug <slug>`. The `--worktree` flag emits `BOLT_STARTED` then delegates to `aidlc-state.ts fork --slug <slug>` (emits `STATE_FORKED`, adds slug to main's `Bolt Refs`, byte-copies main state to `<worktreePath>/aidlc-docs/aidlc-state.md`), `aidlc-audit.ts audit-fork --slug <slug>` (emits `AUDIT_FORKED` audit-of-intent, byte-copies main audit), and `aidlc-runtime.ts fragment-fork --slug <slug>` (byte-copies main `runtime-graph.json` to `<worktreePath>/aidlc-docs/runtime-graph.json`; one-shot; no audit emit — the fragment lifecycle rides on `STATE_FORKED + AUDIT_FORKED`). Audit order on success: `BOLT_STARTED → STATE_FORKED → AUDIT_FORKED` (the runtime-graph fragment is materialised after AUDIT_FORKED with no additional audit row). On any sub-step failure, `aidlc-bolt` emits a `BOLT_FAILED` recovery row and prints a `{ok: false, slug, stage: "start-worktree", reason, detail}` envelope on stdout — route through halt-and-ask. Recovery: `bun .claude/tools/aidlc-worktree.ts discard --slug <slug>` (idempotent) cleans the partial fork (including any fragment file via `git worktree remove`); `--doctor` reconciles any orphan rows.
2. **Questions (3.1–3.4)** — within the Bolt, for each applicable stage (in stage order), for each Unit (in build order): execute the stage file in **QUESTION-ONLY mode**. Collect all questions across the Bolt's Units and stages; present a single approval gate for the Bolt's answers. Follow stage-protocol.md §3 question flow once per stage group within the Bolt.
3. **Design artifacts (3.1–3.4)** — within the Bolt, for each applicable stage, for each Unit: execute the stage file in **ARTIFACT-ONLY mode**. Generate artifacts from approved answers; no human interaction during generation.
4. **Code generation (3.5)** — for each Unit in the Bolt, execute `stages/construction/code-generation.md` via the Task tool with `subagent_type="aidlc-developer-agent"`. The per-Unit approval gate inside the stage file is **suppressed** by the orchestrator; the Bolt's single gate (next step) replaces it.
5. **Bolt gate** — present a single approval gate covering the Bolt (or, for a parallel batch, covering every Bolt in the batch). Walking skeleton: always gate. Subsequent Bolts: honour `Construction Autonomy Mode` — skip the gate if `autonomous`, present it if `gated`.
6. **Emit `BOLT_COMPLETED` and merge state + audit back to main** via `bun .claude/tools/aidlc-bolt.ts complete --name "<bolt-names>" --batch <n> --merge --slug <slug>` on success. The `--merge` flag emits `BOLT_COMPLETED` then delegates to `aidlc-state.ts merge --slug <slug>` (emits `STATE_MERGED`, removes slug from main's `Bolt Refs`, applies per-field merge rule from worktree state), `aidlc-audit.ts audit-merge --slug <slug>` (emits `AUDIT_MERGED`, appends post-fork delta from worktree audit to main), and `aidlc-runtime.ts fragment-merge --slug <slug>` (removes the worktree's runtime-graph.json fragment; idempotent; no audit emit). Audit order on success: `BOLT_COMPLETED → STATE_MERGED → AUDIT_MERGED` (after AUDIT_MERGED, the runtime-graph fragment is removed and the post-Bash hook recompiles main runtime-graph with `instances[]` for the merged slug). AIDLC metadata consolidates BEFORE Step 6.5's git-merge dispatch so the worktree's `aidlc-docs/` content is fully reconciled before aidlc-pipeline-deploy-agent moves application code. On failure, see envelope shape above; route through halt-and-ask. On code-generation failure (not gate-rejection), run `bun .claude/tools/aidlc-bolt.ts fail --name "<failed-bolt>" --slug "<failed-slug>" --error "<summary>" [--succeeded-siblings "<csv>"]` instead — `--slug` records the kebab-case Bolt slug in `BOLT_FAILED` for halt-and-ask correlation (see below); the worktree is preserved for inspection per US-1 AC. On user-driven abort (chosen via halt-and-ask), run `bun .claude/tools/aidlc-bolt.ts abort --name "<name>" --slug "<slug>" --reason "<text>" [--discard]` — `--discard` calls `aidlc-worktree discard` to tear the worktree down (which removes the runtime-graph fragment transitively); default preserves it.
6.5. **Worktree merge dispatch** (after `--merge` succeeded above — failure path skips merge): _Dispatch instrumentation:_ before the Task call, emit `MERGE_DISPATCH_INVOKED` via `bun .claude/tools/aidlc-bolt.ts dispatch-event --event MERGE_DISPATCH_INVOKED --slug <slug> --practices-excerpt "<first 200 chars of the ## Branching section>"`. Then dispatch `Task(subagent_type="aidlc-pipeline-deploy-agent", prompt="Merge worktree for Bolt <slug>. Read .claude/rules/aidlc-team.md per knowledge/aidlc-shared/rules-reading.md fallback chain. Pick aidlc-worktree merge flags from branching-strategies.md. Invoke bun .claude/tools/aidlc-worktree.ts merge --slug <slug> --target <resolved-target> --strategy <resolved-strategy> from the main repo checkout (after cd-ing to be on <target>). Return the JSON envelope per Response contract.")`. After the Task returns: on a parsable JSON envelope, emit `MERGE_DISPATCH_RETURNED` via `bun .claude/tools/aidlc-bolt.ts dispatch-event --event MERGE_DISPATCH_RETURNED --slug <slug> --strategy <s> --target <t> --confidence <c> --notes "<n>"`. On timeout / malformed YAML / confidence below 0.5, emit `MERGE_DISPATCH_FALLBACK` then proceed with org defaults.
6.75. **Verify merge** — run `bun .claude/tools/aidlc-worktree.ts verify --event WORKTREE_MERGED --slug <slug>`. On non-zero exit OR on a `{status: "conflict", ...}` envelope from Step 6.5: route through halt-and-ask (see below).

**Parallel batch dispatch**

When two or more Bolts share dependency-satisfaction and no mutual dependency, batch them. Parallelism is DAG-driven only — the orchestrator does not consult practices for parallelism preferences (the DAG is the permission). The phased contract:

1. **Group eligible Bolts** from `bolt-plan.md` + `unit-of-work-dependency.md` into the next batch (size N).
2. **Phase 0 — Worktree creation (one assistant message, N parallel)**: issue N `aidlc-bolt start --worktree --slug <slug>` calls in a single assistant message. Each subprocess holds its own audit lock via `withAuditLock`; mkdir-based locking serialises the audit-row writes deterministically across the N subprocesses (verified pre-impl: 4 parallel forks complete with no race, all slugs accumulate in `Bolt Refs` cleanly). Each call also emits its own MR-13 dispatch instrumentation around the worktree-create Task (Step 0).
3. **Phase 1 — Questions (per-Bolt sequential)**: within the batch, run Phase 1 of each Bolt one at a time. The user answers questions serially — there's no UX win in parallelising prompts.
4. **Phase 2 — Design artifacts (per-Bolt sequential)**: same pattern; cheap stages, serial generation.
5. **Phase 3 — Code generation (one assistant message, N parallel)**: issue N `Task(subagent_type="aidlc-developer-agent", ...)` invocations in a single assistant message. Pin each Task to its Bolt's worktree by naming the worktree path explicitly in the prompt body (`"Work inside .aidlc/worktrees/bolt-<slug>/. All file edits must stay within this directory tree…"`). Claude Code's Task tool has no `--project-dir` flag — the prompt-body path is the load-bearing pin. Collect all N results in the next turn.
6. **Phase 4 — Batch gate**: present **one batch-level approval gate** covering every Bolt in the batch (skip when `Construction Autonomy Mode: autonomous`).
7. **Phase 5 — Merge dispatch (one assistant message, N parallel)**: on approval, issue N `aidlc-bolt complete --merge --slug <slug>` calls in a single assistant message. Each emits its own MR-13 dispatch instrumentation around the worktree-merge Task (Step 6.5). Merges land on `main` in approximate batch order; cross-Bolt audit row order reflects merge-completion order.
8. **Audit**: one `BOLT_STARTED`/`BOLT_COMPLETED` pair per Bolt; the `Batch` field ties them together. Each Bolt also has its own `STATE_FORKED`/`STATE_MERGED`, `AUDIT_FORKED`/`AUDIT_MERGED`, `WORKTREE_CREATED`/`WORKTREE_MERGED`, and `MERGE_DISPATCH_INVOKED`/`MERGE_DISPATCH_RETURNED` (or `_FALLBACK`) rows.

**Walking skeleton + ladder prompt**

The skeleton stance is **dynamic** — read from team practices' `## Walking Skeleton` section (loaded once at Construction start, see preamble above). Resolution rules:

- If practices say "always" / "every greenfield feature" → skeleton-on for any greenfield-shaped scope.
- If practices say "never" / "we don't run a skeleton ceremony" → skeleton-off for every scope. Bolt 1 runs as a regular Bolt with the standard batch-gate path; no always-gate, no ladder prompt.
- If practices say "scope-dependent" / unspecified / `team.md` empty (layer-3 fallback fires `PRACTICES_SECTION_EMPTY` advisory) → fall back to scope-mapping defaults: skeleton-on for `enterprise`, `mvp`, `feature`, `poc`, `workshop`; skeleton-off for `bugfix`, `refactor`, `security-patch`. (`infra` scope has `code-generation: SKIP` so Construction itself doesn't run.)

If `bolt-plan.md` carries a walking-skeleton marker on a Bolt but practices says skeleton-off for the current scope, **practices wins** — emit a `PRACTICES_OVERRIDE` row with the discriminator field via `bun .claude/tools/aidlc-state.ts practices-event --type override --field "Reason: bolt-plan-marker-conflict" --field "Practices Stance: <stance>" --field "Bolt-Plan Marker: <marker>" --field "Bolt slug: <slug>"`. The marked Bolt then runs as a regular Bolt. Rationale: practices is the team's standing voice; bolt-plan is one workflow's interpretation.

When skeleton-on:

1. The walking-skeleton Bolt is always executed **solo** (never batched) and its gate is **always** presented, regardless of `Construction Autonomy Mode`. Under `--test-run`, the gate auto-approves.
2. Walking-skeleton worktree sequencing: the skeleton Bolt's worktree merges before any subsequent Bolt's Step 0 dispatch — the sequential ordering of solo-mode is the barrier. Subsequent Bolts read post-skeleton `main` (or the team's affirmed integration branch) in their Step 0 dispatch.
3. Immediately after the walking skeleton's gate approves AND its worktree has merged, fire the **ladder prompt** exactly once per workflow:
   - Question: "The walking skeleton shipped. How should the remaining Bolts run?"
   - Options: "Continue autonomously" / "Gate every Bolt"
   - Under `--test-run`: auto-select "Continue autonomously".
4. Record the choice via `bun .claude/tools/aidlc-bolt.ts set-autonomy --mode <autonomous|gated>` — emits `AUTONOMY_MODE_SET` and updates `Construction Autonomy Mode` in state atomically.
5. Resume safety: if a session resumes with `Construction Autonomy Mode: unset` after the walking-skeleton Bolt is already marked `[x]`, re-fire the ladder prompt before continuing.

When skeleton-off, no always-gate fires for Bolt 1 and no ladder prompt is presented. `Construction Autonomy Mode` defaults to the value already in state (typically `unset` until first set; treated as `gated` for the purposes of subsequent batches).

**Halt-and-ask failure handling**

When a Bolt's code-generation Task returns failure (missing expected artifacts in the return summary, or error text), the orchestrator gathers worktree state deterministically before presenting the AUQ:

1. Run `bun .claude/tools/aidlc-bolt.ts fail --name "<name>" --slug "<slug>" --error "<summary>" [--succeeded-siblings "<csv>"]`. This emits `BOLT_FAILED` with the slug for downstream correlation.
2. Run `bun .claude/tools/aidlc-worktree.ts info --slug "<slug>"`. Returns JSON `{slug, path, branch_name, audit_timestamp}` on hit (exit 0); non-zero with stderr message on miss or malformed-block. Schema pinned in `knowledge/aidlc-shared/worktree-info-schema.md`.
3. Compose the halt-and-ask `AskUserQuestion` per `stage-protocol.md §1` — the prompt body interpolates the `path` and `branch_name` returned by `info`. Skip and Abort option descriptions explicitly state the worktree is preserved.
4. Present the AUQ. The user picks retry / skip / abort.

Behaviour by failure shape:

- **Solo Bolt (m=1)**: halt immediately on Task failure; run steps 1–4 above for the single failed Bolt. Use the standard single-AUQ rendering — no multi-failure ceremony for one Bolt.
- **Parallel batch with m≥2 simultaneous failures**: wait for all parallel Tasks to return before deciding. Run steps 1–2 once per failed Bolt to gather correlation context. Then render the AUQs **sequentially** — N separate `AskUserQuestion` invocations, one per failed Bolt, in slug order, each tagged in the question body as `failure <k> of <m> (slug: <slug>)`. **HOLD-MERGE invariant:** before rendering any AUQ, the orchestrator runs `bun .claude/tools/aidlc-bolt.ts hold-merge --slug <slug>` for each successful Bolt — this sets `Merge-Held: true` in that Bolt's per-Bolt forked state. While the marker is set, `aidlc-bolt complete --merge --slug <slug>` refuses with `{ok: false, reason: "merge-held", ...}`; the orchestrator must NOT bypass this. Once every failed AUQ is resolved (every failed Bolt has been retried-and-succeeded, skipped, or aborted), the orchestrator runs `bun .claude/tools/aidlc-bolt.ts release-merge --slug <slug>` for each held Bolt and dispatches the surviving Bolts' merges in original batch order. The marker persists across session-kill / `--resume` (see _Resuming a batch in flight:_ below). Without this hold, a successful Bolt's merge could land on `main` mid-AUQ-sequence and invalidate a later failed Bolt's worktree assumptions.
- **Abort during the multi-failure sequence**: when the user picks Abort on AUQ k of m, halt Construction immediately — do NOT render AUQs k+1..m. The remaining unprocessed failed Bolts' worktrees stay preserved on disk; the user can run `/aidlc --resume` later, at which point the orchestrator re-renders the un-resolved AUQs from where it left off (k+1 of m).
- **Retry**: re-run the failed Bolt only (not the whole batch) inside the existing worktree. Same Bolt gate applies on success. `info` returns the same path on subsequent failures (no new `WORKTREE_CREATED` is emitted on retry). On retry success, the Bolt becomes a survivor and its `Merge-Held` marker stays set until all sibling AUQs resolve.
- **Skip**: mark the Bolt `[S]` in state with reason and proceed to the next AUQ in the sequence (or, if Skip is the last unresolved item, release the HOLD-MERGE markers). Worktree at `path` is preserved for inspection. Dependent Bolts may also fail — the user owns that risk.
- **Abort (single failed Bolt)**: stop Construction. Worktree at `path` is preserved for inspection. The user can resume later via `/aidlc --stage code-generation`.

_Audit-merge prefix-hash mismatch:_ `aidlc-audit.ts audit-merge` refuses with a `prefix-hash` error if main audit's prefix at byte `Fork Boundary` no longer matches the recorded `Source Audit Hash` (someone hand-edited main audit between fork and merge, or another tool truncated it). Quote the error message verbatim to the user; options: retry (after the user fixes main audit) / abort.

_Orphan-BOLT_STARTED recovery:_ if `BOLT_STARTED` emits but the subsequent `aidlc-state.ts fork` or `aidlc-audit.ts audit-fork` fails, `aidlc-bolt start --worktree` emits a `BOLT_FAILED` recovery row and prints the standard `{ok: false, ...}` envelope. The lone `BOLT_STARTED` plus the `BOLT_FAILED` is the recoverable shape — run `bun .claude/tools/aidlc-worktree.ts discard --slug <slug>` (idempotent) to clean any partial fork; `--doctor` reconciles any remaining drift via the slug correlation tag.

### Worktree-dispatch failure shapes — code-generation and merge-conflict (worktree visible)

- **Worktree merge conflict**: Step 6.5 returned `{status: "conflict", conflict_files, detail}`. Quote the `detail` field verbatim to the user, list `conflict_files`. Halt-and-ask presents the worktree path interpolated in the question body. Options: resolve conflicts in the worktree at `<worktree_path>` then re-run Step 6.5 / discard the worktree (`bun .claude/tools/aidlc-worktree.ts discard --slug <slug>`) and abort.

### Worktree-dispatch failure shapes — pre-creation and rejection (no worktree to show)

- **Verify-failed (audit-silent)**: agent reported success but `aidlc-worktree verify` exited non-zero (`absent` or `stale`). Treat as agent-misbehaviour. The worktree may not exist or have no audit trail — do NOT include a `Worktree:` line in the halt-and-ask prompt. Options: retry the dispatch / abort.
- **Dev-worktree rejection**: tool errored with "aidlc-worktree must run from the main repo checkout". The orchestrator is being driven from inside `.claude/worktrees/<dev-slug>/`. Tell the user to `cd` to the main checkout and resume; do not auto-recover. No worktree to show.

Regardless of `Construction Autonomy Mode`, a failure always halts and asks.

**Inspecting a paused Bolt:** when Skip or Abort is chosen, the Bolt's worktree at the path rendered in the halt-and-ask prompt is preserved on disk. Run `cd <path>` to inspect; run `bun .claude/tools/aidlc-worktree.ts discard --slug <slug>` to clean up. Symmetric for Skip and Abort.

_Resuming a batch in flight:_ if a session is killed mid-batch (after Phase 0 fork but before Phase 5 merge), `/aidlc --resume` recovers cleanly:
- Bolts in main state's `Bolt Refs` whose worktree dir exists with a matching `STATE_FORKED` audit row but no `STATE_MERGED`: re-enter Phase 3 (resume code-gen).
- Bolts in `Bolt Refs` whose `STATE_MERGED` row exists: skip — already merged.
- Successful Bolts whose per-Bolt forked state has `Merge-Held: true`: read this via `bun .claude/tools/aidlc-worktree.ts info --slug <slug>` (the JSON envelope's `merge_held` field). If any failed sibling AUQ remains unresolved, do NOT dispatch their merge — re-render the unresolved AUQs and let the user resolve them. Once cleared (`aidlc-bolt release-merge --slug <slug>`), dispatch held merges in original batch order. Even if the orchestrator forgets the marker, `aidlc-bolt complete --merge --slug <slug>` refuses while the hold is set — the tooling enforces the invariant.
- Batch-level gate: re-render with current Bolt status; the user can hold-then-merge any survivors that haven't yet been pushed.

_Workshop resume:_ when an engineer resumes Construction in a multi-engineer workshop (each engineer running their own session against a shared remote) and the skeleton is already merged, check `Construction Autonomy Mode` in `aidlc-state.md`. If set, skip the ladder prompt and inherit the mode. If unset (the first engineer completed the skeleton but disconnected before the ladder fired), present the ladder to the resuming engineer; subsequent resumed engineers inherit the resulting mode. State syncs via `git pull` — the engineer must pull the remote before resuming so their session reads the latest `Construction Autonomy Mode`. This is explicit, not magical: practices and autonomy mode are committed artifacts in the shared repo.

**After all Bolts complete**

1. **3.6 Build and Test** (ALWAYS):
   - Execute `stages/construction/build-and-test.md`
   - Inline with aidlc-quality-agent persona framing

2. **3.7 CI Pipeline** (CONDITIONAL):
   - Execute `stages/construction/ci-pipeline.md`
   - Inline with aidlc-pipeline-deploy-agent persona
   - Phase boundary verification: run traceability check per stage-protocol.md §13

### OPERATION Flow (stages 4.1–4.7)

**FIRST, before executing any stage**, create tasks for ALL OPERATION stages in scope (sidebar displays in creation order):
- TaskCreate for each operation stage in scope

1. **4.1 Deployment Pipeline** (CONDITIONAL):
   - Execute `stages/operation/deployment-pipeline.md`
   - Inline with aidlc-pipeline-deploy-agent persona
   - Approval gate required

2. **4.2 Environment Provisioning** (CONDITIONAL):
   - Execute `stages/operation/environment-provisioning.md`
   - Multi-agent: aidlc-aws-platform-agent (lead) + aidlc-devsecops-agent
   - Approval gate required

3. **4.3 Deployment Execution** (CONDITIONAL):
   - Execute `stages/operation/deployment-execution.md`
   - Inline with aidlc-pipeline-deploy-agent persona
   - Approval gate required

4. **4.4 Observability Setup** (CONDITIONAL):
   - Execute `stages/operation/observability-setup.md`
   - Inline with aidlc-operations-agent persona
   - Approval gate required

5. **4.5 Incident Response** (CONDITIONAL):
   - Execute `stages/operation/incident-response.md`
   - Inline with aidlc-operations-agent persona
   - Approval gate required

6. **4.6 Performance Validation** (CONDITIONAL):
   - Execute `stages/operation/performance-validation.md`
   - Inline with aidlc-quality-agent persona
   - Approval gate required

7. **4.7 Feedback & Optimization** (CONDITIONAL):
   - Execute `stages/operation/feedback-optimization.md`
   - Multi-agent: aidlc-operations-agent (lead) + aidlc-aws-platform-agent
   - Final stage — upon approval, the full AI-DLC workflow is complete
   - Approval gate: Approve (workflow complete) / Request Changes / Start New Ideation Cycle

---

## Agent Delegation Patterns

### Subagent stages (Task tool)
For stages using subagents:
1. Read the stage file to understand the task
2. Prepare context: prior artifacts, project description, workspace findings
3. Call Task tool with subagent_type matching the named agent (e.g., "aidlc-developer-agent", "aidlc-architect-agent") — the agent file is loaded automatically; do NOT manually inject the persona in the prompt
4. Pass context in the prompt (subagents cannot access conversation history)
5. Receive structured summary; use for completion message

### Inline stages (direct execution)
For stages running inline:
1. Read the stage file
2. Load the lead agent's flat file (e.g., `agents/aidlc-architect-agent.md`) for persona framing
3. Load knowledge per stage-protocol.md §5 knowledge loading order
4. Execute steps directly in conversation (user interaction available)
5. Follow stage-protocol.md for approval gates

### Multi-agent stages
For stages with support agents:
1. Execute the lead agent's work first (produce primary artifacts)
2. Invoke support agents (inline or via Task) with the lead's output as context
3. Synthesize all agent outputs into the final stage artifacts
4. Agents do NOT invoke each other — only the orchestrator delegates

---

## Stage Advancement

When a gated stage completes (the common path):
1. Run stage-completion verification (check artifacts exist, guardrails respected).
2. Run the §13 Learnings Ritual (unless `TEST_RUN_MODE`): `bun .claude/tools/aidlc-learnings.ts surface --slug <slug>`, render the AskUserQuestion + free-text channel, run the admission conflict-check against `aidlc-org.md`, then `bun .claude/tools/aidlc-learnings.ts persist --slug <slug> --selections-json <path>`. Advisory and additive — it never blocks the gate. See `stage-protocol.md` §13 for the full tool-as-actor protocol.
3. Call `aidlc-state.ts gate-start <slug>` before AskUserQuestion, then `aidlc-state.ts approve <slug>` after the user approves. `approve` marks the completed stage `[x]`, auto-advances to the next in-scope stage, emits `GATE_APPROVED` + `STAGE_COMPLETED` + `STAGE_STARTED` (+ `PHASE_*` events at phase boundaries), and on the final stage emits `WORKFLOW_COMPLETED` and sets Status=Completed. **Do not call `advance` separately after `approve` — approve owns the full transition.**
4. TaskUpdate: mark the completed stage task `completed`, set the next stage task to `in_progress` with `activeForm` spinner (include `[slug]` suffix).
5. Read and execute the next stage file.

When a non-gated stage completes (Initialization stages, construction bolts, etc.):
- Run `bun .claude/tools/aidlc-state.ts advance "<completed-slug>"` directly. The tool performs the same transition as approve's auto-advance (marks `[x]`, advances Current Stage, emits `STAGE_COMPLETED` + `STAGE_STARTED` + `PHASE_*` at boundaries).
- For the final non-gated stage, run `bun .claude/tools/aidlc-state.ts complete-workflow "<completed-slug>"` instead.

Notes:
- `[S]` (skipped via jump) stages are never modified by `advance`.
- Jump-target early-stops are handled inside `aidlc-jump.ts execute` under `--test-run`. The orchestrator does not need a manual stop check here — the jump tool emits `WORKFLOW_COMPLETED` with `Reason=test-run-stopped-at-<target>` and the state file reflects that.
- For approval gates, use `aidlc-state.ts gate-start <slug>` / `approve <slug>` / `reject <slug>`. Those tools emit `STAGE_AWAITING_APPROVAL` / `GATE_APPROVED` + `STAGE_COMPLETED` + `STAGE_STARTED` (via approve's auto-advance) / `GATE_REJECTED` + `STAGE_REVISING` internally — see `stage-protocol.md` §2.

---

## Deliberate Deviations from Reference

The following intentional differences from the upstream `aidlc-workflows/` reference and the v2 framework spec are documented here to prevent future "fix" attempts:

- **Initialization phase and slug-based IDs.** The reference does not define an Initialization phase or slug-based stage identifiers. This implementation adds a 3-stage Initialization phase (workspace-scaffold, workspace-detection, state-init) that runs before all other phases, plus a welcome banner rendered via `companyAnnouncements` in `settings.json` at session start. Stage IDs use slugs as canonical identifiers (e.g., `workspace-detection`) with numeric display order numbers (e.g., 0.2) as optional readability hints.
- **NFR artifact granularity expansion.** The reference defines 2 files for NFR Requirements and 2 files for NFR Design. This implementation expands to 5 files for NFR Requirements (performance-requirements, security-requirements, scalability-requirements, reliability-requirements, tech-stack-decisions) and 4 files for NFR Design (performance-design, security-design, scalability-design, reliability-design). The finer granularity improves traceability and allows per-concern review without overloading a single document.
- **Plan/question file co-location.** Plans and question files are co-located with stage artifacts (e.g., `aidlc-docs/inception/user-stories/user-stories-questions.md`) instead of the v2 spec's flat `stage-X.X-questions.md` pattern. Improves discoverability — all inputs, questions, and outputs for a stage are found in the same directory.
- **Infrastructure Design expanded to 5 artifacts.** Reference has 2-3 files; implementation adds monitoring-design.md and cicd-pipeline.md as dedicated artifacts for operational visibility.
- **Inline questions for simple decisions.** Reference requires all questions in files. Implementation allows AskUserQuestion for 1-3 simple options. Claude Code's structured UI makes inline questions equivalent to file-based for simple cases.
- **Architecture Decision Records (decisions.md).** Application Design produces an additional decisions.md artifact documenting ADRs with Context, Decision, Consequences, and Alternatives. Not present in the reference.
- **Welcome via companyAnnouncements.** The welcome message is delivered as a `companyAnnouncements` entry in `settings.json`, rendered at session start by Claude Code itself. Shorter and ASCII-safe vs the reference's longer Unicode-based welcome stage.
- **RE always-rerun policy.** Always re-executes Reverse Engineering for brownfield projects even when prior artifacts exist. Documented in Routing section above; listed here for completeness.
- **Session resume uses AskUserQuestion.** The reference uses file-based [Answer]: tag format for resume prompt. This implementation uses AskUserQuestion for the resume choice (Resume / Review / Start fresh), which is more natural in Claude Code's interactive environment.
- **Clarification questions handled inline.** The reference creates separate clarification files. This implementation handles clarification questions inline via AskUserQuestion, since follow-up questions are typically 1-2 targeted queries that don't warrant a separate file.
- **Specialized audit log formats added (not in reference).** Three specialized formats (Error, Recovery, Change Request) for structured post-hoc analysis.
- **Tri-mode question flow (Guide me / I'll edit the file / Chat).** The reference supports only file-based question answering. This implementation adds interactive "Guide me" and freeform "Chat" modes as alternatives, with all modes converging on the file as source of truth.
- **Delivery Planning work breakdown focus.** The reference treats Workflow Planning purely as a stage selector. This implementation (now renamed to Delivery Planning) adds work breakdown analysis that identifies work streams, sequences implementation, and maps review expertise.
- **State file naming.** Kept as `aidlc-state.md` (framework spec uses `state.md`) because hooks hardcode the path `aidlc-docs/aidlc-state.md`.
- **Minimal rules.** Flat `.claude/rules/` directory with scope-layer files (org/team/project) plus phase-scoped files. Files that the v2 spec places in rules (adaptive-patterns, verification, brownfield, audit-format) are instead placed in `knowledge/aidlc-shared/` or embedded in SKILL.md/stage-protocol.md to avoid context bloat in non-AIDLC conversations.
- **Scope-to-stage mapping compiled into SKILL.md.** The v2 spec places this in `adaptive-patterns.md` under rules. This implementation keeps the authoritative mapping in `.claude/tools/data/scope-mapping.json` and compiles a human-readable summary into SKILL.md's Scope-to-Stage Mapping section via `bun .claude/tools/aidlc-utility.ts scope-table`. CI runs `scope-table --check` to prevent drift. Keyword→scope inference (for freeform user input) also reads from `scope-mapping.json` via the `keywords[]` field per scope.
- **Generic agent tool access.** The v2 spec defines scoped tool restrictions per agent (e.g., `Bash(python *)` for aidlc-architect-agent, `Bash(aws *, cdk *)` for aidlc-aws-platform-agent). Claude Code does not support scoped tool restrictions, so every agent inherits the full session toolset, restricted only by `disallowedTools: Task`. (Tool-access details live in `docs/reference/05-agent-system.md`.)
- **No nested agent delegation.** The v2 spec allows agents to delegate to other agents via Task(). This implementation disallows Task on all agents (disallowedTools: Task) — only SKILL.md orchestrates agent invocations. Prevents cascading subagent chains and simplifies the execution model.
- **Flat agent file location.** Agent files at `.claude/agents/*.md` (flat) instead of the spec's `.claude/agents/aidlc/*.md` (namespaced). Matches Claude Code's standard agent discovery path and reduces directory nesting.
- **Agent memory: project omitted.** The v2 spec defines `memory: project` for all agents. This is not a supported Claude Code agent frontmatter field. Cross-session state is managed via `aidlc-docs/aidlc-state.md` instead.
- **Design-agent support additions.** Design-agent added as support to user-stories and application-design stages for UX-informed development. The spec only lists aidlc-design-agent in rough-mockups and refined-mockups.
- **Inline stages use persona framing, not infrastructure enforcement.** For subagent stages, `subagent_type` is set to the named agent (e.g., "aidlc-developer-agent") which enforces `disallowedTools` and `modelOverride` from the agent's frontmatter. For inline stages, there is no Task boundary, so tool restrictions cannot be enforced at the infrastructure level — inline stages rely on persona framing via loading the agent's `.md` file. This is intentional: inline stages benefit from user interaction (AskUserQuestion), which requires orchestrator-level execution, not a subagent boundary.
- **Workspace Detection (0.2, inline).** Moved from Inception to Initialization phase. Runs deterministically inside `aidlc-utility init` (not a subagent) for fast workspace scanning.
- **Subagent stages.** Two stages use subagents: reverse-engineering (2.1, two-step aidlc-developer-agent → aidlc-architect-agent) and code-generation (3.5, aidlc-developer-agent). All other stages run inline — workspace-detection (0.2) in particular runs deterministically inside `aidlc-utility init`, not as a subagent.
- **CLI tools for state management.** Deterministic state operations (checkbox updates, field writes, audit appends, jump orchestration) are implemented as TypeScript CLI tools in `.claude/tools/` (run via `bun`). The LLM calls these as single Bash commands instead of assembling sed/cat patterns. This eliminates flaky state updates and frees LLM turns for actual stage work. Stage graph and scope mapping data are extracted into JSON files (`data/stage-graph.json`, `data/scope-mapping.json`) as single sources of truth.

---

## Key Principles

- **Adaptive scope**: Scope determines which stages execute and at what depth — from 7-stage bugfix to 32-stage enterprise
- **User control**: User can override any stage decision at any approval gate
- **11 domain experts**: Each stage leverages appropriate agent personas (product, design, delivery, architect, aws-platform, compliance, devsecops, developer, quality, pipeline-deploy, operations)
- **Approval gates**: Every stage (except the 3 Initialization stages) requires user approval via AskUserQuestion
- **Questions in markdown files**: All questions go in markdown files using [Answer]: tags with A-E + X (Other) options — the file is always the source of truth
- **Tri-mode interaction**: User chooses guided (interactive walkthrough), self-guided (edit file directly), or chat (freeform conversation) mode for answering questions
- **Audit trail**: All user inputs and AI responses logged automatically via hooks + manual logging of conversation events
- **Progress tracking**: Stage-level tasks via TaskCreate/TaskUpdate; task IDs resolved via TaskList by subject — not stored in state file
- **Self-learning guardrails**: Human corrections can become persistent behavioral rules in `.claude/rules/`
- **Phase boundary verification**: Traceability checks run automatically at phase transitions
- **No nested delegation**: SKILL.md orchestrates all agent invocations. Agents do NOT invoke each other or spawn subagents.
