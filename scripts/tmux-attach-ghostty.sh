#!/bin/sh

if [ "$#" -ne 1 ]; then
    printf 'Usage: %s SESSION\n' "$0" >&2
    exit 2
fi

nohup /usr/bin/ghostty \
      --gtk-single-instance=true \
      --font-size=14 \
      -e tmux attach-session -t "$1" \
      </dev/null >/dev/null 2>&1 &
