#!/usr/bin/env bash
# AI-powered tmux window renaming based on all pane context
# Uses an OpenAI-compatible chat completions API (OpenRouter or a local vLLM
# endpoint) to analyze running processes and pane content.
# Requires: jq, curl, and a reachable API endpoint (see configuration below).
#
# For a pane running Claude Code (`claude`), the visible TUI is only a sliver
# of the session, so instead of capturing the screen we read that session's
# transcript (under ~/.claude/projects/<encoded-cwd>/) and summarize it from its
# AI title, first user message, and most recent turns. Several sessions can
# share one project dir, so we don't guess by mtime — we look THIS pane up in a
# pane->transcript map that an external producer must populate.
#
# TRANSCRIPT MAP (optional producer, graceful fallback): to name a Claude pane
# from its session transcript rather than the visible screen, something must
# record each Claude session's transcript path, keyed by tmux pane, as
#     /tmp/claude-tmux-panes-<uid>/<pane>   (one line: the transcript path)
# where <uid> is `id -u` and <pane> is the tmux pane id with every
# non-alphanumeric char mapped to '_' (e.g. %73 -> _73). That producer is a
# Claude Code SessionStart hook; it is NOT shipped in this repo — it lives as
# tmux-map-claude-session.sh in the claude-config repo, wired into that repo's
# settings.json. Without it, Claude panes (like all non-Claude panes) fall back
# to visible on-screen capture — naming still works, just less precisely when
# concurrent sessions share one cwd.
#
# Configuration (environment variables):
#   TMUX_RENAME_API_URL  Chat completions endpoint.
#                        Default: https://openrouter.ai/api/v1/chat/completions
#                        For vLLM, e.g. http://localhost:8000/v1/chat/completions
#   TMUX_RENAME_API_KEY  API key. Falls back to OPENROUTER_API_KEY. Optional for
#                        vLLM endpoints that don't require auth.
#   TMUX_RENAME_MODEL    Model name. Default: anthropic/claude-haiku-4.5 (OpenRouter).
#                        For vLLM, set to the served model name.
#
# Usage: tmux-window-rename-ai.sh [--dry-run] [-t <window>] [-m <model>]
#   -t         the window to name (default: the current one)
#   -m         the model, overriding TMUX_RENAME_MODEL
#   --dry-run  print the model's reply and the chosen name; rename nothing
#
# WARNING: This script sends pane content to the configured LLM API — visible
# on-screen text for ordinary panes, and session-transcript excerpts (title,
# first message, recent turns) for Claude Code panes. Do not use it if your
# session may contain sensitive information (API keys, passwords, tokens, etc.),
# and prefer a self-hosted endpoint when the transcript is confidential.
set -euo pipefail

DRY_RUN=false
target=""
while (( $# )); do
    case "$1" in
        --dry-run) DRY_RUN=true; shift ;;
        -t) target="${2:?-t needs a window}"; shift 2 ;;
        -m) TMUX_RENAME_MODEL="${2:?-m needs a model}"; shift 2 ;;
        *) echo "usage: tmux-window-rename-ai.sh [--dry-run] [-t <window>] [-m <model>]" >&2; exit 2 ;;
    esac
