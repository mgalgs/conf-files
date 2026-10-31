#!/usr/bin/env bash
# Cycle a tmux session's windows in most-recently-used order.
#
# Usage: tmux-mru-cycle.sh <start|next> <session-id>
#   start: snapshot the session's MRU order, then step to the previous window
#   next:  step one window further back in that snapshot, wrapping around
#
# .tmux.conf binds prefix C-l to `start` and enters the mru-cycle key table,
# where C-l runs `next` -- like Emacs's pop-mark, where SPC keeps popping. Any
# other key leaves the table and then does what it normally does.
#
# Each step re-selects the windows already visited in this cycle, so tmux's own
# MRU stack ends up alt-tab shaped: the window landed on, then the one the
# cycle started from, then the rest. prefix l then goes back to the start.
set -euo pipefail

mode="${1:-}"
sid="${2:-}"
if [[ "$mode" != start && "$mode" != next ]] || [ -z "$sid" ]; then
    sed -n '4,6p' "$0" | sed 's/^# \{0,1\}//' >&2
    exit 2
fi

opt() { tmux show-options -qv -t "$sid" "$1"; }

if [ "$mode" = start ]; then
    # window_stack_index is 1 for the previous window, 2 for the one before,
    # and so on. It is 0 for the current window and for a window never
    # visited; the never-visited ones go last, in index order.
    order=$(tmux list-windows -t "$sid" \
            -F '#{window_active} #{window_stack_index} #{window_index} #{window_id}' \
        | awk '{ print ($1 ? 0 : ($2 ? $2 : 1000000 + $3)), $4 }' \
        | sort -n | cut -d' ' -f2 | tr '\n' ' ')
    tmux set-option -q -t "$sid" @mru-cycle "$order" \; \
        set-option -q -t "$sid" @mru-cycle-pos 0 \; \
        set-option -q -t "$sid" @mru-cycle-seen 0
fi

read -ra wins <<< "$(opt @mru-cycle)"
n=${#wins[@]}
[ "$n" -gt 1 ] || exit 0
pos=$(opt @mru-cycle-pos)
seen=$(opt @mru-cycle-seen)

pos=$(( (pos + 1) % n ))
[ "$pos" -gt "$seen" ] && seen=$pos

# Selecting in reverse of the wanted MRU order builds that order. Only windows
# this cycle already showed are touched, so no unvisited window has its
# activity or bell flag cleared. One tmux call means one redraw, no flicker.
args=()
for (( j = seen; j >= 0; j-- )); do
    [ "$j" -eq "$pos" ] && continue
    args+=(select-window -t "${wins[j]}" ';')
done
args+=(select-window -t "${wins[pos]}" ';'
       set-option -q -t "$sid" @mru-cycle-pos "$pos" ';'
       set-option -q -t "$sid" @mru-cycle-seen "$seen")
tmux "${args[@]}"
