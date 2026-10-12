#!/usr/bin/env bash
# Eco mode: maximum battery life. `eco.sh [on|off|toggle|status]` (Super+Shift+E).
# On: power-saver CPU profile, Bluetooth and keyboard backlight off, hyprglaze
# stopped, and hyprland.lua's lean look (60 Hz, no blur, still border, no
# animations) even on AC. Off: puts back what was there before.
state=${XDG_STATE_HOME:-$HOME/.local/state}/eco
kbd=/sys/class/leds/platform::kbd_backlight/brightness

bt_blocked() { rfkill list bluetooth | grep -q 'Soft blocked: yes' && echo 1 || echo 0; }

on() {
    [[ -f $state ]] && return
    mkdir -p "$(dirname "$state")"
    {
        echo "profile=$(powerprofilesctl get)"
        echo "bt_blocked=$(bt_blocked)"
        echo "kbd=$(cat "$kbd" 2>/dev/null || echo 0)"
    } > "$state"
    powerprofilesctl set power-saver
    rfkill block bluetooth
    echo 0 > "$kbd" 2>/dev/null
    systemctl --user stop hyprglaze.service
    hyprctl reload >/dev/null
    qs -c lastshell ipc call eco sync 2>/dev/null
    notify-send -a eco "Eco mode on" "Power saver, 60 Hz, no effects, Bluetooth off"
}

off() {
    [[ -f $state ]] || return
    # shellcheck disable=SC1090
    source "$state"
    rm -f "$state"
    qs -c lastshell ipc call eco sync 2>/dev/null
    powerprofilesctl set "${profile:-balanced}"
    [[ ${bt_blocked:-0} == 0 ]] && rfkill unblock bluetooth
    echo "${kbd:-0}" > "$kbd" 2>/dev/null
    hyprctl reload >/dev/null
    [[ $(cat /sys/class/power_supply/ADP1/online) == 1 ]] && systemctl --user start hyprglaze.service
    notify-send -a eco "Eco mode off" "Restored $profile profile"
}

case ${1:-toggle} in
    on) on ;;
    off) off ;;
    toggle) if [[ -f $state ]]; then off; else on; fi ;;
    status) [[ -f $state ]] && echo on || echo off ;;
    *) echo "usage: eco.sh [on|off|toggle|status]" >&2; exit 2 ;;
esac
