# Claude Code Features

This chapter documents how AI-DLC maps onto Claude Code's native feature set. Hooks and the knowledge system are covered in dedicated chapters; this chapter focuses on skills, agents, rules, CLAUDE.md, and settings.

For hooks: see [Hooks and Tools](06-hooks-and-tools.md). For knowledge: see [Knowledge System](10-knowledge-system.md).

---

## Feature-to-Concept Mapping

AI-DLC is implemented entirely on top of Claude Code's native primitives:

| Claude Code Primitive | AI-DLC Concept |
|-----------------------|---------------|
| **Skills** | Orchestrator entry point (`/aidlc`), skill-scoped hooks |
| **Agents** | 11 domain-expert personas (flat `.md` files with frontmatter) |
| **Hooks** | Automated audit logging, state validation, subagent tracking (see [Hooks and Tools](06-hooks-and-tools.md)) |
| **Rules** | Minimal self-learning guardrails (~35 lines) |
| **CLAUDE.md** | Project-level instructions, prerequisites, conventions |
| **Settings** | Permissions configuration (`.claude/settings.json`) |

---

## Skills

### SKILL.md as Entry Point

The orchestrator lives at `.claude/skills/aidlc/SKILL.md`. Users invoke it with the `/aidlc` command. The file uses YAML frontmatter to declare metadata:

```yaml
---
name: aidlc
description: >
  AI-DLC workflow orchestrator. Start, resume, or manage an AI-driven
  development lifecycle.
argument-hint: "[description | --status | --stage <slug|#> | --phase <name|#> | --help]"
user-invocable: true
hooks:
  PostToolUse:
    - matcher: "Write|Edit"
      hooks:
        - type: command
          command: "bun $CLAUDE_PROJECT_DIR/.claude/hooks/aidlc-audit-logger.ts"
    - matcher: "TaskUpdate"
      hooks:
        - type: command
          command: "bun $CLAUDE_PROJECT_DIR/.claude/hooks/aidlc-sync-statusline.ts"
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
```

| Field | Purpose |
|-------|---------|
| `name` | Registers the skill as `/aidlc` in Claude Code's command system |
| `description` | Displayed in skill discovery and help text |
| `argument-hint` | Placeholder text shown after `/aidlc` to indicate accepted arguments |
| `user-invocable` | Set to `true` so the user can trigger it directly |
| `hooks` | Declares skill-scoped hooks that fire only when this skill is active |

The body of SKILL.md contains the full orchestrator logic: session detection, scope-to-stage mapping, the stage graph, agent delegation patterns, routing instructions, and stage advancement rules. At ~480 lines, it is the single largest file in the framework.

### Skill-Scoped Hooks

The `hooks` block in SKILL.md frontmatter scopes these hooks to fire **only** when `/aidlc` is active. They do not fire during normal Claude Code usage outside of AI-DLC. See [Hooks and Tools](06-hooks-and-tools.md) for full details.

### Companion Files

SKILL.md references two companion file sets in `.claude/skills/aidlc/`:

- **`stage-protocol.md`** -- Mandatory protocol for all 32 stages (approval gates, question formatting, audit logging rules, completion messages, phase-boundary verification).
- **Stage files** in `stages/initialization/`, `stages/ideation/`, `stages/inception/`, `stages/construction/`, `stages/operation/` -- 32 individual stage definitions.

---

## Agents

### Agent File Format

AI-DLC defines 11 agent files as flat `.md` files in `.claude/agents/`. Each uses YAML frontmatter followed by a markdown body. The frontmatter controls Claude Code's behavior when the agent is activated; the body provides persona, responsibilities, stage ownership, collaboration patterns, knowledge loading order, and key principles.

For full agent system documentation, see [Agent System](05-agent-system.md).

### Inline vs Subagent Loading

The orchestrator uses two modes of agent activation:

**Inline execution (30 of 32 stages):**
The orchestrator reads the agent's `.md` file and adopts the persona directly within the main conversation. The user interacts with the agent in real time.

