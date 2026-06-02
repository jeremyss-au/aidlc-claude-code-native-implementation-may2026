# Scopes

A scope is the dial that decides *which* of the framework's 32 stages run for a given kind of work, and which sit out. A bugfix doesn't need market research or a deployment pipeline; a regulated enterprise feature needs all of it. Rather than asking the user to hand-pick stages every time, AI-DLC ships nine named scopes — each one a curated EXECUTE/SKIP verdict over the full stage set, paired with a default depth and test strategy. Pick the scope and the rest cascades.

For a harness engineer, a scope is pure data. It lives entirely in one JSON file — `aidlc-claude-code/.claude/tools/data/scope-mapping.json` — and adding or tuning one requires no TypeScript. This chapter walks the workflow: what a scope is made of, how to add a team scope, how to tune an existing one, and what the tooling checks for you versus what it leaves to you.

For the full nine-scope catalog with use cases and the routing table users read, see [Scopes, Depth, and Test Strategy](../guide/04-scopes-and-depth.md) in the User Guide. This chapter is the authoring side of that same data.

---

## What a scope is made of

Each scope is a single top-level key in `scope-mapping.json`. The `feature` scope, the default for new work, looks like this in shape:

```json
"feature": {
  "depth": "Standard",
  "keywords": [],
  "description": "Default for new features, practical depth",
  "stages": {
    "workspace-scaffold": "EXECUTE",
    "intent-capture": "EXECUTE",
    "feedback-optimization": "EXECUTE"
  }
}
```

The fields divide into one required pair and three optional knobs:

| Field | Required | What it does |
|-------|----------|--------------|
| `depth` | Yes | The default detail level — `"Minimal"`, `"Standard"`, or `"Comprehensive"`. |
| `stages` | Yes | A map from every stage slug to `"EXECUTE"` or `"SKIP"`. This *is* the scope. |
| `testStrategy` | No | Overrides test volume independent of depth. Defaults to matching `depth`. |
| `keywords` | No | Natural-language triggers for `/aidlc <freeform text>` auto-detection. Empty array opts out. |
| `description` | No | The one-liner rendered in `/aidlc --help`. (The compiled scope-table in SKILL.md shows only Scope / Depth / TestStrategy / EXECUTE-Total — not the description.) |

The `stages` map is the heart of it. Every one of the 32 stage slugs declared in `stage-graph.json` should appear with an explicit `EXECUTE` or `SKIP`. A slug you forget to list is treated as absent — the stage simply won't appear in the plan, which is almost never what you want. When in doubt, copy a neighboring scope's full `stages` block and flip the verdicts you need to change.

