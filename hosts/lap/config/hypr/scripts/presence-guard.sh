#!/bin/bash
# hypridle's hands, coordinated with deskpresence (the laptop's counterpart
# to the desk's idle-guard.sh):
#
#   presence-guard.sh timeout NAME CMD...   run CMD unless deskpresence is up
#                                           and sees someone at the laptop
#   presence-guard.sh resume  NAME CMD...   run CMD only if the matching
#                                           timeout actually ran
#
# Input-idle while the sensor vouches for you (reading, watching) is not idle.
# If the daemon is down or its sensor has gone quiet, the timeouts run as
# plain hypridle would, so a dead sensor never leaves the laptop awake.
# The marker keeps a skipped timeout's resume from running: `brillo -I` with
# nothing saved would restore a stale brightness.

mode=$1 name=$2
shift 2
STATUS="$HOME/.local/state/deskpresence/status.json"
MARK="${XDG_RUNTIME_DIR:-/tmp}/presence-guard.$name"
# lastshell's auto brightness holds off while these marks are up; tell it now
# rather than have it poll (--any-display: this also runs under systemd)
shell_sync() { qs -c lastshell ipc --any-display call backlight sync >/dev/null 2>&1 & }

present() {
    systemctl --user -q is-active deskpresence &&
        jq -e '.sensor_ok and .known and .present' "$STATUS" >/dev/null 2>&1
}

case "$mode" in
    timeout)
        present && exit 0
        touch "$MARK"
        shell_sync
        exec sh -c "$*"
        ;;
    resume)
        [ -e "$MARK" ] || exit 0
        # restore first, then drop the marker: lastshell's auto brightness
        # reads the marker as "not the user's change" while it exists
        sh -c "$*"
        rm -f "$MARK"
        shell_sync
        ;;
    *)
        echo "usage: $0 timeout|resume NAME CMD..." >&2
        exit 2
        ;;
esac
