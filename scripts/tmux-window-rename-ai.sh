#!/usr/bin/env bash
# AI-powered tmux window renaming based on all pane context
# Uses OpenRouter API to analyze running processes and pane content
# Requires: OPENROUTER_API_KEY, jq, curl
#
# WARNING: This script sends visible pane content (head/tail of each pane)
# to an external LLM API. Do not use it if your tmux session may contain
# sensitive information (API keys, passwords, tokens, etc.).
set -euo pipefail

WINDOW_ID=$(tmux display-message -p '#{window_id}')
MODEL="${TMUX_RENAME_MODEL:-google/gemini-2.5-flash-lite}"
LOG="/tmp/tmux-window-rename-ai.log"

main() {
    local context=""
    local pane_num=0

    for pane_id in $(tmux list-panes -t "$WINDOW_ID" -F '#{pane_id}'); do
        pane_num=$((pane_num + 1))
        local cmd path content non_blank head_lines tail_lines
        cmd=$(tmux display-message -t "$pane_id" -p '#{pane_current_command}')
        path=$(tmux display-message -t "$pane_id" -p '#{pane_current_path}')
        content=$(tmux capture-pane -p -t "$pane_id" 2>/dev/null || true)
        non_blank=$(echo "$content" | grep -v '^[[:space:]]*$' || true)
        head_lines=$(echo "$non_blank" | head -15)
        tail_lines=$(echo "$non_blank" | tail -15)

        context+="=== Pane ${pane_num} ===
Command: ${cmd}
Directory: ${path}
--- Top of visible output ---
${head_lines}
--- Bottom of visible output ---
${tail_lines}

"
    done

    local prompt
    prompt="Based on the following tmux pane context, generate a SHORT (1-2 word) descriptive name for this tmux window. The name should be a lowercase, hyphen-separated slug that describes what the user is DOING, not where they are. Focus on the task/activity visible in the pane content (e.g. what's being edited, debugged, built, reviewed), not the repo name or directory. Examples: auth-fix, deploy, api-debug, log-review, db-migrate, tmux-rename, htop.

Respond with ONLY the window name slug, nothing else. No quotes, no explanation.

${context}"

    local json_prompt
    json_prompt=$(printf '%s' "$prompt" | jq -Rs .)

    local response
    response=$(curl -s --max-time 30 https://openrouter.ai/api/v1/chat/completions \
        -H "Authorization: Bearer $OPENROUTER_API_KEY" \
        -H "Content-Type: application/json" \
        -d "{
            \"model\": \"${MODEL}\",
            \"max_tokens\": 20,
            \"messages\": [{\"role\": \"user\", \"content\": ${json_prompt}}]
        }")

    local raw_name name
    raw_name=$(echo "$response" | jq -r '.choices[0].message.content // empty')
    if [[ -z "$raw_name" ]]; then
        echo "$(date -Iseconds) No content in response: ${response}" >> "$LOG"
        return 1
    fi
    name=$(printf '%s' "$raw_name" \
        | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-' | sed 's/^-//;s/-$//' | head -c 30)

    if [[ -n "$name" ]]; then
        tmux rename-window -t "$WINDOW_ID" "$name"
    else
        echo "$(date -Iseconds) Failed to extract name from response: ${response}" >> "$LOG"
    fi
}

if [[ -z "${OPENROUTER_API_KEY:-}" ]]; then
    echo "OPENROUTER_API_KEY not set" >&2
    exit 1
fi

if ! command -v jq &>/dev/null; then
    echo "jq is required" >&2
    exit 1
fi

main >> "$LOG" 2>&1 &
disown
