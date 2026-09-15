#!/usr/bin/env bash
# Render Claude and Codex quota usage as tmux-colored sparkline glyphs.
#
# Companion to tmux-cpu-spark.sh, and deliberately identical to it in look:
# the same eight glyphs (▁▂▃▄▅▆▇█), the same heat ramps, the same index math
# (round(pct * 7 / 100), clamped). One glyph per quota window, with the two
# sources separated by a space:
#
#     [▅▄▂ ▇▁]
#      ^^^ ^^
#      |   codex:  5h, weekly
#      claude: 5h, weekly, weekly-scoped
#
# Glyph height is how full that window is, color is the heat ramp (green ->
# red). Grey (colour238) means the reading is too old to trust. A source that
# errored, or that reports no windows at all, renders a single dim "·" rather
# than disappearing -- a widget that vanishes looks identical to a healthy one
# at a glance.
#
# The number of windows is NOT fixed: Claude reports two or three depending on
# whether a model-scoped weekly bar is active, and Codex reports one or two.
# Whatever the document lists is what gets drawn, in document order.
#
# Usage: tmux-quota-spark.sh [scheme]
#   scheme: vivid (default) | muted | icefire
#
# status-interval is 1, so this runs once a second and must do no real work in
# band. It renders from a cached JSON document produced by `quotatop --json`;
# when that cache goes stale it fires a single background refresh and still
# renders the old contents immediately. quotatop is never run in the
# foreground: its Codex side walks and parses the whole retained session-log
# tree, which is fine once a minute and ruinous at 1 Hz.
#
# Environment:
#   TMUX_QUOTA_STATE            Render this document instead of the cache. The
#                               script then never refreshes and never writes,
#                               so it is safe to point at a checked-in fixture
#                               (see testdata/quota-sample.json). Note that the
#                               fixture's epoch stamps are fixed, so it greys
#                               out once it is older than the stale threshold,
#                               which is correct rather than a bug. To preview
#                               it in color, raise TMUX_QUOTA_STALE_SECONDS.
#   TMUX_QUOTA_REFRESH_SECONDS  How old the cache may get before a background
#                               refresh is fired (default 60).
#   TMUX_QUOTA_STALE_SECONDS    How old a reading may get before its glyphs go
#                               grey (default 1800). Codex has no server to
#                               ask and only records a limit when it happens to
#                               report one, so it legitimately goes hours or
#                               days stale; a confident-looking bar over a
#                               five-day-old number is actively misleading.
#
# Age comes from the document's absolute epoch stamps, so it stays correct no
# matter how long the document sat in the cache: observed_at_epoch is when the
# reading was taken, generated_at_epoch is when the document was built. A
# source is greyed on whichever is older, because a reading cannot be fresher
# than the document carrying it -- that second term is what catches a refresher
# that has silently stopped working. Both stamps are null when the time is
# unknown, which greys rather than passing for fresh, and a payload predating
# them falls back to observed_age_seconds plus the cache file's own age.
#
# A non-empty warning ("this reading is real but something about it is off")
# deliberately does NOT grey. Grey says "too old to trust", and it only carries
# that meaning while it stays rare: for as long as a warning fires on close to
# every scan, greying on it would pin a source grey permanently and drown out
# the staleness signal. One glyph per window leaves no room for a third state,
# so the channel goes to the condition that actually varies. Worth revisiting
# if warnings become rare, or if the field grows a severity.
set -euo pipefail

ticks=(▁ ▂ ▃ ▄ ▅ ▆ ▇ █)
grey=238
scheme="${1:-vivid}"

case "$scheme" in
    vivid)   ramp=(46 118 154 184 220 214 208 196) ;;
    muted)   ramp=(108 108 144 180 179 173 167 160) ;;
    icefire) ramp=(39 45 51 190 226 214 202 196) ;;
    *)       ramp=(46 118 154 184 220 214 208 196) ;;  # unknown -> vivid
esac

refresh_seconds="${TMUX_QUOTA_REFRESH_SECONDS:-60}"
stale_seconds="${TMUX_QUOTA_STALE_SECONDS:-1800}"
# A refresher that is hard-killed cannot clean up its own lock, so a lock this
# old is assumed abandoned rather than held.
lock_seconds=300

cache="${XDG_RUNTIME_DIR:-/tmp}/tmux-quota.${UID}.json"
override=0
state="$cache"
if [[ -n "${TMUX_QUOTA_STATE:-}" ]]; then
    override=1
    state="$TMUX_QUOTA_STATE"
fi

now="$EPOCHSECONDS"

mtime_of() {
    local m
    m="$(stat -c %Y "$1" 2>/dev/null)" || return 1
    printf '%s' "$m"
}

# PATH first, then the two places quotatop lives before claude-config's
# install.sh puts it on PATH.
resolve_quotatop() {
    local c
    if c="$(command -v quotatop 2>/dev/null)"; then
        printf '%s' "$c"
        return 0
    fi
    for c in "$HOME/src/quotatop/quotatop" "$HOME/.local/bin/quotatop"; do
        if [[ -x "$c" ]]; then
            printf '%s' "$c"
            return 0
        fi
    done
    return 1
}

