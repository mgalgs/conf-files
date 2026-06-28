#!/usr/bin/env bash
# Render the 1/5/15-minute load averages as tmux-colored sparkline glyphs.
#
# Dependency-free replacement for the old npm `tmux-cpu` package. Each load
# average is expressed as a percentage of total CPU capacity (load / ncpu * 100)
# and mapped to one of eight glyphs (▁▂▃▄▅▆▇█), matching the old package's math.
#
# Usage: tmux-cpu-spark.sh [scheme]
#   scheme: vivid (default) | muted | icefire | current
#
# Heat schemes (vivid/muted/icefire) color each glyph by load level
# (green -> red); "current" keeps the old fixed per-window colors. To switch,
# change the argument in the status-right line of .tmux.conf and reload tmux.
set -euo pipefail

ticks=(▁ ▂ ▃ ▄ ▅ ▆ ▇ █)
scheme="${1:-vivid}"

# Heat schemes (mode=level) color by glyph level 0-7; "current" (mode=pos)
# colors by position (1m/5m/15m) regardless of load.
mode=level
case "$scheme" in
    vivid)   ramp=(46 118 154 184 220 214 208 196) ;;
    muted)   ramp=(108 108 144 180 179 173 167 160) ;;
    icefire) ramp=(39 45 51 190 226 214 202 196) ;;
    current) mode=pos; pos=(105 178 196) ;;
    *)       ramp=(46 118 154 184 220 214 208 196) ;;  # unknown -> vivid
esac

ncpu=$(nproc 2>/dev/null || echo 1)
read -r l1 l5 l15 _ < /proc/loadavg

# Glyph index (0-7) per load average: round load/ncpu*100 to a percent, then
# round percent*7/100 to a tick (same math as the old npm package).
read -r i1 i5 i15 < <(awk -v ncpu="$ncpu" -v a="$l1" -v b="$l5" -v c="$l15" 'BEGIN {
    n = split(a " " b " " c, loads, " ")
    for (i = 1; i <= n; i++) {
        pct = int((loads[i] / ncpu) * 100 + 0.5)
        idx = int(pct * 7 / 100 + 0.5)
        if (idx < 0) idx = 0
        if (idx > 7) idx = 7
        printf "%d ", idx
    }
    printf "\n"
}')

idxs=("$i1" "$i5" "$i15")
out=""
for p in 0 1 2; do
    idx="${idxs[p]}"
    if [[ "$mode" == pos ]]; then
        color="${pos[p]}"
    else
        color="${ramp[idx]}"
    fi
    out+="#[fg=colour${color},nobright]${ticks[idx]}"
done
printf '%s' "$out"