done
# Resolve to an @id: the other-windows list is filtered by it.
WINDOW_ID=$(tmux display-message ${target:+-t "$target"} -p '#{window_id}')
# A missing -t window yields an empty id with exit 0, and an empty -t later
# means "the focused window": refuse rather than name the wrong one.
[[ -n "$WINDOW_ID" ]] || { echo "tmux-window-rename-ai.sh: no such window: $target" >&2; exit 2; }
API_URL="${TMUX_RENAME_API_URL:-https://openrouter.ai/api/v1/chat/completions}"
API_KEY="${TMUX_RENAME_API_KEY:-${OPENROUTER_API_KEY:-}}"
# Not gemini-2.5-flash: it ignores the no-org-or-repo-names rule.
MODEL="${TMUX_RENAME_MODEL:-anthropic/claude-haiku-4.5}"
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
          ($turns | map(select(.role == "user")) | (.[0].text // "")) as $first
          # A forked session opens with launcher boilerplate before the
          # handoff doc; start the excerpt at the doc'"'"'s first heading.
          | ($first | (if startswith("# ") then 0 else (index("\n# ") // -1) + 1 end)) as $at
          | ($first[$at:]) as $goal
          | ($goal | if startswith("# ") then (split("\n")[0] | ltrimstr("# ")) else "" end) as $heading
          | "Session title: \($title)\n"
            + (if $heading != "" then "Task heading: \($heading)\n" else "" end)
            + "\nOverall goal (first user message):\n"
            + $goal[0:800]
            + "\n\nRecent conversation (most recent last):\n"
            + ( $turns[-8:]
                | map((if .role == "user" then "User" else "Assistant" end)
                      + ": " + (.text[0:400] | gsub("\n"; " ")))
                | join("\n") )
        end
    ' "$file" 2>/dev/null || true
}

# Animate the window name while the model thinks. Frames are an array, not a
# string: run-shell may give us the C locale, where substrings cut bytes.
spin() { # spin <name>
    local frames=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏) i=0
    while :; do
        tmux rename-window -t "$WINDOW_ID" "${frames[i++ % ${#frames[@]}]} $1"
        sleep 0.15
    done
}

# Runs on every exit, so an error mid-way still puts a name back.
SPIN_PID="" FINAL=""
stop_spin() {
    [[ -n "$SPIN_PID" ]] || return 0
    kill "$SPIN_PID" 2>/dev/null || true
    wait "$SPIN_PID" 2>/dev/null || true
    SPIN_PID=""
    tmux rename-window -t "$WINDOW_ID" "$FINAL"
}

main() {
    if ! $DRY_RUN; then
        FINAL=$(tmux display-message -t "$WINDOW_ID" -p '#{window_name}')
        trap stop_spin EXIT
        spin "$FINAL" &
        SPIN_PID=$!
    fi

    local context=""
    local pane_num=0
    local map_root
    map_root="/tmp/claude-tmux-panes-$(id -u)"

    for pane_id in $(tmux list-panes -t "$WINDOW_ID" -F '#{pane_id}'); do
        pane_num=$((pane_num + 1))
        local cmd path enc proj key mapped transcript sess content visible
        cmd=$(tmux display-message -t "$pane_id" -p '#{pane_current_command}')
        path=$(tmux display-message -t "$pane_id" -p '#{pane_current_path}')

        # A pane running Claude Code is summarized from its session transcript
        # rather than the visible TUI tail. The SessionStart hook recorded this
        # pane's transcript path keyed by pane id; trust it only if the file
        # still exists and lives under this pane's own project dir (Claude Code
        # encodes the launch cwd by mapping every non-alphanumeric char to '-'),
        # which rejects a stale mapping left by a since-closed pane.
        if [[ "$cmd" == "claude" ]]; then
            enc=$(printf '%s' "$path" | sed 's/[^a-zA-Z0-9]/-/g')
            proj="$HOME/.claude/projects/$enc"
            key=$(printf '%s' "$pane_id" | tr -c 'a-zA-Z0-9' '_')
            transcript=""
            if [[ -f "$map_root/$key" ]]; then
                mapped=$(<"$map_root/$key")
                if [[ -n "$mapped" && -f "$mapped" && "$mapped" == "$proj/"* ]]; then
                    transcript="$mapped"
                fi
            fi
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

        # Fallback: non-Claude pane, or no session mapping (hook not installed,
        # or a session that predates it). capture-pane returns only the visible
        # screen, so send all non-blank lines (most recent last), capped to
        # avoid flooding very tall panes.
        content=$(tmux capture-pane -p -t "$pane_id" 2>/dev/null || true)
        visible=$(printf '%s\n' "$content" | grep -v '^[[:space:]]*$' | tail -50 || true)
        context+="=== Pane ${pane_num} ===
Command: ${cmd}
Directory: ${path}
--- Visible output (most recent last) ---
${visible}

"
    done

    local others
    others=$(tmux list-windows -a -F '#{window_id} #{window_name}' \
        | awk -v me="$WINDOW_ID" '$1 != me { sub(/^[^ ]+ /, ""); print }' \
        | sort -u | paste -sd' ' -)
    local prompt
    prompt="You are naming a tmux window so the user can find it at a glance among their other windows. The pane context is at the end.

First work out what this window is FOR: the job being done, and what it is being done to. Then name it after that job.

A good name is the word the user would say in \"switch to the ___ window\". It names the job or its specific object, never the place the job happens: the user's org, cluster, repo or project name is shared by many of their windows and tells them nothing.

The user's other windows are named: ${others}
Use the same terse style, and pick something that tells this window apart from those.

Reply in exactly this format, nothing else:
task: <one short sentence: what is being done, to what>
<name>
<name>
<name>

Rules for the names:
- Never put the name of a cluster, company, org, host group or repo in a name, not even abbreviated: the user works inside those all day, so they never tell windows apart. Name what is being done or the specific thing it is done to.
- Best first. Lowercase. Aim for 8 characters or fewer; go longer only when a shorter name would be unclear. One word is best; two short hyphenated words at most. Abbreviate freely (wg, k8s, mig, cfg).
- Drop file extensions and filler: a file named 'tmux-window-rename-ai.sh' becomes 'win-name', never 'tmux-window-rename-ai-sh'.
- Ignore incidental noise: command flags, bare numbers and token counts (e.g. '32'), timestamps, shell prompts, and this renamer's own curl/jq/tmux commands are NEVER the subject.
- For a pane marked '(Claude Code session)', name the task that session is working on: lean on its task heading and most recent turns, and prefer the current focus over the opening request when they differ.
- If a pane is just a TUI or an idle shell with no task, name it after that tool (htop, less, psql).

Examples:
task: debugging why the WireGuard tunnel to the NAS keeps dropping
wg-drop
wg-nas
vpn

task: reviewing a pull request that changes the retry backoff
retry-pr
backoff
pr-retry

<panes>
${context}
</panes>"

    local body
    body=$(jq -n --arg model "$MODEL" --arg content "$prompt" \
        '{model: $model, max_tokens: 96, temperature: 0.3,
          messages: [{role: "user", content: $content}]}')

    # On OpenRouter, give the model a bounded reasoning budget: without it,
    # it names the window after the most frequent word in the context (the
    # cluster or org) instead of the job. max_tokens must cover reasoning
    # plus the reply. vLLM rejects unknown top-level fields, so there thinking
    # is switched off via chat_template_kwargs, which non-reasoning chat
    # templates ignore harmlessly.
    if [[ "$API_URL" == *openrouter.ai* ]]; then
        body=$(printf '%s' "$body" | jq '. + {max_tokens: 1200, reasoning: {max_tokens: 1024}}')
    else
        body=$(printf '%s' "$body" | jq '. + {chat_template_kwargs: {enable_thinking: false}}')
    fi

    # The key and the body stay out of curl's argv, which any local user can
    # read in ps: the key goes in as a config file on a pipe (printf is a
    # builtin, so it never execs), the body on stdin. The <(...) must sit on
    # the curl line itself: one stored in an array is closed before curl runs.
    local headers='header = "Content-Type: application/json"'
    if [[ -n "$API_KEY" ]]; then
        headers+=$'\n'"header = \"Authorization: Bearer ${API_KEY}\""
    fi

    local response
    response=$(curl -s --max-time 30 "$API_URL" -K <(printf '%s\n' "$headers") \
        --data-binary @- <<<"$body")

    local raw name="" first="" line slug
    raw=$(echo "$response" | jq -r '.choices[0].message.content // empty')
    if [[ -z "$raw" ]]; then
        echo "$(date -Iseconds) No content in response: ${response}" >> "$LOG"
        return 1
    fi
    echo "$(date -Iseconds) $WINDOW_ID reply: $(printf '%s' "$raw" | paste -sd'|' -)"
    # Take the model's first name. The 16-character cap is not a style limit
    # (the prompt sets that); it skips preamble ("Here are three names:")
    # that slugifies into one long word.
    local max=16
    while IFS= read -r line; do
        [[ "$line" != [Tt]ask:* ]] || continue
        slug=$(printf '%s' "$line" | sed -E 's/^[[:space:]]*[0-9]+[.)]//' \
            | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-' | sed 's/^-*//;s/-*$//')
        [[ -n "$slug" ]] || continue
        [[ -n "$first" ]] || first="$slug"
        if (( ${#slug} <= max )); then
            name="$slug"
            break
        fi
    done <<<"$raw"
    # None under the cap: cut the first one, at a hyphen when there is one.
    if [[ -z "$name" && -n "$first" ]]; then
        name=${first:0:max}
        [[ "$name" != *-* ]] || name=${name%-*}
    fi

    if [[ -n "$name" ]] && $DRY_RUN; then
        printf '%s\n-> %s\n' "$raw" "$name"
    elif [[ -n "$name" ]]; then
        FINAL="$name"
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

if $DRY_RUN; then
    main
else
    main >> "$LOG" 2>&1 &
    disown
fi
