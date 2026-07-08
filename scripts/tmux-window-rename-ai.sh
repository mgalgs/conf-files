#!/usr/bin/env bash
# AI-powered tmux window renaming based on all pane context
# Uses an OpenAI-compatible chat completions API (OpenRouter or a local vLLM
# endpoint) to analyze running processes and pane content.
# Requires: jq, curl, and a reachable API endpoint (see configuration below).
#
# For a pane running Claude Code (`claude`), the visible TUI is only a sliver
# of the session, so instead of capturing the screen we read that session's
# transcript (~/.claude/projects/<encoded-cwd>/<newest>.jsonl) and summarize it
# from its AI title, first user message, and most recent turns. All other panes
# still use their visible on-screen output.
#
# Configuration (environment variables):
#   TMUX_RENAME_API_URL  Chat completions endpoint.
#                        Default: https://openrouter.ai/api/v1/chat/completions
#                        For vLLM, e.g. http://localhost:8000/v1/chat/completions
#   TMUX_RENAME_API_KEY  API key. Falls back to OPENROUTER_API_KEY. Optional for
#                        vLLM endpoints that don't require auth.
#   TMUX_RENAME_MODEL    Model name. Default: google/gemini-2.5-flash (OpenRouter).
#                        For vLLM, set to the served model name.
#
# WARNING: This script sends pane content to the configured LLM API — visible
# on-screen text for ordinary panes, and session-transcript excerpts (title,
# first message, recent turns) for Claude Code panes. Do not use it if your
# session may contain sensitive information (API keys, passwords, tokens, etc.),
# and prefer a self-hosted endpoint when the transcript is confidential.
set -euo pipefail

WINDOW_ID=$(tmux display-message -p '#{window_id}')
API_URL="${TMUX_RENAME_API_URL:-https://openrouter.ai/api/v1/chat/completions}"
API_KEY="${TMUX_RENAME_API_KEY:-${OPENROUTER_API_KEY:-}}"
MODEL="${TMUX_RENAME_MODEL:-google/gemini-2.5-flash}"
LOG="/tmp/tmux-window-rename-ai.log"

