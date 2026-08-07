#!/bin/bash
# Notification history menu using rofi + makoctl

CLEAR_ALL="󰎟  Clear All"

# Find icon path for an app name from the icon theme
find_icon() {
    local app="$1"
    local name=$(echo "$app" | tr '[:upper:]' '[:lower:]')
    local icon

    # Search common icon locations
    for dir in /usr/share/icons/hicolor /usr/share/pixmaps; do
        icon=$(find "$dir" -iname "${name}.png" -o -iname "${name}.svg" 2>/dev/null | head -1)
        [[ -n "$icon" ]] && echo "$icon" && return
    done

    echo ""
}

build_menu() {
    local history
    history=$(makoctl history 2>/dev/null)

    if [[ -z "$history" ]] || ! echo "$history" | grep -q "^Notification"; then
        echo "No notifications"
        return
    fi

    local entries=""
    local app="" summary=""

    while IFS= read -r line; do
        if [[ "$line" =~ ^Notification\ [0-9]+:\ (.*) ]]; then
            summary="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^\ \ App\ name:\ (.*) ]]; then
            app="${BASH_REMATCH[1]}"
            local icon
            icon=$(find_icon "$app")
            if [[ -n "$icon" ]]; then
                entries+="${app}  →  ${summary}\x00icon\x1f${icon}\n"
            else
                entries+="${app}  →  ${summary}\n"
            fi
        fi
    done <<< "$history"

    echo -ne "$entries"
    echo ""
    echo -ne "${CLEAR_ALL}\x00icon\x1fedit-clear-all\n"
}

selected=$(build_menu | rofi -dmenu -i -p "󰂚 " -show-icons -theme ~/.config/rofi/themes/notifications.rasi)

case "$selected" in
    "$CLEAR_ALL")
        makoctl dismiss --all
        ;;
    "No notifications"|"")
        ;;
    *)
        makoctl invoke
        ;;
esac
