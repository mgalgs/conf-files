#!/bin/sh

if [ "$#" -ne 1 ]; then
    printf 'Usage: %s SESSION\n' "$0" >&2
    exit 2
fi

nohup /usr/bin/ghostty \
      --gtk-single-instance=true \
      --font-size=14 \
      -e tmux new-session -A -s "$1" \
      </dev/null >/dev/null 2>&1 &