**Subagent execution (2 stages: 2.1, 3.5):**
The orchestrator delegates to a separate Claude instance via the Claude Code Task tool. The subagent runs in isolation, receives context via the prompt, and returns a structured summary.

| Stage | Claude Code Subagent Type | Agent | Reason |
|-------|---------------------------|-------|--------|
| 2.1 Reverse Engineering | `aidlc-developer-agent` then `aidlc-architect-agent` (two-step) | aidlc-developer-agent + aidlc-architect-agent | Deep code analysis produces large intermediate output |
| 3.5 Code Generation | `aidlc-developer-agent` | aidlc-developer-agent | Code writing benefits from clean context focused on the unit specification |

Workspace detection (0.2) used to be a subagent; it now runs deterministically inside `aidlc-utility init`.

### Model Overrides

| Model | Agents | Rationale |
|-------|--------|-----------|
| `opus` | architect, product, design, developer, quality, devsecops, compliance, aws-platform (8) | High-judgment, multi-constraint reasoning whose decisions cascade downstream — architectural boundaries, intent interpretation, UX trade-offs, code synthesis, threat prioritisation, regulatory edge-cases, cloud architecture |
| `sonnet` | delivery, pipeline-deploy, operations (3) | Output is dominantly templated planning tables, CI/CD YAML, or observability/runbook scaffolding; methodology is encoded in the agent's knowledge files |

---

## Rules

### The flat layered rule files

AI-DLC uses `.claude/rules/` for behavioral rules. The directory is flat — one file per layer of the inheritance chain:

```
.claude/rules/
├── aidlc-org.md                  # framework defaults (shipped)
├── aidlc-team.md                 # this team's affirmed practices
├── aidlc-project.md              # this project's specialization
├── aidlc-phase-ideation.md       # rules scoped to a phase
├── aidlc-phase-inception.md
├── aidlc-phase-construction.md
└── aidlc-phase-operation.md
```

Each file carries topical `##` headings (Way of Working, Testing Posture, Deployment, Code Style, Forbidden, Mandated, and so on). At workflow start the compile resolver walks the chain **org → team → project → phase → stage** and bakes the resolved rule set onto each stage's graph node. The model is **strict-additive**: every applicable rule from every layer appears in the agent's context simultaneously — a narrower layer never silently overrides a broader one. A rule that would *contradict* a broader-scope rule is rejected at the admission gate when it is written, not reconciled at runtime. The authoritative layout, scope derivation, and conflict semantics are in [Rule System](08-rule-system.md).

**Why the org/team files stay lean:** Claude Code loads every file in `.claude/rules/` into each conversation, including non-AI-DLC ones. Keeping the shipped layers to concise, topical structure avoids polluting regular development sessions. Detailed methodology that the upstream specification places in rules instead lives in `.claude/knowledge/aidlc-shared/` or in SKILL.md and stage-protocol.md, loaded only when `/aidlc` is active.

### The Learning Loop

The rule files are not static — the v0.5.0 learning loop turns an in-workflow correction into a standing rule for next time. The division of labor is deliberate: the LLM's only job is to write observations to the stage's `memory.md` diary while the stage runs (Interpretations / Deviations / Tradeoffs / Open questions). Everything else is a deterministic tool or a human decision:

1. **Diary (LLM).** During the stage, observations accumulate in `aidlc-docs/<phase>/<stage>/memory.md`.
2. **Surface (tool).** At the approval gate, `aidlc-learnings.ts surface` reads the diary and emits structured candidates — the LLM does not re-parse or classify.
3. **Confirm (human).** The orchestrator renders the candidates; you pick which to keep and, for free-text additions, pick the single heading that derives the destination.
4. **Admission check (knowledge).** Each kept learning is checked against `aidlc-org.md`'s matching section; a contradiction is surfaced for you to revise, skip, or escalate.
5. **Persist (tool).** `aidlc-learnings.ts persist` writes confirmed learnings to `aidlc-{project,team}-learnings.md` as dated entries and, for a sensor-binding learning, installs the manifest plus the stage `sensors:` import inside one locked transaction. It emits `RULE_LEARNED` / `SENSOR_PROPOSED`.

