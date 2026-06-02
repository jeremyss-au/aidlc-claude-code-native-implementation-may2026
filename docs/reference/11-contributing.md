# Contributing

## Overview

Contributions to AI-DLC are welcome. This guide covers prerequisites, development workflow, testing, and how to submit changes.

## Prerequisites

- **Claude Code** -- native install (recommended, auto-updates): macOS/Linux/WSL `curl -fsSL https://claude.ai/install.sh | bash`; Windows PowerShell `irm https://claude.ai/install.ps1 | iex`. Or `brew install --cask claude-code`. (see [Claude Code docs](https://code.claude.com/docs/en/quickstart))
- **bun** -- Required for all CLI tools and all 9 hooks. Install via `curl -fsSL https://bun.sh/install | bash`. On Windows: `npm install -g bun` or `powershell -c "irm bun.sh/install.ps1 | iex"`. Must be on PATH for non-interactive shells (`~/.zshenv` for zsh, `~/.bashrc` for bash / Git Bash on Windows).
- **timeout** (GNU coreutils) -- Required by the test suite for LLM test timeouts (L2/L3). Pre-installed on Linux. macOS: `brew install coreutils` then add gnubin to PATH: `export PATH="/opt/homebrew/opt/coreutils/libexec/gnubin:$PATH"` (in `~/.zshenv` or `~/.zshrc`).
- **Bash** -- Only needed to run the test suite on Windows (`tests/run-tests.sh` is bash). Use Git Bash (included with Git for Windows) -- WSL is NOT required. At runtime, none of the distributable hooks require Bash.
- **Bedrock access** -- Required for running integration, stage, and workflow tests (L2/L3). Not needed for L1 protocol tests.

## Repository Structure

```
aidlc-claude-code/   # Distributable implementation (copy .claude/ into your project)
tests/               # TAP-based test suite
docs/                # Documentation
  guide/             # User guide (how to use AI-DLC)
  harness/           # Harness engineer guide (configure AI-DLC without code)
  reference/         # Developer reference (how it works internally)
```

For the full architecture, see [reference/01-architecture.md](01-architecture.md).

## Development Workflow

1. **Fork and branch** from `main`
2. **Read the architecture** -- [reference/01-architecture.md](01-architecture.md) explains the execution model, agent delegation, and hook system
3. **Understand the entry point** -- The orchestrator lives at `aidlc-claude-code/.claude/skills/aidlc/SKILL.md`
4. **Make changes** -- The implementation is in `aidlc-claude-code/.claude/` (skills, agents, hooks, rules, knowledge)
5. **Test** -- Run `bash tests/run-tests.sh` before submitting
6. **Submit** -- Open a PR against `main`

## Testing

The project uses a three-layer test pyramid. L1 runs locally with no dependencies; L2 and L3 require the `claude` CLI tool.

**Quick reference:**

```bash
# L1 Protocol -- runs in seconds, no dependencies
bash tests/run-tests.sh

# L2 Stage -- CI pipeline (requires claude CLI tool)
bash tests/run-tests.sh --ci

# L3 Acceptance -- release gate (requires claude CLI tool)
bash tests/run-tests.sh --release

# Individual tiers
bash tests/run-tests.sh --smoke        # File structure validation
bash tests/run-tests.sh --unit         # Hook behavior, stage content
bash tests/run-tests.sh --feature      # Scope mapping, I/O contracts
bash tests/run-tests.sh --integration  # End-to-end CLI tool tests
bash tests/run-tests.sh --stage        # Individual stage tests
bash tests/run-tests.sh --workflow     # Multi-stage workflow tests
bash tests/run-tests.sh --worktree     # Worktree primitive helpers (no LLM)
```

For the full test strategy, stubs, and how to add new tests, see [reference/09-testing.md](09-testing.md).

## Adding a Utility Handler

> **Before adding an audit event**, read [State Machine](12-state-machine.md). The chapter lists every event in the taxonomy, its emitter, and the "same-commit rule" — update the code AND the chapter's tables in the same MR, or the drift test will fail.

Utility handlers fall into two categories:

### Deterministic handlers (preferred)
For handlers that require no LLM reasoning (print text, read/format files, check prerequisites, create directories):
1. Add a subcommand to `aidlc-claude-code/.claude/tools/aidlc-utility.ts`
2. Dispatch from SKILL.md with a single Bash call: `bun .claude/tools/aidlc-utility.ts <subcommand>`
3. No task tracking needed -- the script runs in under a second
4. Handle audit logging inside the script via `appendAuditEntry` from `aidlc-audit.ts` (never hand-write `**Event**:` markdown blocks)

The `--help`, `--version`, `--status`, and `--doctor` handlers are reference implementations.

### LLM-driven handlers
For handlers that benefit from agent reasoning (filesystem scanning, decision-making):
1. **Task tracking** -- Create tasks via `TaskCreate` for each logical step, transition them with `TaskUpdate` (`in_progress` -> `completed`) as work progresses. This drives the task sidebar in Claude Code.
2. **Statusline update** -- If `aidlc-docs/aidlc-state.md` exists, temporarily set `Current Stage` to describe the running utility (e.g., `running health check`), then restore the original value when done. The `aidlc-statusline.ts` hook reads this field for the terminal status bar.
3. **Audit logging** -- Invoke the appropriate tool subcommand (e.g., `bun .claude/tools/aidlc-utility.ts <handler>` that calls `appendAuditEntry` internally). Never hand-write `**Event**:` markdown blocks from LLM prose — see [State Machine: Forbidden patterns](12-state-machine.md).

The `--init` handler is fully deterministic: all three init stages (workspace-scaffold, workspace-detection, state-init) run inside a single `aidlc-utility init` call. The welcome message is rendered at session start via `companyAnnouncements` in `settings.json` and is not a stage.

## Adding a Scope

Scopes are defined in `aidlc-claude-code/.claude/tools/data/scope-mapping.json`. Validation logic across `init`, `scope-change`, `resolve-env-scope`, `doctor`, and state tooling derives the list of valid scopes from this file at runtime via `validScopes()` in `aidlc-claude-code/.claude/tools/aidlc-lib.ts`. Adding a scope requires no TypeScript edits.

### Steps

1. **Edit `scope-mapping.json`** — add a new top-level key with:
   - `depth` (required): `"Minimal"` | `"Standard"` | `"Comprehensive"`
   - `stages` (required): object mapping every stage slug from `stage-graph.json` to `"EXECUTE"` or `"SKIP"`. All 32 stage slugs must appear; missing slugs are treated as absent and the stage will not appear in the plan.
   - `keywords` (optional): array of NL triggers for `/aidlc <freeform text>` auto-detection (MR 10+). Word-boundary matched, alphabetical-scope tie-break. Empty array opts out of inference.
   - `description` (optional): one-line summary rendered in `/aidlc --help` and in SKILL.md's compiled scope-table (MR 10+).
   - `testStrategy` (optional): override test strategy independent of depth (e.g. `"Minimal"` for workshop). Defaults to matching depth.

   `loadScopeMapping()` in `lib.ts` only JSON-parses the file — schema validation for `scope-mapping.json` is not yet wired up. Run `/aidlc --doctor` after editing to catch structural issues.

   ```json
   "hotfix": {
     "depth": "Minimal",
     "keywords": ["hotfix", "urgent"],
     "description": "Urgent production fix",
     "stages": {
       "workspace-scaffold": "EXECUTE",
       "workspace-detection": "EXECUTE",
       "state-init": "EXECUTE",
       "intent-capture": "EXECUTE",
       "feasibility": "SKIP",
       ...
     }
   }
   ```

2. **Regenerate SKILL.md's compiled scope-table** — `bun .claude/tools/aidlc-utility.ts scope-table` prints the canonical Markdown table. Paste the output between the `<!-- BEGIN: compiled ... -->` / `<!-- END: compiled ... -->` markers in `aidlc-claude-code/.claude/skills/aidlc/SKILL.md`. Run `bun .claude/tools/aidlc-utility.ts scope-table --check` to confirm exit 0.

3. **Verify the scope resolves** — `bun aidlc-claude-code/.claude/tools/aidlc-utility.ts init --scope hotfix --project-dir /tmp/scope-smoke` should succeed and produce a state file with `Scope: hotfix`.

4. **Verify `doctor` accepts it as an env default** — `AWS_AIDLC_DEFAULT_SCOPE=hotfix bun aidlc-utility.ts doctor` should report the env var as valid.

5. **Verify keyword inference** (if `keywords` populated) — `bun aidlc-utility.ts detect-scope --from-text --input "urgent customer issue" --project-dir /tmp/scope-smoke` should return `{"scope":"hotfix","source":"keyword","matches":["urgent"]}`.

6. **Update scope-aware documentation** — `docs/guide/04-scopes-and-depth.md` (full scope reference), `docs/guide/12-customization.md` (valid values list and scope table), and `docs/reference/03-orchestrator.md` (scope-to-stage mapping) all enumerate scopes explicitly. Per the documentation policy at the end of this chapter, update them in the same MR.

7. **Add a scope-routing workflow test** — if the scope has behavior that differs from existing scopes (new phase skipping pattern, new depth combination), add a `tests/workflow/tNN-workflow-<scope>-scope.sh` modeled after `t50-workflow-bugfix-scope.sh` or `t51-workflow-poc-scope.sh`.

### What validates automatically

- `validScopes().has("hotfix")` returns `true` the moment the JSON edit lands — every validation site uses this helper.
- Error messages list the new scope in alphabetical order without any code changes.
- `/aidlc --doctor` treats `AWS_AIDLC_DEFAULT_SCOPE=hotfix` as valid.
- `aidlc-utility scope-change --scope hotfix` on an in-flight workflow accepts the new scope.
- SKILL.md's scope routing is data-driven as of MR 10 of v0.3.0 Foundation. The scope-to-stage summary in SKILL.md is compiled from `.claude/tools/data/scope-mapping.json` via `bun .claude/tools/aidlc-utility.ts scope-table`, with a `--check` drift guard run by the t67 test. Adding a scope means a JSON edit + table regeneration + commit — no SKILL.md prose edit required.
- Keyword detection for freeform `/aidlc <text>` invocations reads from each scope's `keywords[]` field in `scope-mapping.json`. Custom scopes with their own NL triggers auto-detect as soon as the `keywords` array is populated (no SKILL.md change needed). Users can still pass `--scope hotfix` explicitly to bypass inference.

### What does NOT validate automatically

- Stage skipping semantics (`PHASE_SKIPPED` events). `tests/feature/t39-per-scope-phase-sequence.sh:69` hardcodes the 9 known scope names in a `for scope in ...` loop — a new scope is not exercised until that list is extended. Add your new scope to that loop as part of the same MR.

## Adding an Agent

Agent metadata (display name, example knowledge files) is read from each agent's `.md` frontmatter under `aidlc-claude-code/.claude/agents/`. The `loadAgents()` helper in `aidlc-claude-code/.claude/tools/aidlc-lib.ts` discovers every `.md` file in that directory and derives the metadata map consumed by `--init` (to scaffold `aidlc-docs/knowledge/<agent>/README.md`) and by the statusline hook (to render the display name). Adding an agent requires no TypeScript edits.

### Steps

1. **Create the agent file** — drop a new `aidlc-claude-code/.claude/agents/<slug>-agent.md` with the required frontmatter:

   ```yaml
   ---
   name: <slug>-agent
   display_name: <Human-Readable Name>
   examples:
     - example-knowledge-file-one.md
     - example-knowledge-file-two.md
   description: >
     One-paragraph description of the agent's responsibilities and which stages it leads or supports.
   disallowedTools: Task
   modelOverride: opus
   ---
   ```

   The `name` field must match the filename stem exactly. `display_name` is the human-facing label used by `--init` and the statusline. `examples` lists filenames that appear as bullets in the scaffolded knowledge README — they're suggestions for the user, not loaded at runtime.

2. **Verify the agent is discovered** — `bun -e "import { loadAgents } from 'aidlc-claude-code/.claude/tools/aidlc-lib.ts'; console.log(loadAgents().find(a => a.slug === '<slug>-agent'));"` should print the new agent's metadata.

3. **Verify `--init` scaffolds the knowledge README** — `bun aidlc-claude-code/.claude/tools/aidlc-utility.ts init --scope poc --project-dir /tmp/agent-smoke` should create `aidlc-docs/knowledge/<slug>-agent/README.md` with the display name as H1 and the examples as bullets.

4. **Verify the statusline renders** — seed a state file with `Active Agent: <slug>-agent` and invoke the statusline hook; the output should include the display name after the `--` separator.

5. **Wire the agent into stages** — a new agent that should lead or support stages must be added to `aidlc-claude-code/.claude/tools/data/stage-graph.json` under the relevant entries' `lead_agent` / `support_agents` fields. This is separate from discovery — `loadAgents()` makes the agent visible; `stage-graph.json` makes it active.

### What validates automatically

- `loadAgents()` discovers any new `.md` file in `.claude/agents/` on next invocation — no code edit.
- The parser throws if `name` or `display_name` is missing, naming the file and the missing field.
- Agents are returned alphabetically sorted by slug, so `readdirSync` order on any platform produces the same output.
- `/aidlc --init` scaffolds per-agent knowledge directories using derived metadata.
- Statusline rendering derives display name from the same source — no risk of drift with `--init` output.
- `tests/unit/t61-agent-metadata-derived.sh` asserts all five properties end-to-end against a fixture agent.

### What does NOT validate automatically

- **Stage-graph participation**. `stage-graph.json` references agents by slug in `lead_agent` / `support_agents` fields. Adding a new agent without updating stage-graph means the agent exists but never runs. Stage-graph schema validation (`aidlc-claude-code/.claude/tools/aidlc-stage-schema.ts`) is wired in: `aidlc-graph.ts compile` validates every stage's frontmatter (and `compile --check` is the CI drift guard), and `/aidlc --doctor` re-runs the same `validateStageFrontmatter` plus a "Graph references" check that every `lead_agent` / `support_agents` slug resolves.
- **Knowledge file existence**. `examples` is a list of filenames surfaced as suggestions in the scaffolded README — they're not created or validated. Users place the actual content in `aidlc-docs/knowledge/<agent>/`.
- **Doc tables listing agents**. The Phase Participation matrix at `docs/reference/05-agent-system.md:119-131` and the agent→examples table at `aidlc-claude-code/.claude/knowledge/aidlc-shared/knowledge-readme-template.md:16-29` are maintained by hand. Update them in the same MR that adds the agent (see Documentation Policy below).
- **`.claude/agents/<new-agent>.md` body content**. Only the frontmatter is parsed. The body prose (Core Responsibilities, Knowledge Loading sequence, etc.) is read by the agent itself when activated — write it to match the other 11 agent files' structure.

## CI/CD Pipeline

The repository runs scheduled and API-triggered pipelines:

- **AIDA dispatch/resolve** -- The automated issue agent. Its pipeline jobs live in `.gitlab-ci.yml` and the dispatch/resolve scripts under `.gitlab/scripts/`.

**Testing CI changes:** Push to a branch and trigger a manual pipeline run to validate `.gitlab-ci.yml` or script changes before merging.

## Documentation Policy

When adding, removing, or renaming files, directories, commands, or flags:

1. Grep `docs/` and `README.md` for stale references
2. Update all references in the same commit

## Submitting Changes

1. Open a PR against `main` with a clear description of what changed and why
2. Ensure L1 tests pass: `bash tests/run-tests.sh`
3. For hook changes: run `bash tests/run-tests.sh --unit`
4. For integration tests: run `bash tests/run-tests.sh --integration` (requires `claude` CLI tool)
5. Update documentation if your changes affect files, commands, or flags (see Documentation Policy above)
