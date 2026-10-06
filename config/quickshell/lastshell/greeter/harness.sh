#!/bin/bash
# Preview the greeter in a nested Hyprland (never the live session). Same
# mechanics as ../scripts/test-harness.sh; the greeter runs in demo mode
# because no greetd socket is present. Password "pass" succeeds.
#
#   greeter/harness.sh [script-file] [out-dir]
#     shot NAME · key ARGS (wtype) · click X Y · hyp ARGS (nested hyprctl)
set -u
BODY=${1:-}
OUT=${2:-$(mktemp -d /tmp/greeter-test.XXXX)}
HERE=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$OUT"
for tool in Hyprland qs grim wtype wlrctl; do command -v "$tool" >/dev/null || { echo "missing $tool" >&2; exit 1; }; done

before=$(ls "$XDG_RUNTIME_DIR/hypr" 2>/dev/null)
Hyprland --config "$HERE/hyprland-test.lua" >"$OUT/hyprland.log" 2>&1 &
HYPR_PID=$!
HIS=""
for _ in $(seq 1 50); do
    sleep 0.2
    for d in "$XDG_RUNTIME_DIR/hypr"/*/; do d=$(basename "$d"); grep -q "$d" <<<"$before" || { HIS=$d; break 2; }; done
done
[ -n "$HIS" ] || { echo "nested Hyprland never registered" >&2; kill $HYPR_PID; exit 1; }
hyp() { HYPRLAND_INSTANCE_SIGNATURE=$HIS hyprctl "$@"; }
NWL=""
for _ in $(seq 1 50); do
    sleep 0.2
    [ -S "$XDG_RUNTIME_DIR/wayland-$HIS" ] && NWL="wayland-$HIS"
    [ -n "$NWL" ] && break
    for s in "$XDG_RUNTIME_DIR"/wayland-*; do [ -S "$s" ] || continue; n=$(basename "$s"); [ "$n" = "${WAYLAND_DISPLAY:-wayland-1}" ] && continue; NWL=$n; done
    [ -n "$NWL" ] && break
done
[ -n "$NWL" ] || { echo "no nested wayland socket" >&2; kill $HYPR_PID; exit 1; }
echo "nested: HIS=$HIS WAYLAND_DISPLAY=$NWL out=$OUT"

# GREETER_WRAP=/path/to/fakegreet runs the greeter against greetd's fake
# socket (user "user", password "password", then answer "9" to "7 + 2:").
env WAYLAND_DISPLAY="$NWL" HYPRLAND_INSTANCE_SIGNATURE="$HIS" \
    LASTSHELL_GREETER_STATE="$OUT/state.json" \
    ${GREETER_WRAP:-} qs -p "$HERE/../greeter.qml" >"$OUT/qs.log" 2>&1 &
QS_PID=$!
cleanup() { kill $QS_PID 2>/dev/null; hyp dispatch 'hl.dsp.exit()' >/dev/null 2>&1 || hyp dispatch exit >/dev/null 2>&1; sleep 0.5; kill $HYPR_PID 2>/dev/null; }
trap cleanup EXIT INT TERM
sleep 2.5
hyp dismissnotify >/dev/null 2>&1

shot()  { WAYLAND_DISPLAY=$NWL grim "$OUT/$1.png" && echo "shot: $OUT/$1.png"; }
key()   { WAYLAND_DISPLAY=$NWL wtype "$@"; }
hover() { WAYLAND_DISPLAY=$NWL wlrctl pointer move -20000 -20000 2>/dev/null; WAYLAND_DISPLAY=$NWL wlrctl pointer move "$1" "$2" 2>/dev/null; }
click() { hover "$1" "$2"; WAYLAND_DISPLAY=$NWL wlrctl pointer click left; }

if [ -n "$BODY" ]; then source "$BODY"; else echo "interactive; Ctrl-C tears down"; wait $QS_PID; fi