The user-facing walk-through (with a worked example) is in [Rules and the Learning Loop](../guide/08-rules-and-the-learning-loop.md); the harness-engineer authoring angle is in [Rules and the Learning Loop](../harness/05-rules-and-the-loop.md).

---

## CLAUDE.md

### Project-Level Instructions

`.claude/CLAUDE.md` provides project-level instructions loaded into every conversation. For AI-DLC, it serves as the bootstrap document.

**Key sections:**

| Section | Contents |
|---------|----------|
| Prerequisites | `bun` (only runtime dependency); `mkdir`-based locking |
| AI-DLC Structure | Skill, agent, rules, knowledge, and hook locations |
| Conventions | Artifacts go to `aidlc-docs/`; application code goes to workspace root |
| Session Resumption | Check for `aidlc-state.md` on startup, offer resume options |
| Git Integration | Commit policy (see below) |

### Git Integration

```
Commit: aidlc-docs/ (all artifacts and state)
Gitignore:
  - aidlc-docs/audit.md       (may contain sensitive user input)
  - .aidlc-recovery.md        (transient hook breadcrumb)
```

`audit.md` is excluded because it may contain tool invocation details, file paths, and user input. `.aidlc-recovery.md` is transient and has no value outside the active session.

---

## Settings

### Permissions Configuration

`.claude/settings.json` pre-approves Claude Code tools so workflows run without per-invocation permission prompts:

```json
{
  "permissions": {
    "allow": [
      "Read", "Edit", "Write", "Bash",
      "Glob", "Grep", "Task", "WebSearch"
    ]
  }
}
```

Without this, Claude Code would prompt "Allow this tool?" on each first use, disrupting the workflow -- particularly during subagent delegation where the user is not directly interacting.

### Status Line Configuration

```json
"statusLine": {
  "type": "command",
  "command": "bun $CLAUDE_PROJECT_DIR/.claude/hooks/aidlc-statusline.ts"
}
```

Runs periodically (not just on tool use) to keep the terminal status current.

### SessionStart and SessionEnd Hook Configuration

```json
"hooks": {
  "SessionStart": [{
    "matcher": "",
    "hooks": [{
      "type": "command",
      "command": "bun $CLAUDE_PROJECT_DIR/.claude/hooks/aidlc-session-start.ts"
    }]
  }],
  "SessionEnd": [{
    "matcher": "",
    "hooks": [{
      "type": "command",
      "command": "bun $CLAUDE_PROJECT_DIR/.claude/hooks/aidlc-session-end.ts"
    }]
  }]
}
```

Registered in `settings.json` (project-wide) rather than SKILL.md (skill-scoped) because session lifecycle events fire before `/aidlc` activates and after it exits — `session-start.ts` injects resume context, `session-end.ts` emits `SESSION_ENDED` for audit completeness.

### Personal Settings Override

`.claude/settings.local.json` (gitignored) overrides shared settings without affecting the repository:

```bash
cp .claude/settings.local.json.example .claude/settings.local.json
```

---

## MCP Servers

### .mcp.json as the Server Registry

AI-DLC declares its Model Context Protocol (MCP) servers in `.mcp.json` at the project root, beside `.claude/` rather than inside it. The file maps server names to their transport and launch configuration:

```json
{
  "mcpServers": {
    "context7": {
      "type": "http",
      "url": "https://mcp.context7.com/mcp",
      "headers": {
        "CONTEXT7_API_KEY": "${CONTEXT7_API_KEY}"
      }
    },
    "aws-mcp": {
      "command": "uvx",
      "args": [
        "mcp-proxy-for-aws@latest",
        "https://aws-mcp.us-east-1.api.aws/mcp",
        "--metadata",
        "AWS_REGION=us-east-1"
      ]
    },
    "aws-pricing": { "command": "uvx", "args": ["awslabs.aws-pricing-mcp-server@latest"] },
    "aws-iac": { "command": "uvx", "args": ["awslabs.aws-iac-mcp-server@latest"] },
    "aws-serverless": { "command": "uvx", "args": ["awslabs.aws-serverless-mcp-server@latest"] }
  }
}
```

