#!/bin/bash
# Rofi browser tab switcher with favicons for Hyprland + Helium.
#
# This script only READS the favicon cache. tabstrip owns it: that daemon is
# always running and subscribed to tabctl's TabsUpdated, so it fetches and
# composites a chip the moment a tab appears. This runs occasionally, and
# doing the work here meant the waybar strip sat on placeholder chips until
# the switcher happened to be opened.
#
# A missing chip therefore means tabstrip hasn't got to it yet, or the icon is
# unusable. Either way the browser's own icon stands in.

ICON_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/tabctl/favicons"
LOG_FILE="$HOME/.cache/rofi-tabs/debug.log"
mkdir -p "$(dirname "$LOG_FILE")"

# tabctl 2.2.0+ gives a second profile of the same browser its own prefix
# (chrome2, chrome3). Strip that so every profile resolves to one browser.
browser_base() {
  echo "${1%%[0-9]*}"
}

# Map a tabctl browser prefix → executable, display name, and icon-theme name.
# Add new browsers here as needed. Unknown prefixes fall through to a best guess.
browser_exec() {
  case "$(browser_base "$1")" in
    firefox)  echo "firefox" ;;
    helium)   echo "helium-browser" ;;
    brave)    echo "brave" ;;
    chrome)   echo "google-chrome-stable" ;;
    chromium) echo "chromium" ;;
    zen)      echo "zen-browser" ;;
    *)        echo "$1" ;;
  esac
}
browser_name() {
  case "$(browser_base "$1")" in
    firefox)  echo "Firefox" ;;
    helium)   echo "Helium" ;;
    brave)    echo "Brave" ;;
    chrome)   echo "Chrome" ;;
    chromium) echo "Chromium" ;;
    zen)      echo "Zen" ;;
    *)        echo "$1" ;;
  esac
}
browser_icon() {
  case "$(browser_base "$1")" in
    firefox)  echo "firefox" ;;
    helium)   echo "helium-browser" ;;
    brave)    echo "brave-browser" ;;
    chrome)   echo "google-chrome" ;;
    chromium) echo "chromium" ;;
    zen)      echo "zen-browser" ;;
    *)        echo "$1" ;;
  esac
}

exec 2>>"$LOG_FILE"
echo "=== Script started at $(date) ===" >>"$LOG_FILE"

get_domain() {
  echo "$1" | sed -E 's|^https?://||' | sed -E 's|^www\.||' | cut -d'/' -f1
}

# Chips are keyed by the favicon URL's SHA-256, so a site changing its icon
# misses rather than serving a stale one.
#
# KEEP IN SYNC with iconKey() in ~/Projects/Go/tabstrip/icons.go, which writes
# these files. Change one without the other and every lookup here misses,
# leaving the menu on browser icons with no other symptom.
chip_for() {
  local favicon_url="$1" browser="$2" key p

  if [ -n "$favicon_url" ]; then
    key=$(printf '%s' "$favicon_url" | sha256sum | cut -c1-16)
    p="$ICON_CACHE/$key-processed.png"
    [ -s "$p" ] && echo "$p" && return
  fi

  # Not cached yet, or unusable: stand in with the browser's own icon so rows
  # stay aligned rather than going ragged.
  p="$ICON_CACHE/_fallback-$(browser_base "$browser").png"
  [ -s "$p" ] && echo "$p" && return

  p="$ICON_CACHE/_tabstrip-fallback.png"
  [ -s "$p" ] && echo "$p" && return

  echo ""
}

tabs_json=$(tabctl list --format json)

# Build a "New Window" entry per browser that currently has tabs open.
# new_window_cmds[i] is the executable for the i-th top entry.
new_window_cmds=()
entries=""
declare -A seen_browsers
while read -r prefix; do
  [ -z "$prefix" ] && continue
  # Two profiles of one browser (chrome, chrome2) get one "New Window" entry.
  base=$(browser_base "$prefix")
  [ "${seen_browsers[$base]+x}" ] && continue
  seen_browsers[$base]=1

  exec_cmd=$(browser_exec "$prefix")
  command -v "$exec_cmd" >/dev/null 2>&1 || continue

  label="New $(browser_name "$prefix") Window"
  icon_name=$(browser_icon "$prefix")
  entries+="$label\x00icon\x1f$icon_name\n"
  new_window_cmds+=("$exec_cmd")
done < <(echo "$tabs_json" | jq -r '.[].id | split(".")[0]' | sort -u)