The one judgment call worth understanding is the relationship between `depth` and `testStrategy`. Depth controls how much detail each stage's artifacts carry; test strategy controls how many tests get generated. They're independent on purpose. Most scopes leave `testStrategy` off, so it inherits from `depth` — a Standard-depth scope tests at Standard volume. The `workshop` scope is the shipped example that breaks the tie: it runs `"depth": "Standard"` (full artifacts, because participants are learning) but `"testStrategy": "Minimal"` (fast Nyquist testing, to keep the session moving). If your scope wants that split, declare both. For what each level means, see [The 3 Depth Levels](../guide/04-scopes-and-depth.md#the-3-depth-levels) and [The 3 Test Strategy Levels](../guide/04-scopes-and-depth.md#the-3-test-strategy-levels) in the User Guide.

The exhaustive field-by-field contract — including how `keywords` are word-boundary matched and how the alphabetical-scope tie-break resolves an ambiguous freeform invocation — lives in [Contributing § Adding a Scope](../reference/11-contributing.md#adding-a-scope) in the Developer Reference. This chapter summarizes the decisions; that section is the normative spec.

---

## How scopes relate to stages

A scope and a stage point at each other from opposite ends, and it helps to hold both directions in view.

A **stage** declares its own identity — its phase, its lead agent, the artifacts it consumes and produces. It says nothing about which scopes include it. A **scope** is the inverse: a flat verdict over the whole stage set, with no knowledge of what any stage actually does. The binding between them is the slug. When you add a new stage (see [Adding a Stage](02-adding-a-stage.md)), the framework doesn't decide its scope membership for you — every existing scope still lists only the slugs it knew about, so your new stage is effectively `SKIP` everywhere until you go add its slug to each scope that should run it. Adding a stage and granting it scope membership are two edits, in two files, and the second is the one people forget.

That separation is the same data-versus-code line the rest of this guide rests on (see [Harness Engineer Guide](00-overview.md)). The scope is data about *selection*; the stage is data about *work*; neither contains the other.

---

## Adding a team scope

Suppose your team wants a `hotfix` scope — leaner than `bugfix`, for the urgent production patch where you want a regression test and a deploy, nothing else. The whole change is a JSON edit plus a table regeneration. Mirror the discipline below; the verification steps and the full command lines are in [Contributing § Adding a Scope](../reference/11-contributing.md#adding-a-scope).

### Steps

1. **Add the scope key to `scope-mapping.json`.** Add a new top-level object keyed by your scope name. Set `depth`, then write a `stages` map covering all 32 slugs — start from `bugfix`'s map (the closest existing scope) and flip what differs. Add `keywords` if you want freeform auto-detection (`["hotfix", "urgent"]`), a `description` for the help text, and `testStrategy` only if it should diverge from `depth`.

2. **Regenerate SKILL.md's compiled scope-table.** Run `bun .claude/tools/aidlc-utility.ts scope-table` and paste its output between the `<!-- BEGIN: compiled ... -->` / `<!-- END: compiled ... -->` markers in `.claude/skills/aidlc/SKILL.md`. The orchestrator reads its scope summary from that compiled block, not from the JSON directly, so this regeneration is what makes the scope visible to the workflow. Run `bun .claude/tools/aidlc-utility.ts scope-table --check` to confirm there's no drift (exit 0).

3. **Verify the scope resolves and is accepted.** Run `/aidlc --doctor` to catch structural problems — `loadScopeMapping()` only JSON-parses the file, so there's no schema validation at load time and the doctor is your first guardrail. Then confirm an init under the new scope produces a state file with the right `Scope:` line, and that it's accepted as an env default and as a mid-workflow `--scope` change.

4. **Verify keyword inference** (only if you populated `keywords`). Confirm a freeform phrase containing one of your triggers detects the new scope rather than falling through to `feature`.

5. **Update the scope-aware docs and add a routing test.** Several docs enumerate scopes by hand — the User Guide's scope reference and routing table, the customization chapter's valid-values list, and the orchestrator reference's scope-to-stage mapping. Update them in the same change. If your scope skips stages in a pattern no existing scope uses, add a workflow test modeled on the existing per-scope tests.

### What validates automatically

The framework derives the valid-scope list from `scope-mapping.json` at runtime through `validScopes()`, so a lot falls into place the moment the JSON lands:

- The scope is valid everywhere at once — `init`, `--scope` change, env-default resolution, and `doctor` all consult the same helper, so none of them needs a code edit.
- Error messages list your scope in alphabetical order with no change.
- If you gave it `keywords`, freeform `/aidlc <text>` auto-detects it as soon as the array is populated — no SKILL.md prose edit, just the table regeneration.

### What does NOT validate automatically

- **The `stages` map is not schema-checked at load.** A typo'd slug, a missing slug, or an `"EXEC"` instead of `"EXECUTE"` parses cleanly and fails silently — the stage just won't run. `/aidlc --doctor` is the catch; run it after every edit.
- **The compiled scope-table can drift.** If you edit the JSON but skip the regeneration in step 2, the orchestrator keeps reading the stale table. The `--check` flag (run by the test suite) catches this, but only if you run it.
- **Per-scope phase-sequence coverage.** The shipped phase-sequence test iterates a hardcoded list of the known scope names; a new scope isn't exercised by it until you extend that list. Add your scope to it in the same change.
- **The hand-maintained docs.** Nothing greps the docs for you. The scope reference, the routing table, and the customization valid-values list are prose; keep them in step with the JSON yourself.

---

## Tuning an existing scope

Tuning is the same file, a smaller edit. Two changes come up often:

- **Flip a stage in or out.** Change a single `EXECUTE`/`SKIP` verdict in a scope's `stages` map. This is how you'd, say, add `observability-setup` to your `mvp` scope because your team always wires monitoring even for a first cut. One verdict, then regenerate the scope-table and run `--doctor`.
- **Change a default depth or test strategy.** Adjust `depth`, or add/remove `testStrategy`, to recalibrate what a scope produces. Because each scope carries its own defaults, this change cascades to every workflow that selects the scope — no per-run flags needed. A user can still override on any given run with `--depth` or `--test-strategy`, but the scope's value is the team-wide baseline.

Either way, the regeneration-and-doctor pair from steps 2 and 3 above applies. The edit is small; the verification is the same.

A note on layering: tuning the shipped scopes edits framework-shipped data directly. That's legitimate for a fork that wants different defaults, but be aware you're changing files that carry the `aidlc-` lineage and a framework upgrade may want to reconcile them. Adding a net-new scope key alongside the shipped nine is the cleaner path when you want a team-specific behavior without touching the defaults everyone else relies on.

---

## Next

[Rules and the Learning Loop](05-rules-and-the-loop.md) — author the standing decisions that travel into every workflow, and let the loop promote a one-time correction into a durable rule.
