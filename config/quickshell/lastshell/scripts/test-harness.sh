#!/bin/bash
# Run lastshell inside a nested Hyprland, so shell development never touches
# the session you are sitting in. Modeled on
# ~/Projects/Rust/hoja/scripts/sway-harness.sh, but the nested compositor is
# Hyprland rather than sway: half the shell (workspaces widget, socket2
# events, Hyprland.dispatch) speaks Hyprland IPC that sway cannot provide.
#
#   scripts/test-harness.sh [script-file] [out-dir]
#
# With no script file, starts the nested session and leaves it running for
# interactive poking (Ctrl-C tears it down). With one, sources it with:
#
#   $OUT        where shots land            shot NAME    full-output screenshot
#   $NWL        nested WAYLAND_DISPLAY      key ...      wtype args, nested scope
#   $HIS        nested HYPRLAND_INSTANCE_SIGNATURE
#   hyp ...     hyprctl against the nested instance
#   click X Y   left-click at nested coords (wlrctl virtual pointer)
#
# grim/wtype/wlrctl all scope to $NWL, never the host. ydotool is banned here
# for the same reason it is in the hoja harness: uinput lands on whatever the
# real session has focused.
set -u

BODY=${1:-}
OUT=${2:-$(mktemp -d /tmp/lastshell-test.XXXX)}
REPO=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$OUT"

for tool in Hyprland qs grim wtype wlrctl jq; do
    command -v "$tool" >/dev/null || { echo "missing $tool" >&2; exit 1; }
done

# Nested Hyprland. It inherits the session's WAYLAND_DISPLAY and opens as a
# window; its own clients get a fresh socket. Instance signatures are dirs in
# $XDG_RUNTIME_DIR/hypr — diff before/after to find the new one.
before=$(ls "$XDG_RUNTIME_DIR/hypr" 2>/dev/null)
Hyprland --config "$REPO/test/hyprland-test.lua" >"$OUT/hyprland.log" 2>&1 &
HYPR_PID=$!

HIS=""
for _ in $(seq 1 50); do
    sleep 0.2
    for d in "$XDG_RUNTIME_DIR/hypr"/*/; do
        d=$(basename "$d")
        grep -q "$d" <<<"$before" || { HIS=$d; break 2; }
    done
done
[ -n "$HIS" ] || { echo "nested Hyprland never registered an instance" >&2; kill $HYPR_PID; exit 1; }

hyp() { HYPRLAND_INSTANCE_SIGNATURE=$HIS hyprctl "$@"; }

# The nested compositor's client socket: env of the Hyprland process.
NWL=""
for _ in $(seq 1 50); do
    sleep 0.2
    NWL=$(tr '\0' '\n' < /proc/$HYPR_PID/environ 2>/dev/null | sed -n 's/^_WAYLAND_DISPLAY_OUT=//p')
    # Hyprland exports its client display as WAYLAND_DISPLAY to children; read
    # it from the instance dir instead, which is authoritative.
    [ -S "$XDG_RUNTIME_DIR/wayland-$HIS" ] && NWL="wayland-$HIS"
    # Modern Hyprland names it after the instance socket:
    for s in "$XDG_RUNTIME_DIR"/wayland-*; do
        [ -S "$s" ] || continue
        name=$(basename "$s")
        [ "$name" = "${WAYLAND_DISPLAY:-wayland-1}" ] && continue
        NWL=$name
    done
    [ -n "$NWL" ] && break
done
[ -n "$NWL" ] || { echo "could not find nested wayland socket" >&2; kill $HYPR_PID; exit 1; }

echo "nested: HIS=$HIS  WAYLAND_DISPLAY=$NWL  out=$OUT"

# Launch the shell inside the nested session.
env WAYLAND_DISPLAY="$NWL" HYPRLAND_INSTANCE_SIGNATURE="$HIS" \
    qs -c lastshell >"$OUT/qs.log" 2>&1 &
QS_PID=$!

cleanup() { kill $QS_PID $HYPR_PID 2>/dev/null; }
trap cleanup EXIT INT TERM

sleep 3
# Hyprland paints a "started without start-hyprland" error banner over the top
# edge in debug environments — exactly where the top bar lives. Dismiss it.
hyp dismissnotify >/dev/null 2>&1

shot()  { WAYLAND_DISPLAY=$NWL grim "$OUT/$1.png" && echo "shot: $OUT/$1.png"; }
key()   { WAYLAND_DISPLAY=$NWL wtype "$@"; }
# wlrctl pointer move is RELATIVE. Absolute positioning = slam into the 0,0
# corner (motion clamps at edges), then move by the target offset.
hover() { WAYLAND_DISPLAY=$NWL wlrctl pointer move -20000 -20000 2>/dev/null
          WAYLAND_DISPLAY=$NWL wlrctl pointer move "$1" "$2" 2>/dev/null; }
click() { hover "$1" "$2"; WAYLAND_DISPLAY=$NWL wlrctl pointer click left; }

if [ -n "$BODY" ]; then
    # shellcheck disable=SC1090
    source "$BODY"
else
    echo "interactive: nested session up. Ctrl-C to tear down."
    wait $QS_PID
fi
