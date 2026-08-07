#!/bin/bash
# Switch hyprglaze effect via rofi (edits TOML, daemon hot-reloads)

CONFIG="$HOME/.config/hypr/hyprglaze.toml"

current=$(awk -F'"' '/^effect[[:space:]]*=/{print $2; exit}' "$CONFIG")

menu=$(hyprglaze --list-effects | awk -v cur="$current" '{
  if ($0 == cur) print "<span foreground=\"#c4a7e7\">" $0 "</span>"; else print $0
}')

selected=$(echo "$menu" | rofi -dmenu -i -markup-rows -p "󰸉 " -theme ~/.config/rofi/themes/effect.rasi | sed -E 's|<[^>]+>||g')
[ -z "$selected" ] && exit

sed -i -E "s/^effect[[:space:]]*=.*/effect = \"$selected\"/" "$CONFIG"
