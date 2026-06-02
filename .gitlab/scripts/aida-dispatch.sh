#!/usr/bin/env bash
set -euo pipefail

API_URL="${CI_API_V4_URL}/projects/${CI_PROJECT_ID}"

echo "Scanning for @aida mentions in open issues and MRs"

# --- Scan open issues ---
ISSUES=$(curl --silent --fail \
  --header "PRIVATE-TOKEN: ${GITLAB_TOKEN_AIDA}" \
  "${API_URL}/issues?state=opened&per_page=20")

if [ "$(echo "$ISSUES" | jq 'length')" -eq 0 ]; then
  echo "No open issues found."
else
  echo "$ISSUES" | jq -c '.[]' | while read -r ISSUE; do
    IID=$(echo "$ISSUE" | jq -r '.iid')
    TITLE=$(echo "$ISSUE" | jq -r '.title')
    DESC=$(echo "$ISSUE" | jq -r '.description // ""' | head -c 4000)
    AUTHOR=$(echo "$ISSUE" | jq -r '.author.username')

    # --- Check description for @aida ---
    if echo "$DESC" | grep -qi '@aida'; then
      if ! echo "$AUTHOR" | grep -q '^project_.*_bot'; then
        # Check if we already reacted with eyes emoji on the issue itself
        ISSUE_REACTIONS=$(curl --silent --fail \
          --header "PRIVATE-TOKEN: ${GITLAB_TOKEN_AIDA}" \
          "${API_URL}/issues/${IID}/award_emoji")

        if ! echo "$ISSUE_REACTIONS" | jq -e '.[] | select(.name == "eyes")' >/dev/null 2>&1; then
          COMMAND=$(echo "$DESC" | grep -oi '@aida[[:space:]]\+[a-z]\+' | head -1 | awk '{print tolower($2)}')
          COMMAND=${COMMAND:-request}

          echo "Found @aida in description of issue #${IID} (command: $COMMAND)"

          # Mark as seen with eyes reaction on the issue
          curl --silent --fail \
            --header "PRIVATE-TOKEN: ${GITLAB_TOKEN_AIDA}" \
            --request POST \
            "${API_URL}/issues/${IID}/award_emoji" \
            --data "name=eyes" >/dev/null 2>&1 || true

          # Trigger worker pipeline
          curl --silent --fail \
            --header "PRIVATE-TOKEN: ${GITLAB_TOKEN_AIDA}" \
            --header "Content-Type: application/json" \
            --request POST \
            "${API_URL}/pipeline" \
            --data "$(jq -n \
              --arg ref "main" \
              --arg iid "$IID" \
              --arg title "$TITLE" \
              --arg desc "$DESC" \
              --arg cmd "$COMMAND" \
              --arg body "$DESC" \
              '{
                ref: $ref,
                variables: [
                  {key: "AIDA_SOURCE_TYPE", value: "issue"},
                  {key: "ISSUE_IID", value: $iid},
                  {key: "ISSUE_TITLE", value: $title},
                  {key: "ISSUE_DESCRIPTION", value: $desc},
                  {key: "AIDA_COMMAND", value: $cmd},
                  {key: "AIDA_COMMENT_BODY", value: $body},
                  {key: "AIDA_COMMENT_ID", value: ""}
                ]
              }'
            )"

          echo "Pipeline triggered for issue #${IID} description (command: $COMMAND)"
        fi
      fi
    fi

    # Get recent notes (comments) on this issue
    NOTES=$(curl --silent --fail \
      --header "PRIVATE-TOKEN: ${GITLAB_TOKEN_AIDA}" \
      "${API_URL}/issues/${IID}/notes?sort=desc&per_page=20")

    # Find notes containing @aida that we haven't reacted to yet
    [ "$(echo "$NOTES" | jq 'length')" -eq 0 ] && continue

    echo "$NOTES" | jq -c '.[]' | while read -r NOTE; do
      NOTE_ID=$(echo "$NOTE" | jq -r '.id')
      BODY=$(echo "$NOTE" | jq -r '.body')
      AUTHOR=$(echo "$NOTE" | jq -r '.author.username')

      # Skip bot comments (AIDA's own responses contain @aida in text)
      echo "$AUTHOR" | grep -q '^project_.*_bot' && continue

      # Skip if no @aida mention
      echo "$BODY" | grep -qi '@aida' || continue

      # Check if we already reacted with 👀 (eyes emoji)
      REACTIONS=$(curl --silent --fail \
        --header "PRIVATE-TOKEN: ${GITLAB_TOKEN_AIDA}" \
        "${API_URL}/issues/${IID}/notes/${NOTE_ID}/award_emoji")

      if echo "$REACTIONS" | jq -e '.[] | select(.name == "eyes")' >/dev/null 2>&1; then
        continue  # Already processed
      fi

      # Parse command: first word after @aida (lowercase, for logging only — resolver doesn't route on it)
      COMMAND=$(echo "$BODY" | grep -oi '@aida[[:space:]]\+[a-z]\+' | head -1 | awk '{print tolower($2)}')
      COMMAND=${COMMAND:-request}

      echo "Found @aida command: '$COMMAND' in issue #${IID} note ${NOTE_ID}"

      # Mark as seen with 👀 reaction
      curl --silent --fail \
        --header "PRIVATE-TOKEN: ${GITLAB_TOKEN_AIDA}" \
        --request POST \
        "${API_URL}/issues/${IID}/notes/${NOTE_ID}/award_emoji" \
        --data "name=eyes" >/dev/null 2>&1 || true

      # Trigger worker pipeline
      curl --silent --fail \
        --header "PRIVATE-TOKEN: ${GITLAB_TOKEN_AIDA}" \
        --header "Content-Type: application/json" \
        --request POST \
        "${API_URL}/pipeline" \
        --data "$(jq -n \
          --arg ref "main" \
          --arg iid "$IID" \
          --arg title "$TITLE" \
          --arg desc "$DESC" \
          --arg cmd "$COMMAND" \
          --arg body "$BODY" \
          --arg note_id "$NOTE_ID" \
          '{
            ref: $ref,
            variables: [
              {key: "AIDA_SOURCE_TYPE", value: "issue"},
              {key: "ISSUE_IID", value: $iid},
              {key: "ISSUE_TITLE", value: $title},
              {key: "ISSUE_DESCRIPTION", value: $desc},
              {key: "AIDA_COMMAND", value: $cmd},
              {key: "AIDA_COMMENT_BODY", value: $body},
              {key: "AIDA_COMMENT_ID", value: $note_id}
            ]
          }'
        )"

      echo "Pipeline triggered for issue #${IID} (command: $COMMAND)"
    done
  done