# Fallback: if no browsers detected (no tabs), offer a generic entry via xdg default
if [ ${#new_window_cmds[@]} -eq 0 ]; then
  default_app=$(xdg-mime query default x-scheme-handler/https 2>/dev/null)
  if [ -n "$default_app" ] && command -v gtk-launch >/dev/null 2>&1; then
    entries+="New Window\x00icon\x1fweb-browser\n"
    new_window_cmds+=("gtk-launch ${default_app%.desktop}")
  fi
fi

n_browsers=${#new_window_cmds[@]}

# Tab entries follow the New Window entries. tab_ids[i] is the id for index i + n_browsers.
tab_ids=()

while IFS=$'\t' read -r id title url favicon; do
  icon=$(chip_for "$favicon" "${id%%.*}")
  domain=$(get_domain "$url")

  display_text="$title - $domain"
  if [ -n "$icon" ]; then
    entries+="$display_text\x00icon\x1f$icon\n"
  else
    entries+="$display_text\n"
  fi

  tab_ids+=("$id")
done < <(echo "$tabs_json" | jq -r '.[] | [.id, .title, .url, .favIconUrl] | @tsv')

# Enter switches to the tab; Ctrl+w closes it; Ctrl+c copies its URL. rofi
# returns the selected index on stdout (-format i) and signals the key via its
# exit code: 0 = Enter, 10 = custom-1 (Ctrl+w), 11 = custom-2 (Ctrl+c),
# 1 = cancelled (Escape). Ctrl+w defaults to kb-clear-line and Ctrl+c to
# kb-secondary-copy (which would only copy the row text), so free both
# bindings to reuse the keys.
selected_index=$(echo -ne "$entries" | rofi -dmenu -i -p "󱦞 " -show-icons -format i \
  -kb-clear-line "" -kb-custom-1 "Control+w" \
  -kb-secondary-copy "" -kb-custom-2 "Control+c" \
  -mesg "Enter: switch • Ctrl+w: close • Ctrl+c: copy URL" \
  -theme ~/.config/rofi/themes/tabs.rasi)
rofi_exit=$?

echo "User selected index: $selected_index (rofi exit $rofi_exit)" >>"$LOG_FILE"

if [ "$rofi_exit" -eq 1 ] || [ -z "$selected_index" ] || [ "$selected_index" = "-1" ]; then
  echo "No selection made (user cancelled)" >>"$LOG_FILE"
  echo "=== Script ended at $(date) ===" >>"$LOG_FILE"
  exit 0
fi

# First n_browsers entries are "New <Browser> Window" launchers. They have no
# URL to copy, so Ctrl+c is a no-op on them; any other accept just launches.
if [ "$selected_index" -lt "$n_browsers" ]; then
  [ "$rofi_exit" -eq 11 ] && exit 0
  cmd="${new_window_cmds[$selected_index]}"
  echo "Launching: $cmd" >>"$LOG_FILE"
  # Word-split intentional so "gtk-launch foo" works as well as "firefox"
  $cmd &
  exit 0
fi

tab_id="${tab_ids[$((selected_index - n_browsers))]}"
[ -z "$tab_id" ] && exit 0

# Ctrl+w (custom-1): close the tab, then reopen the menu so several can be
# closed in a row.
if [ "$rofi_exit" -eq 10 ]; then
  echo "Closing tab: $tab_id" >>"$LOG_FILE"
  tabctl close "$tab_id"
  exec "$0" "$@"
fi

# Ctrl+c (custom-2): copy the tab's URL to the clipboard.
if [ "$rofi_exit" -eq 11 ]; then
  tab_url=$(echo "$tabs_json" | jq -r --arg id "$tab_id" '.[] | select(.id == $id) | .url')
  echo "Copying URL for $tab_id: $tab_url" >>"$LOG_FILE"
  printf '%s' "$tab_url" | wl-copy
  notify-send -a "rofi-tabctl" "URL copied" "$tab_url"
  exit 0
fi

tab_title=$(echo "$tabs_json" | jq -r --arg id "$tab_id" '.[] | select(.id == $id) | .title')
tabctl activate "$tab_id"

# tabctl ids are prefixed with the browser (e.g. firefox.1.1, helium.x.y).
# Use that to scope window matching to the right browser class. Profiles of one
# browser share a window class, so match on the base (chrome2 -> chrome).
browser_prefix=$(browser_base "${tab_id%%.*}")

# Prefer an exact title match within the right browser; fall back to substring.
# If nothing matches by class (rare — e.g. window class doesn't share the prefix),
# fall back to title-only match across all windows.
window_address=$(hyprctl clients -j | jq -r --arg title "$tab_title" --arg prefix "$browser_prefix" '
  [.[] | select((.class | ascii_downcase) | contains($prefix))] as $scoped
  | (($scoped | map(select(.title == $title))) + ($scoped | map(select(.title | contains($title)))))[0].address // empty
')

if [ -z "$window_address" ]; then
  window_address=$(hyprctl clients -j | jq -r --arg title "$tab_title" '
    [.[] | select(.title | contains($title))][0].address // empty
  ')
fi

if [ -n "$window_address" ]; then
  echo "Focusing window with address: $window_address" >>"$LOG_FILE"
  hyprctl dispatch "hl.dsp.focus({ window = \"address:$window_address\" })"
else
  echo "No window found matching title: $tab_title (browser: $browser_prefix)" >>"$LOG_FILE"
fi

echo "=== Script ended at $(date) ===" >>"$LOG_FILE"
