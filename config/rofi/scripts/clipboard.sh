#!/bin/bash
# Clipboard history picker. cliphist stores entries; hyprland.lua starts the
# `wl-paste --watch cliphist store` daemon that feeds it.
#
# cliphist list emits "<id>\t<preview>". The id must survive the round trip to
# cliphist decode, so the whole line goes through rofi and the id is cut off
# afterwards rather than shown.

set -euo pipefail

selected=$(cliphist list | rofi -dmenu -i -p "󰅍 " -theme ~/.config/rofi/themes/clipboard.rasi)
[ -z "$selected" ] && exit 0

printf '%s' "$selected" | cliphist decode | wl-copy
