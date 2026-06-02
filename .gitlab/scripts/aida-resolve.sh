#!/usr/bin/env bash
set -euo pipefail

LOG_FILE="aida-output.log"
export API_URL="${CI_API_V4_URL}/projects/${CI_PROJECT_ID}"

AIDA_SOURCE_TYPE="${AIDA_SOURCE_TYPE:-issue}"

if [ "$AIDA_SOURCE_TYPE" = "mr" ]; then
  NOTES_PATH="merge_requests/${MR_IID}"
  BRANCH_NAME="${MR_SOURCE_BRANCH}"
  SOURCE_IID="${MR_IID}"
  SOURCE_LABEL="MR !${MR_IID}"
  SOURCE_TITLE="${MR_TITLE:-}"
  SOURCE_DESCRIPTION="${MR_DESCRIPTION:-}"
else
  NOTES_PATH="issues/${ISSUE_IID}"
  BRANCH_NAME="${ISSUE_IID}-$(echo "$ISSUE_TITLE" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | head -c 60)"
  SOURCE_IID="${ISSUE_IID}"
  SOURCE_LABEL="issue #${ISSUE_IID}"
  SOURCE_TITLE="${ISSUE_TITLE}"
  SOURCE_DESCRIPTION="${ISSUE_DESCRIPTION}"
fi
export NOTES_PATH

# Exclude log artifact from git
mkdir -p "$(git rev-parse --git-dir)/info"
echo "$LOG_FILE" >> "$(git rev-parse --git-dir)/info/exclude"

log() { echo "[$(date -u +%H:%M:%S)] $*" | tee -a "$LOG_FILE"; }
debug() { [ "${AIDA_DEBUG:-}" = "true" ] && log "DEBUG: $*" || true; }

react_to_comment() {
  local emoji="$1"
  [ -z "${AIDA_COMMENT_ID:-}" ] && return 0
  curl --silent --fail \
    --header "PRIVATE-TOKEN: ${GITLAB_TOKEN_AIDA}" \
    --request POST \
    "${API_URL}/${NOTES_PATH}/notes/${AIDA_COMMENT_ID}/award_emoji" \
    --data "name=${emoji}" >/dev/null 2>&1 || true
}

update_progress_note() {
  curl --silent --fail \
    --header "PRIVATE-TOKEN: ${GITLAB_TOKEN_AIDA}" \
    --request PUT \
    "${API_URL}/${NOTES_PATH}/notes/${PROGRESS_NOTE_ID}" \
    --data-urlencode "body=$1" >/dev/null 2>&1 || true
}

