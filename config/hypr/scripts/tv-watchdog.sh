#!/bin/bash
# The TV's last line of defence, run by hypridle at 10 min without input and
# on the input that ends it. deskpresence owns the TV; while it is alive
# (its status file is fresher than 15 s: it rewrites it every 5) this does
# nothing. If it is dead, nothing else will blank the OLED, so this does.
#
# Replaced idle-guard.sh (2026-09-27), which blanked only when the radar did
# not vouch for someone and so fought deskpresence over the screen.

STATUS="$HOME/.local/state/deskpresence/status.json"
TV_SCREEN="${TV_SCREEN:-$HOME/.config/hypr/scripts/tv-screen.sh}"
LOG="$HOME/.config/lgtv/screen.log"
log() { printf '%s tv-watchdog: %s\n' "$(date '+%F %T')" "$*" >> "$LOG"; }

daemon_alive() {
    [ -f "$STATUS" ] && [ $(( $(date +%s) - $(stat -c %Y "$STATUS") )) -le 15 ]
}

case "$1" in
  idle)
    daemon_alive && exit 0
    log "deskpresence is not running; blanking after 10 min without input"
    exec "$TV_SCREEN" off ;;
  resume)
    daemon_alive && exit 0
    log "deskpresence is not running; input is back, waking the TV"
    exec "$TV_SCREEN" on ;;
  *) echo "usage: tv-watchdog.sh idle|resume" >&2; exit 2 ;;
esac