fi

# --- Scan open merge requests ---
MRS=$(curl --silent --fail \
  --header "PRIVATE-TOKEN: ${GITLAB_TOKEN_AIDA}" \
  "${API_URL}/merge_requests?state=opened&per_page=20")

if [ "$(echo "$MRS" | jq 'length')" -gt 0 ]; then
  echo "$MRS" | jq -c '.[]' | while read -r MR; do
    MR_IID=$(echo "$MR" | jq -r '.iid')
    MR_TITLE=$(echo "$MR" | jq -r '.title')
    MR_DESC=$(echo "$MR" | jq -r '.description // ""' | head -c 4000)
    MR_SOURCE_BRANCH=$(echo "$MR" | jq -r '.source_branch')
    MR_AUTHOR=$(echo "$MR" | jq -r '.author.username')

    # --- Check description for @aida ---
    if echo "$MR_DESC" | grep -qi '@aida'; then
      if ! echo "$MR_AUTHOR" | grep -q '^project_.*_bot'; then
        # Check if we already reacted with eyes emoji on the MR itself
        MR_REACTIONS=$(curl --silent --fail \
          --header "PRIVATE-TOKEN: ${GITLAB_TOKEN_AIDA}" \
          "${API_URL}/merge_requests/${MR_IID}/award_emoji")

        if ! echo "$MR_REACTIONS" | jq -e '.[] | select(.name == "eyes")' >/dev/null 2>&1; then
          COMMAND=$(echo "$MR_DESC" | grep -oi '@aida[[:space:]]\+[a-z]\+' | head -1 | awk '{print tolower($2)}')
          COMMAND=${COMMAND:-request}

          echo "Found @aida in description of MR !${MR_IID} (command: $COMMAND)"

          # Mark as seen with eyes reaction on the MR
          curl --silent --fail \
            --header "PRIVATE-TOKEN: ${GITLAB_TOKEN_AIDA}" \
            --request POST \
            "${API_URL}/merge_requests/${MR_IID}/award_emoji" \
            --data "name=eyes" >/dev/null 2>&1 || true

          # Trigger worker pipeline
          curl --silent --fail \
            --header "PRIVATE-TOKEN: ${GITLAB_TOKEN_AIDA}" \
            --header "Content-Type: application/json" \
            --request POST \
            "${API_URL}/pipeline" \
            --data "$(jq -n \
              --arg ref "main" \
              --arg mr_iid "$MR_IID" \
              --arg mr_title "$MR_TITLE" \
              --arg mr_desc "$MR_DESC" \
              --arg mr_branch "$MR_SOURCE_BRANCH" \
              --arg cmd "$COMMAND" \
              --arg body "$MR_DESC" \
              '{
                ref: $ref,
                variables: [
                  {key: "AIDA_SOURCE_TYPE", value: "mr"},
                  {key: "MR_IID", value: $mr_iid},
                  {key: "MR_TITLE", value: $mr_title},
                  {key: "MR_DESCRIPTION", value: $mr_desc},
                  {key: "MR_SOURCE_BRANCH", value: $mr_branch},
                  {key: "AIDA_COMMAND", value: $cmd},
                  {key: "AIDA_COMMENT_BODY", value: $body},
                  {key: "AIDA_COMMENT_ID", value: ""}
                ]
              }'
            )"

          echo "Pipeline triggered for MR !${MR_IID} description (command: $COMMAND)"
        fi
      fi
    fi

    # Get recent notes (comments) on this MR
    NOTES=$(curl --silent --fail \
      --header "PRIVATE-TOKEN: ${GITLAB_TOKEN_AIDA}" \
      "${API_URL}/merge_requests/${MR_IID}/notes?sort=desc&per_page=20")

    [ "$(echo "$NOTES" | jq 'length')" -eq 0 ] && continue

    echo "$NOTES" | jq -c '.[]' | while read -r NOTE; do
      NOTE_ID=$(echo "$NOTE" | jq -r '.id')
      BODY=$(echo "$NOTE" | jq -r '.body')
      AUTHOR=$(echo "$NOTE" | jq -r '.author.username')

      # Skip bot comments
      echo "$AUTHOR" | grep -q '^project_.*_bot' && continue

      # Skip if no @aida mention
      echo "$BODY" | grep -qi '@aida' || continue

      # Check if we already reacted with 👀 (eyes emoji)
      REACTIONS=$(curl --silent --fail \
        --header "PRIVATE-TOKEN: ${GITLAB_TOKEN_AIDA}" \
        "${API_URL}/merge_requests/${MR_IID}/notes/${NOTE_ID}/award_emoji")

      if echo "$REACTIONS" | jq -e '.[] | select(.name == "eyes")' >/dev/null 2>&1; then
        continue  # Already processed
      fi

      # Parse command
      COMMAND=$(echo "$BODY" | grep -oi '@aida[[:space:]]\+[a-z]\+' | head -1 | awk '{print tolower($2)}')
      COMMAND=${COMMAND:-request}

      echo "Found @aida command: '$COMMAND' in MR !${MR_IID} note ${NOTE_ID}"

      # Mark as seen with 👀 reaction
      curl --silent --fail \
        --header "PRIVATE-TOKEN: ${GITLAB_TOKEN_AIDA}" \
        --request POST \
        "${API_URL}/merge_requests/${MR_IID}/notes/${NOTE_ID}/award_emoji" \
        --data "name=eyes" >/dev/null 2>&1 || true

      # Trigger worker pipeline
      curl --silent --fail \
        --header "PRIVATE-TOKEN: ${GITLAB_TOKEN_AIDA}" \
        --header "Content-Type: application/json" \
        --request POST \
        "${API_URL}/pipeline" \
        --data "$(jq -n \
          --arg ref "main" \
          --arg mr_iid "$MR_IID" \
          --arg mr_title "$MR_TITLE" \
          --arg mr_desc "$MR_DESC" \
          --arg mr_branch "$MR_SOURCE_BRANCH" \
          --arg cmd "$COMMAND" \
          --arg body "$BODY" \
          --arg note_id "$NOTE_ID" \
          '{
            ref: $ref,
            variables: [
              {key: "AIDA_SOURCE_TYPE", value: "mr"},
              {key: "MR_IID", value: $mr_iid},
              {key: "MR_TITLE", value: $mr_title},
              {key: "MR_DESCRIPTION", value: $mr_desc},
              {key: "MR_SOURCE_BRANCH", value: $mr_branch},
              {key: "AIDA_COMMAND", value: $cmd},
              {key: "AIDA_COMMENT_BODY", value: $body},
              {key: "AIDA_COMMENT_ID", value: $note_id}
            ]
          }'
        )"

      echo "Pipeline triggered for MR !${MR_IID} (command: $COMMAND)"
    done
  done
fi

echo "Dispatch complete."