fetch_source_context() {
  local notes
  notes=$(curl --silent --fail \
    --header "PRIVATE-TOKEN: ${GITLAB_TOKEN_AIDA}" \
    "${API_URL}/${NOTES_PATH}/notes?sort=asc&per_page=50") || true
  if [ -z "$notes" ] || [ "$(echo "$notes" | jq 'length')" -eq 0 ]; then
    SOURCE_COMMENTS="(no comments)"
    return
  fi
  # Exclude bot noise (emoji-prefixed status messages) but keep substantive bot content (## headings)
  SOURCE_COMMENTS=$(echo "$notes" | jq -r '
    [.[] | select(
      (.author.username | test("^project_.*_bot$") | not) or
      (.body | test("^## "))
    )] | .[] | "[\(.author.username)] \(.body)"
  ' | head -c 8000)
}

# --- Setup ---
debug "SOURCE_TYPE=$AIDA_SOURCE_TYPE SOURCE_IID=$SOURCE_IID AIDA_COMMAND=${AIDA_COMMAND:-} AIDA_COMMENT_ID=$AIDA_COMMENT_ID"
debug "BRANCH_NAME=$BRANCH_NAME"
log "AIDA resolving ${SOURCE_LABEL}"
react_to_comment "rocket"  # = working on it
fetch_source_context

# Create progress comment — this is the ONLY user-facing output
PROGRESS_BODY='## AIDA — ⏳ In progress'
PROGRESS_NOTE_ID=$(curl --silent --fail \
  --header "PRIVATE-TOKEN: ${GITLAB_TOKEN_AIDA}" \
  --request POST "${API_URL}/${NOTES_PATH}/notes" \
  --data-urlencode "body=${PROGRESS_BODY}" | jq -r '.id')
export PROGRESS_NOTE_ID

# Helper: Claude calls this to update progress in real-time
# Claude passes body only — the system prepends the status header
cat > /tmp/aida-progress.sh << 'HELPER'
#!/bin/bash
printf '%s' "$1" > /tmp/aida-body.md
printf '\n---\n%s' "$1" >> /tmp/aida-progress-log.md
curl --silent --fail \
  --header "PRIVATE-TOKEN: ${GITLAB_TOKEN_AIDA}" \
  --request PUT \
  "${API_URL}/${NOTES_PATH}/notes/${PROGRESS_NOTE_ID}" \
  --data-urlencode "body=## AIDA — ⏳ In progress

$1" >/dev/null 2>&1
HELPER
chmod +x /tmp/aida-progress.sh

# --- Branch handling: only checkout for MR-triggered tasks ---
if [ "$AIDA_SOURCE_TYPE" = "mr" ]; then
  log "Checking out MR source branch $BRANCH_NAME"
  git checkout "$BRANCH_NAME" && git pull origin "$BRANCH_NAME"
fi

# --- Trap: post timeout notice on crash ---
cleanup() {
  if [ -n "${PROGRESS_NOTE_ID:-}" ]; then
    update_progress_note "## AIDA — ⚠️ Timed out"
    react_to_comment "x"
  fi
}
trap cleanup EXIT

# --- Build prompt ---

# Check for existing branch with prior commits (issue-triggered only)
PRIOR_WORK_SECTION=""
if [ "$AIDA_SOURCE_TYPE" != "mr" ]; then
  if git ls-remote --exit-code --heads origin "$BRANCH_NAME" >/dev/null 2>&1; then
    PRIOR_WORK=$(git log --oneline "origin/main..origin/$BRANCH_NAME" 2>/dev/null || true)
    if [ -n "$PRIOR_WORK" ]; then
      PRIOR_WORK_SECTION=$(printf 'Previous commits on branch %s:\n%s\n\nThe branch already exists on the remote. Run `git checkout %s` to continue.\n' "$BRANCH_NAME" "$PRIOR_WORK" "$BRANCH_NAME")
    fi
  fi
fi

MR_DIFF_SECTION=""
if [ "$AIDA_SOURCE_TYPE" = "mr" ]; then
  MR_DIFF=$(git diff --stat origin/main.."$BRANCH_NAME" | tail -5)
  if [ -n "$MR_DIFF" ]; then
    MR_DIFF_SECTION=$(printf 'Current MR diff summary:\n%s\n' "$MR_DIFF")
  fi
fi

# Build environment/instruction section based on source type
if [ "$AIDA_SOURCE_TYPE" = "mr" ]; then
  ENV_INSTRUCTIONS=$(cat <<ENVBLOCK
ENVIRONMENT:
- Running in CI on branch ${BRANCH_NAME} (the MR source branch).
- Git remote has push access.
- GitLab API: ${API_URL} (auth header: PRIVATE-TOKEN: \$GITLAB_TOKEN_AIDA)
- Update progress: bash /tmp/aida-progress.sh "<markdown body>"

INSTRUCTIONS:
- Decide what the user needs: code changes, a review, an answer, or analysis.
- For code changes: edit files, commit with message "fix(!${SOURCE_IID}): <description>",
  then git push origin ${BRANCH_NAME}.
- For reviews or questions: output your response as text.
- If you need clarification, ask in your text output.
- Update progress after each major step.
- Your final text output will be posted as a comment on ${SOURCE_LABEL}.
ENVBLOCK
  )
else
  ENV_INSTRUCTIONS=$(cat <<ENVBLOCK
ENVIRONMENT:
- Running in CI on the main branch. Git remote has push access.
- Branch name for this task: ${BRANCH_NAME}
- GitLab API: ${API_URL} (auth header: PRIVATE-TOKEN: \$GITLAB_TOKEN_AIDA)
- Update progress: bash /tmp/aida-progress.sh "<markdown body>"

INSTRUCTIONS:
- Decide what the user needs: code changes, a review, an answer, or analysis.
- For code changes:
  1. git checkout -b ${BRANCH_NAME}
  2. Edit files, commit with message "fix(#${SOURCE_IID}): <description>"
  3. git push -u origin ${BRANCH_NAME}
  4. Create a merge request via the GitLab API (POST to ${API_URL}/merge_requests)
     with source_branch=${BRANCH_NAME}, target_branch=main,
     title="Resolve #${SOURCE_IID}: ${SOURCE_TITLE}".
- For reviews or questions: output your response as text. Do not modify files.
- If you need clarification, ask in your text output. The user can reply
  with @aida and the conversation continues (you'll see the full thread).
- Update progress after each major step.
- Your final text output will be posted as a comment on ${SOURCE_LABEL}.
ENVBLOCK
  )
fi

PROMPT=$(cat <<PROMPT
You are AIDA, an automated development agent working on ${SOURCE_LABEL}: ${SOURCE_TITLE}

Description:
${SOURCE_DESCRIPTION}

User request:
${AIDA_COMMENT_BODY}

Comment thread:
${SOURCE_COMMENTS}

${PRIOR_WORK_SECTION}
${MR_DIFF_SECTION}

PROGRESS UPDATES:
Update your progress by running:
  bash /tmp/aida-progress.sh "- [x] Completed step
- [ ] Next step"
Call this after completing each major step so the user can follow along.
The system automatically adds the status header — just pass your content.
Progress updates are for SHORT STATUS CHECKLISTS ONLY — each call overwrites the previous one.
Do NOT put your actual deliverable (tables, analysis, review text) in progress updates.
Your complete results MUST be in your final text output — that is what gets posted permanently.
Do not write status or completion messages (e.g. "Done", "Complete").

${ENV_INSTRUCTIONS}
PROMPT
)

# --- Single Claude invocation ---
log "Invoking Claude"
set +e
CLAUDE_OUTPUT=$(claude -p "$PROMPT" \
  --model "${CLAUDE_MODEL:-opus}" \
  --allowedTools "Bash,Read,Edit,Write,Glob,Grep" \
  --permission-mode acceptEdits \
  --output-format text \
  2>> "$LOG_FILE")
CLAUDE_RC=$?
set -e
log "Claude exited with code $CLAUDE_RC"

# --- Result handling ---
trap - EXIT

PROGRESS_BODY=""
[ -f /tmp/aida-body.md ] && PROGRESS_BODY=$(cat /tmp/aida-body.md)

if [ "$CLAUDE_RC" -ne 0 ]; then
  react_to_comment "x"
  STATUS_LINE="## AIDA — Failed ❌"
  FOOTER=""
elif [ -n "$CLAUDE_OUTPUT" ]; then
  react_to_comment "white_check_mark"
  STATUS_LINE="## AIDA — Complete ✅"
  FOOTER=$(printf '\n\n---\n\n%s' "$CLAUDE_OUTPUT")
else
  react_to_comment "white_check_mark"
  STATUS_LINE="## AIDA — Complete ✅"
  FOOTER=""
fi

if [ -n "$PROGRESS_BODY" ]; then
  update_progress_note "$(printf '%s\n\n%s%s' "$STATUS_LINE" "$PROGRESS_BODY" "$FOOTER")"
else
  update_progress_note "$(printf '%s%s' "$STATUS_LINE" "$FOOTER")"
fi

log "AIDA resolve complete."