# Fire at most one refresh at a time and never wait for it. mkdir is the mutex
# because it is atomic on every filesystem worth caring about; at 1 Hz a
# quotatop that hangs would otherwise spawn a process per second.
start_refresh() {
    local bin lock
    lock="${cache}.lock"

    if ! mkdir "$lock" 2>/dev/null; then
        local held
        held="$(mtime_of "$lock")" || return 0
        if (( now - held < lock_seconds )); then
            return 0
        fi
        rmdir "$lock" 2>/dev/null || return 0
        mkdir "$lock" 2>/dev/null || return 0
    fi

    # Stamped before the attempt rather than after it, so a quotatop that fails
    # every time -- or is not installed yet -- is retried on the refresh
    # interval instead of on every tick. It holds the epoch second as text so
    # the hot path can read it with a builtin instead of forking stat. The
    # cache's own mtime stays honest, which matters -- see age_offset.
    printf '%s\n' "$now" > "${cache}.attempt" 2>/dev/null || true

    # Resolved after the marker is stamped: when quotatop is missing this is
    # the only work a tick does, and it must not repeat every second.
    if ! bin="$(resolve_quotatop)"; then
        rmdir "$lock" 2>/dev/null || true
        return 0
    fi

    (
        trap 'rmdir "$lock" 2>/dev/null || true' EXIT
        local tmp runner=()
        tmp="${cache}.$$"
        command -v timeout >/dev/null 2>&1 && runner=(timeout 30)
        if "${runner[@]}" "$bin" --json > "$tmp" 2>/dev/null && [[ -s "$tmp" ]]; then
            mv -f "$tmp" "$cache" 2>/dev/null || rm -f "$tmp" 2>/dev/null || true
        else
            rm -f "$tmp" 2>/dev/null || true
        fi
    ) >/dev/null 2>&1 &
}

state_mtime=""
if [[ -s "$state" ]]; then
    state_mtime="$(mtime_of "$state")" || state_mtime=""
fi

# Only consulted for payloads that predate generated_at_epoch; the epoch stamps
# are absolute, so when they are present no correction is needed. -1 means
# "unknown", which is not the same as "fresh": an explicit TMUX_QUOTA_STATE is a
# static fixture rather than a live cache, so its file mtime says nothing about
# when the reading was taken.
doc_fallback_age=-1
if (( ! override )) && [[ -n "$state_mtime" ]]; then
    doc_fallback_age=$(( now - state_mtime ))
    (( doc_fallback_age < 0 )) && doc_fallback_age=0
fi

if (( ! override )); then
    due=1
    if [[ -n "$state_mtime" ]] && (( now - state_mtime < refresh_seconds )); then
        due=0
    elif [[ -r "${cache}.attempt" ]]; then
        attempt=0
        read -r attempt < "${cache}.attempt" || attempt=0
        [[ "$attempt" =~ ^[0-9]+$ ]] || attempt=0
        (( now - attempt < refresh_seconds )) && due=0
    fi
    (( due )) && start_refresh
fi

