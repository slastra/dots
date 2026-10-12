#!/bin/bash
# The laptop's actuator for deskpresence (the desk's is tv-screen.sh):
#   laptop-screen.sh off   panel DPMS off, keyboard backlight off
#   laptop-screen.sh on    panel DPMS on, keyboard backlight restored
# Records what it achieved in $STATE, which deskpresence reads back as "tv".

STATE="${STATE:-$HOME/.local/state/laptop-screen/state}"
KBD=platform::kbd_backlight

# Run from a systemd user unit this has no Hyprland instance in its
# environment. Ask which instances are running and take the oldest: the
# session, not a nested test compositor (their stale socket dirs linger, so
# "newest dir in $XDG_RUNTIME_DIR/hypr" picks a dead one).
if [ -z "$HYPRLAND_INSTANCE_SIGNATURE" ]; then
    HYPRLAND_INSTANCE_SIGNATURE=$(hyprctl instances -j | jq -r 'sort_by(.time) | .[0].instance // empty')
    export HYPRLAND_INSTANCE_SIGNATURE
fi

# Lua config: `dispatch dpms off` is a syntax error there, the dispatcher
# has to be written as a hl.dsp call.
dpms() { hyprctl dispatch "hl.dsp.dpms({ action = \"$1\" })" >/dev/null; }

case "$1" in
    off)
        dpms off || exit 1
        brightnessctl -q -s -d "$KBD" set 0
        ;;
    on)
        dpms on || exit 1
        brightnessctl -q -r -d "$KBD" >/dev/null
        ;;
    *)
        echo "usage: $0 on|off" >&2
        exit 2
        ;;
esac

mkdir -p "$(dirname "$STATE")"
echo "$1" > "$STATE"
# lastshell's auto brightness holds off while the panel is off (--any-display:
# this runs under deskpresence's systemd unit)
qs -c lastshell ipc --any-display call backlight sync >/dev/null 2>&1 &
