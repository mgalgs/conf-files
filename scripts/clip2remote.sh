#!/usr/bin/env bash
#
# clip2remote.sh -- push the local clipboard image to a remote host, then
# copy the resulting remote path back onto the local clipboard.
#
# Purpose: paste screenshots into a Claude Code (or editor) session that runs
# on a remote host over SSH. Image clipboard data does not travel through SSH,
# but a file path does. So: this runs on your LAPTOP, lands the image on the
# remote filesystem, and hands you the remote path. Text paste works over SSH,
# so you press Ctrl+V in the remote session and the path appears.
#
# Usage:
#   clip2remote.sh [[user@]host[:/remote/dir]]
#
#   host        SSH target. Default: bitforge
#   /remote/dir Destination directory on the host. Default: /tmp
#
# Examples:
#   clip2remote.sh                       # -> bitforge:/tmp/clip-<stamp>.png
#   clip2remote.sh bitforge:/home/mgalgs/shots
#   clip2remote.sh me@otherhost
#
# Requires (local): openssh (scp), and one clipboard tool for your session:
#   Wayland -> wl-clipboard (wl-paste / wl-copy)
#   X11     -> xclip
set -euo pipefail

target="${1:-bitforge}"
host="${target%%:*}"
if [ "$host" != "$target" ]; then
    remote_dir="${target#*:}"
else
    remote_dir="/tmp"
fi
remote_dir="${remote_dir%/}"
[ -z "$remote_dir" ] && remote_dir="/" # a bare "host:/" target must stay "/"

if [ -z "$host" ]; then
    echo "clip2remote: no SSH host in target '$target'" >&2
    exit 2
fi

have() { command -v "$1" >/dev/null 2>&1; }

# Decide which clipboard backend to use for this session. On Wayland, do not
# fall back to xclip: it reads the X11 clipboard through XWayland and usually
# cannot see the image, which would give a misleading "no image" error. Tell
# the user to install wl-clipboard instead.
if [ -n "${WAYLAND_DISPLAY:-}" ]; then
    if have wl-paste && have wl-copy; then
        backend="wayland"
    else
        echo "clip2remote: Wayland session detected, but wl-clipboard is missing." >&2
        echo "  install it:  sudo pacman -S wl-clipboard" >&2
        exit 3
    fi
elif have xclip; then
    backend="x11"
else
    echo "clip2remote: need wl-clipboard (Wayland) or xclip (X11) on this machine" >&2
    exit 3
fi

list_targets() {
    case "$backend" in
    wayland) wl-paste --list-types ;;
    x11) xclip -selection clipboard -t TARGETS -o ;;
    esac
}

read_clip() { # $1 = mime type -> bytes on stdout
    case "$backend" in
    wayland) wl-paste --type "$1" ;;
    x11) xclip -selection clipboard -t "$1" -o ;;
    esac
}

copy_text() { # stdin -> local clipboard
    case "$backend" in
    wayland) wl-copy ;;
    x11) xclip -selection clipboard ;;
    esac
}

# Pick an image mime the clipboard actually offers (png preferred).
targets="$(list_targets || true)"
mime=""
for m in image/png image/jpeg image/webp; do
    if printf '%s\n' "$targets" | grep -qx "$m"; then
        mime="$m"
        break
    fi
done
if [ -z "$mime" ]; then
    echo "clip2remote: no image on the clipboard" >&2
    echo "  available types: $(printf '%s' "$targets" | tr '\n' ' ')" >&2
    exit 1
fi

ext="${mime#image/}"
[ "$ext" = "jpeg" ] && ext="jpg"

tmp="$(mktemp --suffix=".$ext")"
trap 'rm -f "$tmp"' EXIT
read_clip "$mime" >"$tmp"
if [ ! -s "$tmp" ]; then
    echo "clip2remote: the clipboard image was empty" >&2
    exit 1
fi

stamp="$(date +%Y%m%d-%H%M%S)-$$"
remote_path="$remote_dir/clip-$stamp.$ext"
scp -q "$tmp" "$host:$remote_path"

# Re-copy the remote path so you can paste it straight into the remote session.
printf '%s' "$remote_path" | copy_text

echo "$remote_path"
