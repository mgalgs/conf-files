#!/usr/bin/env bash
# Render today's sunset time for the tmux status line.
#
# The location is GNOME Weather's first saved location, read at run time so
# no coordinates live in this (public) repo. The time is worked out once a day
# with NOAA's low-precision solar equations (good to about a minute) and
# cached; every other tick is a builtin read of the cache.
#
# The widget dims once the sun is down. It renders a dim "·" when there is no
# location or the sun does not set today.
#
# Usage: tmux-sunset.sh
set -euo pipefail

icon=$'\U000f059b'   # nf-md-weather_sunset_down
grey=238
cache="${XDG_RUNTIME_DIR:-/tmp}/tmux-sunset.${UID}"
printf -v today '%(%F)T' -1

day="" sunset=""
if [[ -r "$cache" ]]; then
    read -r day sunset < "$cache" || true
    # Minutes past local midnight; anything else is a stale format.
    [[ "$sunset" =~ ^[0-9]*$ ]] || day=""
fi

# A failed lookup is cached too, so it is retried tomorrow rather than forking
# gsettings every second.
if [[ "$day" != "$today" ]]; then
    sunset=""
    loc="$(gsettings get org.gnome.Weather locations 2>/dev/null)" || loc=""
    # Stored in radians, as the first "[(lat, lon)]" in the GVariant.
    if [[ "$loc" =~ \[\(([-0-9.e]+),\ ([-0-9.e]+)\)\] ]]; then
        printf -v doy '%(%j)T' -1
        printf -v tz '%(%z)T' -1
        sunset="$(awk -v lat="${BASH_REMATCH[1]}" -v lon="${BASH_REMATCH[2]}" \
            -v doy="$doy" -v tz="$tz" 'BEGIN {
            pi = atan2(0, -1)
            deg = 180 / pi
            g = 2 * pi / 365 * (doy - 1)
            eqt = 229.18 * (0.000075 + 0.001868 * cos(g) - 0.032077 * sin(g) \
                - 0.014615 * cos(2 * g) - 0.040849 * sin(2 * g))
            decl = 0.006918 - 0.399912 * cos(g) + 0.070257 * sin(g) \
                - 0.006758 * cos(2 * g) + 0.000907 * sin(2 * g) \
                - 0.002697 * cos(3 * g) + 0.00148 * sin(3 * g)
            x = cos(90.833 / deg) / (cos(lat) * cos(decl)) \
                - (sin(lat) / cos(lat)) * (sin(decl) / cos(decl))
            if (x < -1 || x > 1) exit
            ha = atan2(sqrt(1 - x * x), x)
            utc = 720 - 4 * (lon * deg - ha * deg) - eqt
            off = (substr(tz, 1, 1) == "-" ? -1 : 1) \
                * (substr(tz, 2, 2) * 60 + substr(tz, 4, 2))
            m = int(utc + off + 0.5)
            print (m % 1440 + 1440) % 1440
        }')" || sunset=""
    fi
    printf '%s %s\n' "$today" "$sunset" > "$cache.$$" 2>/dev/null &&
        mv -f "$cache.$$" "$cache" 2>/dev/null || rm -f "$cache.$$" 2>/dev/null || true
fi

if [[ -z "$sunset" ]]; then
    printf '#[fg=colour%s,nobright]·' "$grey"
    exit 0
fi

h=$(( sunset / 60 ))
h12=$(( h % 12 ))
(( h12 )) || h12=12
ampm=pm
(( h >= 12 )) || ampm=am
printf -v hh '%(%H)T' -1
printf -v mm '%(%M)T' -1

# Dimmed once the sun is down. 10# because %H and %M are zero-padded.
if (( 10#$hh * 60 + 10#$mm >= sunset )); then
    icon_colour=240 time_colour=242
else
    icon_colour=208 time_colour=214
fi

printf '#[fg=colour%s,nobright]%s#[fg=colour%s,nobright]%d:%02d%s' \
    "$icon_colour" "$icon" "$time_colour" "$h12" $(( sunset % 60 )) "$ampm"
