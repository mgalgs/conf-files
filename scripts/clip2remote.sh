#!/usr/bin/env bash
#
# clip2remote.sh -- push the local clipboard image to a remote host, then
# copy the resulting remote path back onto the local clipboard.
#
# Purpose: paste screenshots into a Claude Code (or editor) session that runs
# on a remote host over SSH. Image clipboard data does not travel through SSH,
# but a file path does. So: this runs where the clipboard is, lands the image
# on the remote filesystem, and hands you the remote path. Text paste works
# over SSH, so you press Ctrl+V in the remote session and the path appears.
#
# Usage:
#   clip2remote.sh [--print-only] [[user@]host[:/remote/dir]]
#
#   --print-only  Do not touch the local clipboard; just print the remote
#                 path on stdout. The GNOME clip2remote extension uses this
#                 and sets the clipboard itself.
#   host          SSH target. Default: bitforge
#   /remote/dir   Destination directory on the host. Default: /tmp
#
# Examples:
#   clip2remote.sh                       # -> bitforge:/tmp/clip-<stamp>.png
#   clip2remote.sh bitforge.home.lan:/home/mgalgs/shots
#   clip2remote.sh --print-only omie.home.lan
#
# Requires (local): openssh (scp), and one clipboard tool for your session:
#   Wayland -> wl-clipboard (wl-paste, plus wl-copy unless --print-only)
#   X11     -> xclip
set -euo pipefail

print_only=0
positional=()
while [ $# -gt 0 ]; do
    case "$1" in
    -p | --print-only) print_only=1 ;;
    --)
        shift
        while [ $# -gt 0 ]; do
            positional+=("$1")
            shift
        done
        break
        ;;
    -*)
        echo "clip2remote: unknown option '$1'" >&2
        exit 2
        ;;
    *) positional+=("$1") ;;
    esac
    shift
done

target="${positional[0]:-bitforge}"
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
# the user to install wl-clipboard instead. wl-copy is only needed when we
# write the path back to the clipboard (i.e. not --print-only).
if [ -n "${WAYLAND_DISPLAY:-}" ]; then
    if have wl-paste && { [ "$print_only" -eq 1 ] || have wl-copy; }; then
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

# Re-copy the remote path so you can paste it straight into the remote
# session -- unless --print-only, where the caller sets the clipboard.
if [ "$print_only" -eq 0 ]; then
    printf '%s' "$remote_path" | copy_text
fi

echo "$remote_path"
