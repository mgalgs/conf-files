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
MODEL="${TMUX_RENAME_MODEL:-google/gemini-2.5-flash}"
LOG="/tmp/tmux-window-rename-ai.log"

main() {
    local context=""
    local pane_num=0

    for pane_id in $(tmux list-panes -t "$WINDOW_ID" -F '#{pane_id}'); do
        pane_num=$((pane_num + 1))
        local cmd path content visible
        cmd=$(tmux display-message -t "$pane_id" -p '#{pane_current_command}')
        path=$(tmux display-message -t "$pane_id" -p '#{pane_current_path}')
        content=$(tmux capture-pane -p -t "$pane_id" 2>/dev/null || true)
        # capture-pane returns only the visible screen, so send all non-blank
        # lines (most recent last), capped to avoid flooding very tall panes.
        visible=$(echo "$content" | grep -v '^[[:space:]]*$' | tail -50 || true)

        context+="=== Pane ${pane_num} ===
Command: ${cmd}
Directory: ${path}
--- Visible output (most recent last) ---
${visible}

"
    done

    local prompt
    prompt="Generate a SPECIFIC, descriptive name for this tmux window based on the pane context below.

The name must identify the concrete thing being worked on RIGHT NOW — the actual file, feature, service, error, command, or topic visible in the panes. Be specific, not categorical: name the instance, not the genre of activity.

Rules:
- lowercase, hyphen-separated slug, 2-4 tokens, max ~28 chars
- Anchor the name to the most distinctive concrete noun on screen: a filename (drop the extension), a function or feature, a service, an error message, a host. Specific beats short.
- Combine the subject with the activity when both are clear (subject first): 'openrouter-timeout-fix', 'tmux-rename-prompt', 'wireguard-tunnel-logs', 'migrations-rebase'.
- Using the repo/dir/filename is GOOD when it's the distinctive signal — just don't stop at a bare cwd; say what is being done to it.
- If a pane is only a running TUI with no task context (htop, less, a plain shell), name it after that tool.

Bad (too generic) -> Good (specific):
  api-debug    -> openrouter-timeout
  log-review   -> wireguard-tunnel-logs
  db-migrate   -> orders-migration-rebase
  script-edit  -> tmux-rename-prompt
  deploy       -> apps-vm-deploy

Respond with ONLY the slug, nothing else. No quotes, no explanation.

${context}"

    local json_prompt
    json_prompt=$(printf '%s' "$prompt" | jq -Rs .)

    local response
    response=$(curl -s --max-time 30 https://openrouter.ai/api/v1/chat/completions \
        -H "Authorization: Bearer $OPENROUTER_API_KEY" \
        -H "Content-Type: application/json" \
        -d "{
            \"model\": \"${MODEL}\",
            \"max_tokens\": 32,
            \"reasoning\": {\"enabled\": false},
            \"messages\": [{\"role\": \"user\", \"content\": ${json_prompt}}]
        }")

    local raw_name name
    raw_name=$(echo "$response" | jq -r '.choices[0].message.content // empty')
    if [[ -z "$raw_name" ]]; then
        echo "$(date -Iseconds) No content in response: ${response}" >> "$LOG"
        return 1
    fi
    name=$(printf '%s' "$raw_name" \
        | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-' | head -c 30 | sed 's/^-//;s/-$//')

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