# Summarize a Claude Code session transcript into a compact context block:
# its AI title (the session's overall subject), the first user message (the
# stated goal), and the last few conversation turns (the current focus). Pure
# jq over the JSONL — no LLM, no network. Reads lines defensively with
# `fromjson?` so a partial final line (the session may be mid-write) is skipped
# rather than aborting. Prints nothing if the transcript has no usable turns.
transcript_context() {
    local file="$1"
    jq -Rrn '
      [inputs | fromjson?] as $recs
      | ($recs | map(select(.type == "ai-title" and ((.aiTitle // "") != "")))
              | last | .aiTitle // "") as $title
      | ( $recs
          | map(select((.type == "user" or .type == "assistant")
                       and ((.isSidechain // false) | not)))
          | map(
              (.message.role // .type) as $role
              | (.message.content) as $c
              | if ($c | type) == "string" then {role: $role, text: $c}
                elif ($c | type) == "array" then
                  {role: $role, text: ($c | map(select(.type == "text") | .text // "") | join("\n"))}
                else {role: $role, text: ""} end
            )
          | map(select((.text // "") | gsub("^\\s+|\\s+$"; "") | length > 0))
        ) as $turns
      | if ($turns | length) == 0 then ""
        else
          ($turns | map(select(.role == "user")) | (.[0].text // "")) as $goal
          | "Session title: \($title)\n\nOverall goal (first user message):\n"
            + $goal[0:600]
            + "\n\nRecent conversation (most recent last):\n"
            + ( $turns[-8:]
                | map((if .role == "user" then "User" else "Assistant" end)
                      + ": " + (.text[0:400] | gsub("\n"; " ")))
                | join("\n") )
        end
    ' "$file" 2>/dev/null || true
}

main() {
    local context=""
    local pane_num=0

    for pane_id in $(tmux list-panes -t "$WINDOW_ID" -F '#{pane_id}'); do
        pane_num=$((pane_num + 1))
        local cmd path enc proj transcript sess content visible
        cmd=$(tmux display-message -t "$pane_id" -p '#{pane_current_command}')
        path=$(tmux display-message -t "$pane_id" -p '#{pane_current_path}')

        # A pane running Claude Code is summarized from its session transcript
        # rather than the visible TUI tail. Claude Code encodes the launch cwd
        # by replacing every non-alphanumeric char with '-'; the newest .jsonl
        # in that project dir is the live session.
        if [[ "$cmd" == "claude" ]]; then
            enc=$(printf '%s' "$path" | sed 's/[^a-zA-Z0-9]/-/g')
            proj="$HOME/.claude/projects/$enc"
            transcript=$(find "$proj" -maxdepth 1 -type f -name '*.jsonl' \
                -printf '%T@\t%p\n' 2>/dev/null | sort -rn | head -1 | cut -f2-)
            if [[ -n "$transcript" ]]; then
                sess=$(transcript_context "$transcript")
                if [[ -n "${sess//[[:space:]]/}" ]]; then
                    context+="=== Pane ${pane_num} (Claude Code session) ===
Directory: ${path}
${sess}

"
                    continue
                fi
            fi
        fi

        # Fallback: non-Claude pane, or transcript unavailable. capture-pane
        # returns only the visible screen, so send all non-blank lines (most
        # recent last), capped to avoid flooding very tall panes.
        content=$(tmux capture-pane -p -t "$pane_id" 2>/dev/null || true)
        visible=$(echo "$content" | grep -v '^[[:space:]]*$' | tail -50 || true)
        context+="=== Pane ${pane_num} ===
Command: ${cmd}
Directory: ${path}
--- Visible output (most recent last) ---
${visible}

"
    done

    local prompt
    prompt="Name this tmux window from the pane context at the end.

Name the concrete thing being worked on right now: the actual file, feature, service, error, command, or topic visible on screen. Be specific, not categorical — name the instance, not the genre.

Hard rules (follow exactly):
- Output ONLY the slug. No quotes, no prose, no explanation, no trailing punctuation.
- Format: lowercase, hyphen-separated, 2 to 4 words, at most 28 characters. Prefer fewer words.
- Drop file extensions: a file named 'tmux-window-rename-ai.sh' becomes 'tmux-rename', never 'tmux-window-rename-ai-sh'.
- Ignore incidental noise: command flags, bare numbers and token counts (e.g. '32'), timestamps, shell prompts, and this renamer's own curl/jq/tmux commands are NEVER the subject.
- Anchor to the most distinctive noun on screen (a filename without its extension, a function, a service, an error, a host), then add what is being done to it, subject first.
- For a pane marked '(Claude Code session)', name the task that session is working on — lean on its session title and most recent turns, and prefer the current focus over the opening request when they differ.
- If a pane is just a TUI or an idle shell with no task, name it after that tool (htop, less, psql).

Examples — bad (too generic, or copied literally) then good (specific):
  api-debug          -> openrouter-timeout
  log-review         -> wireguard-tunnel-logs
  db-migrate         -> orders-migration-rebase
  update-metrics-py  -> metrics-exporter-fix
  deploy             -> apps-vm-deploy

Respond with ONLY the slug.

<panes>
${context}
</panes>"

    local body
    body=$(jq -n --arg model "$MODEL" --arg content "$prompt" \
        '{model: $model, max_tokens: 32, temperature: 0.3,
          messages: [{role: "user", content: $content}]}')

    # Suppress chain-of-thought so the whole token budget goes to the slug
    # (a reasoning model like Qwen3 otherwise spends all 32 tokens thinking and
    # returns nothing usable). OpenRouter uses a "reasoning" field; vLLM rejects
    # unknown top-level fields but honors chat_template_kwargs.enable_thinking,
    # which non-reasoning chat templates ignore harmlessly.
    if [[ "$API_URL" == *openrouter.ai* ]]; then
        body=$(printf '%s' "$body" | jq '. + {reasoning: {enabled: false}}')
    else
        body=$(printf '%s' "$body" | jq '. + {chat_template_kwargs: {enable_thinking: false}}')
    fi

    local -a curl_args=(-s --max-time 30 "$API_URL" -H "Content-Type: application/json")
    if [[ -n "$API_KEY" ]]; then
        curl_args+=(-H "Authorization: Bearer $API_KEY")
    fi

    local response
    response=$(curl "${curl_args[@]}" -d "$body")

    local raw_name name
    raw_name=$(echo "$response" | jq -r '.choices[0].message.content // empty')
    if [[ -z "$raw_name" ]]; then
        echo "$(date -Iseconds) No content in response: ${response}" >> "$LOG"
        return 1
    fi
    # Small models sometimes prepend prose or emit the slug on its own line;
    # keep only the last non-blank line before slugifying so preamble like
    # "Here's the name:" doesn't get mashed into the slug.
    raw_name=$(printf '%s' "$raw_name" | grep -v '^[[:space:]]*$' | tail -1)
    name=$(printf '%s' "$raw_name" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-')
    # Trim to 28 chars at a hyphen boundary so we never cut a word mid-token.
    if (( ${#name} > 28 )); then
        name=${name:0:28}
        name=${name%-*}
    fi
    name=$(printf '%s' "$name" | sed 's/^-*//;s/-*$//')

    if [[ -n "$name" ]]; then
        tmux rename-window -t "$WINDOW_ID" "$name"
    else
        echo "$(date -Iseconds) Failed to extract name from response: ${response}" >> "$LOG"
    fi
}

if [[ "$API_URL" == *openrouter.ai* && -z "$API_KEY" ]]; then
    echo "OPENROUTER_API_KEY (or TMUX_RENAME_API_KEY) not set" >&2
    exit 1
fi

if ! command -v jq &>/dev/null; then
    echo "jq is required" >&2
    exit 1
fi

main >> "$LOG" 2>&1 &
disown