The five shipped servers cover the integrations the framework's agents reach for:

| Server | Transport | Auth | Purpose |
|--------|-----------|------|---------|
| `context7` | HTTP | `${CONTEXT7_API_KEY}` env passthrough | Library/SDK documentation lookups |
| `aws-mcp` | `uvx` (`mcp-proxy-for-aws@latest`, `AWS_REGION=us-east-1`) | Standard AWS credential chain | AWS API access |
| `aws-pricing` | `uvx` (`awslabs.aws-pricing-mcp-server@latest`) | AWS credential chain | AWS pricing |
| `aws-iac` | `uvx` (`awslabs.aws-iac-mcp-server@latest`) | AWS credential chain | Infrastructure-as-code tooling |
| `aws-serverless` | `uvx` (`awslabs.aws-serverless-mcp-server@latest`) | AWS credential chain | Serverless tooling |

The registry carries only environment-variable placeholders — no committed secrets. Credentials flow through your shell: `context7` reads `CONTEXT7_API_KEY` from the environment, and the four `uvx`-launched AWS servers authenticate against your standard AWS credential chain (install `uv`/`uvx` via `curl -fsSL https://astral.sh/uv/install.sh | sh`). A server you have no credentials for is simply unavailable to the session and never blocks a workflow.

`.mcp.json` lives at the project root because that is the path Claude Code reads for project-scoped MCP servers. AI-DLC currently ships as a `.claude/` directory copy rather than a Claude Code plugin, but the project-root `.mcp.json` placement is also the canonical plugin location, so the registry is plugin-portable without change.

### Provisioning and Inheritance

The access model is provisioning followed by inheritance, with no grant step between them:

1. **Declare once.** Servers are listed in `.mcp.json` at the project root.
2. **Provision to the session.** Claude Code starts the declared servers and exposes their tools to the session as `mcp__<server>__<tool>` ids.
3. **Inherit everywhere.** Subagents inherit all session MCP tools by default. Every AI-DLC agent — whether running inline or as a delegated subagent (stages 2.1, 3.5) — reaches every declared server.

There is no per-agent grant step, and none is needed: inheritance is the default and it is additive across all agents. A new agent file gains MCP access by existing, not by listing servers in its frontmatter.

### Why There Is No Per-Agent Grant

This is the load-bearing lesson, and it is worth stating plainly so it is not re-litigated. **MCP access cannot be granted to an agent by addition — it is inherited, and the only lever is restriction.** An empirical spike against Claude Code 2.1.159 established the boundaries:

- An agent gains nothing by *naming* a server in its frontmatter. There is no additive grant field. Inheritance has already given the agent every session MCP tool.
- To *prevent* an agent from using a server, narrow its `tools:` allowlist (the real Claude Code frontmatter field) to the fully-qualified `mcp__<server>__<tool>` ids it is permitted to call. Omitting a tool from a populated `tools:` list is what denies it.
- A bare `mcp__<server>` token is **not** honored — there is no server-level wildcard. Only fully-qualified `mcp__<server>__<tool>` ids match.
- `disallowedTools` is a real, working field on the denylist side. AI-DLC uses `disallowedTools: Task` to block nested subagent spawning; that denial does not affect MCP server access.

The spike also surfaced a separate frontmatter footgun: `allowedTools` is **not** a recognized Claude Code subagent field and is silently ignored. An agent declaring `allowedTools: Read` still reached an MCP tool, behaving identically to inherit-all, whereas the same agent with `tools: Read` correctly denied it. The resolution (v0.5.4): the silently-ignored `allowedTools` field has been removed from every shipped agent file (`.claude/agents/*.md`). The agents now intentionally inherit the full session toolset — built-in tools and MCP tools alike — and the only declared restriction is `disallowedTools: Task`. The documented opt-in narrowing is the real `tools:` allowlist, which drops inherited MCP unless the fully-qualified `mcp__<server>__<tool>` ids are also listed. So inherit-all is now the deliberate, documented model rather than an accident of an ignored field: every agent reaches every declared server today.

