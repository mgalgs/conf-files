#!/usr/bin/env bash
# Render the 1/5/15-minute load averages as tmux-colored sparkline glyphs.
#
# Dependency-free replacement for the old npm `tmux-cpu` package (which dragged
# in yargs -> minimist and a string of Dependabot alerts). Each load average is
# expressed as a percentage of total CPU capacity (load / ncpu * 100) and mapped
# to one of the eight sparkline glyphs, exactly matching the old package's math.
#
# Usage: tmux-cpu-spark.sh [color1 color5 color15]
#   Colors are tmux color names/codes for the 1/5/15-minute glyphs.
set -euo pipefail

# tmux colours for the 1/5/15-minute glyphs (defaults match the previous config).
c1="${1:-colour105}"
c5="${2:-colour178}"
c15="${3:-colour196}"

ticks=(▁ ▂ ▃ ▄ ▅ ▆ ▇ █)

ncpu=$(nproc 2>/dev/null || echo 1)
read -r l1 l5 l15 _ < /proc/loadavg

# Compute the glyph index (0-7) for each load average. Mirror the old package:
# round load/ncpu*100 to an integer percent, then round percent*7/100 to a tick.
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

printf '#[fg=%s,nobright]%s#[fg=%s,nobright]%s#[fg=%s,nobright]%s' \
    "$c1" "${ticks[i1]}" "$c5" "${ticks[i5]}" "$c15" "${ticks[i15]}"