# Flatten the document and emit one line per source:
#
#     <id> <age_seconds> <error_flag> [<glyph_index> ...]
#
# This is a real (small) JSON walker rather than a line-oriented grep because
# nothing promises the document stays pretty-printed: quotatop may well emit it
# compact. It tracks a path like sources[0].windows[1].percent and reports the
# four fields the widget actually needs, so every other key in the schema --
# projections, labels, reset times -- costs nothing here.
read_state() {
    awk -v now="$2" -v doc_fallback="$3" '
    { doc = doc $0 "\n" }

    # Path of a value about to be placed in the container at depth d. Also
    # advances the array cursor, so array elements number themselves.
    function value_path(d) {
        if (d == 0) return ""
        if (ctype[d] == "a") {
            cidx[d]++
            return cpath[d] "[" cidx[d] "]"
        }
        if (cpath[d] == "") return ckey[d]
        return cpath[d] "." ckey[d]
    }

    # Nth bracketed subscript in a path, as a number.
    function nth_index(path, which,   tmp, cnt, got) {
        cnt = 0
        tmp = path
        while (match(tmp, /\[[0-9]+\]/)) {
            cnt++
            got = substr(tmp, RSTART + 1, RLENGTH - 2)
            if (cnt == which) return got + 0
            tmp = substr(tmp, RSTART + RLENGTH)
        }
        return -1
    }

    function scan_string(s, p, n,   out, ch) {
        p++
        out = ""
        while (p <= n) {
            ch = substr(s, p, 1)
            if (ch == "\\") {
                p++
                ch = substr(s, p, 1)
                if (ch == "n") out = out "\n"
                else if (ch == "t") out = out "\t"
                else if (ch == "u") { out = out "?"; p += 4 }
                else out = out ch
                p++
                continue
            }
            if (ch == "\"") { p++; break }
            out = out ch
            p++
        }
        STR = out
        return p
    }

    function note_source(si) {
        if (si >= nsrc) nsrc = si + 1
    }

    function emit(path, val,   si, wi, pct, gi) {
        if (path ~ /^sources\[[0-9]+\]\.source$/) {
            si = nth_index(path, 1)
            sid[si] = val
            note_source(si)
        } else if (path ~ /^sources\[[0-9]+\]\.observed_age_seconds$/) {
            si = nth_index(path, 1)
            # null means the observation time is unknown, which must read as
            # unknown rather than as zero seconds old.
            if (val != "null" && val != "") {
                sage[si] = int(val + 0)
                shas_age[si] = 1
            }
            note_source(si)
        } else if (path ~ /^sources\[[0-9]+\]\.observed_at_epoch$/) {
            si = nth_index(path, 1)
            if (val != "null" && val != "") {
                sobs[si] = int(val + 0)
                shas_obs[si] = 1
            }
            note_source(si)
        } else if (path == "generated_at_epoch") {
            if (val != "null" && val != "") {
                gen_epoch = int(val + 0)
                has_gen = 1
            }
        } else if (path ~ /^sources\[[0-9]+\]\.error$/) {
            si = nth_index(path, 1)
            serr[si] = (val != "" && val != "null") ? 1 : 0
            note_source(si)
        } else if (path ~ /^sources\[[0-9]+\]\.windows\[[0-9]+\]\.percent$/) {
            si = nth_index(path, 1)
            wi = nth_index(path, 2)
            pct = val + 0
            if (pct < 0) pct = 0
            if (pct > 100) pct = 100
            gi = int(pct * 7 / 100 + 0.5)
            if (gi < 0) gi = 0
            if (gi > 7) gi = 7
            glyph[si, wi] = gi
            if (wi >= wcount[si]) wcount[si] = wi + 1
            note_source(si)
        }
    }

    END {
        n = length(doc)
        i = 1
        depth = 0
        while (i <= n) {
            c = substr(doc, i, 1)
            if (c == " " || c == "\t" || c == "\n" || c == "\r") { i++; continue }
            if (c == "{" || c == "[") {
                np = value_path(depth)
                depth++
                ctype[depth] = (c == "{") ? "o" : "a"
                cpath[depth] = np
                cidx[depth] = -1
                ckey[depth] = ""
                i++
                continue
            }
            if (c == "}" || c == "]") { if (depth > 0) depth--; i++; continue }
            if (c == "," || c == ":") { i++; continue }
            if (c == "\"") {
                i = scan_string(doc, i, n)
                s = STR
                # A string is a key exactly when the next thing is a colon;
                # a value string can never be followed by one.
                j = i
                while (j <= n && substr(doc, j, 1) ~ /^[ \t\n\r]$/) j++
                if (depth > 0 && ctype[depth] == "o" && substr(doc, j, 1) == ":")
                    ckey[depth] = s
                else
                    emit(value_path(depth), s)
                continue
            }
            # number, true, false, null
            j = i
            while (j <= n && index(",}] \t\n\r", substr(doc, j, 1)) == 0) j++
            emit(value_path(depth), substr(doc, i, j - i))
            i = j
        }

        doc_age = (has_gen ? now - gen_epoch : doc_fallback)
        if (has_gen && doc_age < 0) doc_age = 0

        for (s = 0; s < nsrc; s++) {
            # Absolute stamp first: it already accounts for time spent in the
            # cache. Relative age only as a fallback, and then it does need the
            # document age added back.
            if (shas_obs[s]) {
                reading = now - sobs[s]
                if (reading < 0) reading = 0
            } else if (shas_age[s]) {
                reading = sage[s] + (doc_age > 0 ? doc_age : 0)
            } else {
                reading = -1
            }
            # A reading cannot be fresher than the document carrying it.
            if (reading < 0) eff = -1
            else if (doc_age > reading) eff = doc_age
            else eff = reading

            line = ((s in sid) ? sid[s] : "?")
            line = line " " eff
            line = line " " (serr[s] ? 1 : 0)
            wc = wcount[s] + 0
            for (w = 0; w < wc; w++) line = line " " glyph[s, w]
            print line
        }
    }
    ' "$1"
}

out=""
first=1
if [[ -s "$state" ]]; then
    while read -ra f; do
        (( ${#f[@]} >= 3 )) || continue
        if (( ! first )); then
            out+=" "
        fi
        first=0

        age="${f[1]}"
        err="${f[2]}"
        idxs=("${f[@]:3}")

        if (( err )) || (( ${#idxs[@]} == 0 )); then
            out+="#[fg=colour${grey},nobright]·"
            continue
        fi

        stale=0
        if (( age < 0 )) || (( age > stale_seconds )); then
            stale=1
        fi

        for gi in "${idxs[@]}"; do
            (( gi >= 0 && gi <= 7 )) || gi=0
            if (( stale )); then
                out+="#[fg=colour${grey},nobright]${ticks[gi]}"
            else
                out+="#[fg=colour${ramp[gi]},nobright]${ticks[gi]}"
            fi
        done
    done < <(read_state "$state" "$now" "$doc_fallback_age")
fi

# No document, an unreadable one, or no sources in it. Show something dim
# rather than nothing: a widget that disappears reads as "all clear".
if [[ -z "$out" ]]; then
    out="#[fg=colour${grey},nobright]·"
fi

printf '%s' "$out"
