# AI-DLC — Claude Code Native Implementation

This repo contains the Claude Code native implementation of the AI-DLC
(AI-Driven Development Life Cycle) methodology.

## Project Structure

- `aidlc-claude-code/` — The distributable implementation. Users copy `aidlc-claude-code/.claude/` into their project's `.claude/`.
- `tests/` — TAP-based test suite. Run `bash tests/run-tests.sh --help` for tiers and profiles.
- `docs/guide/` — User Guide: getting started, workflows, scopes, agents, customization, troubleshooting
- `docs/harness/` — Harness Engineer Guide: reshaping AIDLC through configuration (stages, agents, scopes, rules, sensors, knowledge) without code
- `docs/reference/` — Developer Reference: architecture, orchestrator, stage protocol, hooks, testing, contributing

## How It Works

The implementation lives in `aidlc-claude-code/.claude/` and uses Claude Code's native features:

- **Skills** (`skills/aidlc/`) — Orchestrator (`SKILL.md`), stage protocol, and 32 stage files across 5 phases (initialization, ideation, inception, construction, operation)
- **Agents** (`agents/`) — 11 domain-expert personas as `aidlc-<role>-agent.md` files: product, design, delivery, architect, aws-platform, compliance, devsecops, developer, quality, pipeline-deploy, operations
- **Rules** (`rules/`) — Flat layered config: `aidlc-org.md` (framework defaults), `aidlc-team.md` (affirmed practices), `aidlc-project.md` (project overrides), and `aidlc-phase-<phase>.md` for ideation/inception/construction/operation
- **Sensors** (`sensors/`) — Deterministic verification manifests (advisory): `aidlc-required-sections.md`, `aidlc-upstream-coverage.md`, `aidlc-linter.md`, `aidlc-type-check.md`
- **Knowledge** (`knowledge/`) — Methodology reference. Per-agent under `aidlc-<agent>-agent/`; cross-agent material in `aidlc-shared/`
- **Tools** (`tools/`) — TypeScript CLI tools, all prefixed `aidlc-*.ts` and run via bun
- **Hooks** (`hooks/`) — 9 framework hooks, all prefixed `aidlc-*.ts`, covering audit emission, sensor dispatch, runtime-graph compile, session lifecycle, state validation, subagent tracking, and statusline rendering

## Working on This Project

- The orchestrator `SKILL.md` is the main file to understand and modify
- `aidlc-claude-code/.claude/CLAUDE.md` is the user-facing CLAUDE.md that ships with the framework — it is NOT this file. Edit it when changing user-facing behavior (commands, prerequisites, conventions).
- See `docs/guide/` (User Guide), `docs/harness/` (Harness Engineer Guide), and `docs/reference/` (Developer Reference) for full documentation

## Test Suite

Run `bash tests/run-tests.sh --help` for tiers and flags. See `docs/reference/09-testing.md` for full strategy.

## Utility Handler Checklist

See `docs/reference/11-contributing.md` § "Adding a Utility Handler" before implementing a new `/aidlc --*` command.

## Documentation Policy

IMPORTANT: When adding, removing, or renaming files, directories, commands, or flags — grep `docs/` and `README.md` for stale references and update them in the same commit.

## Changelog Policy

IMPORTANT: Every user-visible MR bumps `aidlc-claude-code/.claude/tools/aidlc-version.ts` and adds a matching `## [X.Y.Z] - YYYY-MM-DD` heading + bullet(s) to `CHANGELOG.md` in the same commit. Patch tags (`v0.3.1`, `v0.3.2`, ...) accumulate through a release-prep cycle; the eventual minor cut (e.g. `v0.4.0`) consolidates them. Pure doc sweeps, internal refactors, and test-only changes do NOT bump — those live in commit messages and the design notes under `docs/`. The pin in `tests/unit/t68-version-changelog-sync.sh` enforces that `aidlc-version.ts` and the latest `CHANGELOG.md` heading agree.

Each entry follows the v0.1.0 / v0.2.0 / v0.3.0 shape: `## [N.N.N] - YYYY-MM-DD` heading, one-paragraph summary that includes any upgrade instruction, then a flat bullet list focused on what users actually invoke (commands, flags, errors they see, breaking changes for CI/scripts). Tagging (`git tag vX.Y.Z`) is a post-merge ritual, not a CI gate.

Conflict-trap: when two MRs both bump `aidlc-version.ts` to the same patch number, the second-to-merge resolves by rebasing onto main and re-bumping (e.g. `0.3.4` → `0.3.5`) plus renaming its `## [0.3.4]` heading + `[0.3.4]:` link reference to `## [0.3.5]` / `[0.3.5]:`. t68 catches a missed CHANGELOG bullet, a missing link reference, AND duplicate `## [N.N.N]` headings post-rebase.
