#!/bin/bash
# t06: SKILL.md frontmatter valid (9 tests)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/tap.sh"

SKILL="$(cd "$SCRIPT_DIR/../../aidlc-claude-code/.claude/skills/aidlc" && pwd)/SKILL.md"

plan 9

# name: aidlc
assert_grep "$SKILL" "^name: aidlc" "SKILL.md name is aidlc"

# description: present
assert_grep "$SKILL" "^description:" "SKILL.md has description"

# user-invocable: true
assert_grep "$SKILL" "^user-invocable: true" "SKILL.md is user-invocable"

# PostToolUse hook with Write|Edit matcher
assert_grep "$SKILL" "PostToolUse" "SKILL.md registers PostToolUse hook"
assert_grep "$SKILL" "audit-logger.ts" "SKILL.md references audit-logger.ts"

# PreCompact hook
assert_grep "$SKILL" "PreCompact" "SKILL.md registers PreCompact hook"
assert_grep "$SKILL" "validate-state.ts" "SKILL.md references validate-state.ts"

# SubagentStop hook
assert_grep "$SKILL" "SubagentStop" "SKILL.md registers SubagentStop hook"
assert_grep "$SKILL" "log-subagent.ts" "SKILL.md references log-subagent.ts"

finish
