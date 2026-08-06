#!/usr/bin/env bash
# Render CPU or RAM use as a tmux-colored fill bar.
#
# Companion to tmux-cpu-spark.sh, and dependency-free in the same way: it reads
# /proc directly, so it needs no iostat, sar or ps. The level is drawn as N
# cells, of which the filled ones show the level and the rest (░) stay dim.
# Filled cells take their color from the spark's heat ramps.
#
# The bar has sub-cell resolution, using the eighth-block glyphs, and rounds
# down. A completely full bar therefore means 100%, not "about full".
#
# Usage: tmux-gauge.sh <cpu|ram> [scheme] [cells]
#   scheme: vivid (default) | muted | icefire
#   cells:  number of cells in the bar (default 5)
#
# cpu: share of CPU time that was not idle since the previous call. The
#      previous /proc/stat sample is kept in a state file, so the reading
#      covers the status-interval rather than the time since boot. The first
#      call has nothing to compare against and reports the since-boot average.
# ram: MemTotal - MemAvailable, which is what `free` reports as used. Cache
#      and buffers do not count as used.
set -euo pipefail

metric="${1:-}"
scheme="${2:-vivid}"
cells="${3:-5}"

case "$scheme" in
    vivid)   ramp=(46 118 154 184 220 214 208 196) ;;
    muted)   ramp=(108 108 144 180 179 173 167 160) ;;
    icefire) ramp=(39 45 51 190 226 214 202 196) ;;
    *)       ramp=(46 118 154 184 220 214 208 196) ;;  # unknown -> vivid
esac

# Percent in use, 0-100.
read_ram_pct() {
    local key value _ total="" avail=""
    while read -r key value _; do
        case "$key" in
            MemTotal:) total="$value" ;;
            MemAvailable:) avail="$value" ;;
        esac
        [[ -n "$total" && -n "$avail" ]] && break
    done < /proc/meminfo

    [[ -n "$total" && -n "$avail" && "$total" -gt 0 ]] || return 1
    echo $(( ((total - avail) * 100 + total / 2) / total ))
}

read_cpu_pct() {
    local cpu user nice system idle iowait irq softirq steal
    # guest and guest_nice are already counted inside user and nice, so the
    # total stops at steal.
    read -r cpu user nice system idle iowait irq softirq steal _ < /proc/stat
    [[ "$cpu" == "cpu" ]] || return 1

    local total idle_all
    total=$(( user + nice + system + idle + iowait + irq + softirq + steal ))
    idle_all=$(( idle + iowait ))

    local state="${XDG_RUNTIME_DIR:-/tmp}/tmux-gauge-cpu.${UID}"
    local prev_total=0 prev_idle=0 prev_pct=0 pct
    if [[ -r "$state" ]]; then
        read -r prev_total prev_idle prev_pct < "$state" || true
        : "${prev_total:=0}" "${prev_idle:=0}" "${prev_pct:=0}"
    fi

    local d_total=$(( total - prev_total ))
    local d_idle=$(( idle_all - prev_idle ))
    if (( d_total > 0 )); then
        pct=$(( ((d_total - d_idle) * 100 + d_total / 2) / d_total ))
    elif (( prev_total > 0 )); then
        # Called twice inside one clock tick: reuse the last reading rather
        # than report a bogus zero.
        pct="$prev_pct"
    else
        # First call. Nothing to diff against, so use the since-boot average.
        pct=$(( total > 0 ? ((total - idle_all) * 100 + total / 2) / total : 0 ))
    fi
    (( pct < 0 )) && pct=0
    (( pct > 100 )) && pct=100

    printf '%s %s %s\n' "$total" "$idle_all" "$pct" > "$state.$$" 2>/dev/null &&
        mv -f "$state.$$" "$state" 2>/dev/null || rm -f "$state.$$" 2>/dev/null || true

    echo "$pct"
}

case "$metric" in
    cpu) pct=$(read_cpu_pct) || exit 0 ;;
    ram) pct=$(read_ram_pct) || exit 0 ;;
    *)   echo "usage: $(basename "$0") <cpu|ram> [scheme] [cells]" >&2; exit 2 ;;
esac

(( pct < 0 )) && pct=0
(( pct > 100 )) && pct=100

# Fill level in eighths of a cell, rounded down.
eighths=$(( pct * cells * 8 / 100 ))
full=$(( eighths / 8 ))
rem=$(( eighths % 8 ))

# Heat level 0-7, matching the spark's ramp.
idx=$(( (pct * 7 + 50) / 100 ))
(( idx > 7 )) && idx=7

# Leading fractions of a cell, for rem 1-7.
partials=(▏ ▎ ▍ ▌ ▋ ▊ ▉)

out="#[fg=colour${ramp[idx]},nobright]"
for (( i = 0; i < full; i++ )); do
    out+="█"
done
drawn="$full"
if (( rem > 0 && drawn < cells )); then
    out+="${partials[rem - 1]}"
    drawn=$(( drawn + 1 ))
fi
if (( drawn < cells )); then
    out+="#[fg=colour238,nobright]"
    for (( i = drawn; i < cells; i++ )); do
        out+="░"
    done
fi

printf '%s' "$out"