### Relationship to settings.json Permissions

The two configuration files answer different questions and do not overlap:

- `.claude/settings.json` `permissions.allow` pre-approves *built-in Claude Code tools* (Read, Edit, Write, Bash, Glob, Grep, Task, WebSearch) so the session does not prompt on first use (see [Settings](#settings) above). It says nothing about MCP servers.
- `.mcp.json` declares *which MCP servers exist* and how to launch them. Provisioning and inheritance are governed by Claude Code's MCP layer, not by `settings.json`.

An MCP server appearing in the session is a function of `.mcp.json` plus available credentials, not of any `settings.json` allow-list entry. Per-agent narrowing, when it is wired, lives in the agent's `tools:` frontmatter — not in `settings.json` and not in `.mcp.json`.

---

## Feature Interaction Map

| Feature | File(s) | When It Loads | Role |
|---------|---------|---------------|------|
| CLAUDE.md | `.claude/CLAUDE.md` | Every conversation | Bootstrap: structure, prerequisites, conventions |
| Settings | `.claude/settings.json` | Every conversation | Pre-approve Claude Code tools |
| Rules | `.claude/rules/*.md` | Every conversation | Minimal guardrails; self-learning corrections |
| Skill | `.claude/skills/aidlc/SKILL.md` | On `/aidlc` invocation | Orchestrator: session, scope, stage graph, delegation |
| Skill hooks | SKILL.md frontmatter | When `/aidlc` is active | PostToolUse, PreCompact, SubagentStop |
| Agents (inline) | `.claude/agents/*.md` | Persona activation | 30 of 32 stages: orchestrator adopts agent persona |
| Agents (subagent) | `.claude/agents/*.md` | Task tool delegation | 2 stages (2.1, 3.5): isolated execution |
| Knowledge (Tier 1) | `.claude/knowledge/` | Persona activation (steps 2-3) | 52 methodology reference files |
| Knowledge (Tier 2) | `aidlc-docs/knowledge/` | Persona activation (steps 4-5) | Team-managed customization |
| Stage protocol | `stage-protocol.md` | Every stage execution | Mandatory behavioral contract |
| Stage files | `stages/**/*.md` | Orchestrator routing | 32 individual stage definitions |
| State file | `aidlc-state.md` | Session start + throughout | Persistent workflow state |
| Audit file | `audit.md` | Throughout execution | Append-only audit trail |

### Loading Sequence

When a user runs `/aidlc feature`:

```
1.  CLAUDE.md loads              (every conversation)
1a. statusLine command starts    (settings.json -- runs continuously)
2.  settings.json loads          (every conversation)
2a. SessionStart hook fires      (settings.json -- if session resume)
3.  rules/ load (every conversation)
4.  SKILL.md activates           (skill invocation)
5.  Skill-scoped hooks register  (skill activation)
6.  Orchestrator reads state     (session check)
7.  Orchestrator reads stage     (routing)
8.  Agent .md file loads         (persona activation)
9.  Knowledge loads (5 steps)    (persona activation)
10. Stage executes               (stage work)
11. Hooks fire as needed         (Claude Code tool calls, compaction, subagent stop)
12. State updates                (stage advancement)
13. Next stage begins            (routing loops back to step 7)
```

Steps 1-2a happen for every conversation, even non-AI-DLC ones. Steps 3-5 set up skill context only when the user invokes `/aidlc`. Steps 7-13 repeat for each stage.

---

## Cross-References

- [Architecture](01-architecture.md) -- 5-layer model including all feature layers
- [Orchestrator](03-orchestrator.md) -- SKILL.md deep-dive
- [Agent System](05-agent-system.md) -- agent frontmatter, tool restrictions, model overrides
- [Hooks and Tools](06-hooks-and-tools.md) -- hook system, audit taxonomy, CLI tools
- [Knowledge System](10-knowledge-system.md) -- two-tier knowledge, loading order
