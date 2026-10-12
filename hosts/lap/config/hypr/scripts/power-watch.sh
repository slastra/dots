#!/usr/bin/env bash
# Follow the AC adapter: reload Hyprland (hyprland.lua reads ADP1/online
# itself and picks refresh rate, blur and border animation from it) and run
# the hyprglaze shader wallpaper on AC only. Runs in the session, so it never
# fires while the session is frozen for suspend.
adp=/sys/class/power_supply/ADP1/online
last=$(cat "$adp")

udevadm monitor --udev --subsystem-match=power_supply | while read -r _; do
    now=$(cat "$adp")
    [[ $now == "$last" ]] && continue
    last=$now
    hyprctl reload >/dev/null
    if [[ $now == 1 ]]; then
        [[ -f ~/.local/state/eco ]] || systemctl --user start hyprglaze.service
    else
        systemctl --user stop hyprglaze.service
    fi
done
