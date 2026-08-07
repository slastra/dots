#!/bin/bash
# TV screen control for idle blanking (swayidle) and manual use.
#
# Resume lesson history (2026-07-23/24): the webOS panel-off API drops HPD and
# desyncs DPMS (needs a VT switch to recover) — so blanking is DPMS-based. But
# dpmsStatus lies: after standby the 4K120 FRL modeset can "succeed" while the
# link carries black. The only ground truth is the TV's own screenshot, so the
# resume path verifies pixels through the TV API and escalates until real:
#   dpms retry → TV input bounce (forces retrain) → TV power cycle.

TV_IP="192.168.11.243"
TV_MAC="84:a3:29:ad:42:5c"
LG=("$HOME/.local/share/lgtv/venv/bin/bscpylgtvcommand" -p "$HOME/.config/lgtv/keys.sqlite" "$TV_IP")

LOG="$HOME/.config/lgtv/screen.log"
log() { printf '%s %s\n' "$(date '+%F %T')" "$*" >> "$LOG"; }
log "invoked: $1"

dpms() { hyprctl dispatch "hl.dsp.dpms({ mode = \"$1\" })" >> "$LOG" 2>&1; }
dpms_up() { hyprctl monitors | grep -q 'dpmsStatus: 1'; }

# tv_sees_picture: 0 = TV shows real content, 1 = TV shows black, 2 = can't tell
# (API unreachable). Waybar chips are always lit, so a live desktop never
# measures black; a dead link measures ~0.005.
tv_sees_picture() {
  local uri brightness shot="${XDG_RUNTIME_DIR:-/tmp}/tv-screen-verify.jpg"
  uri=$(timeout 8 "${LG[@]}" take_screenshot 2>/dev/null | grep -o "'imageUri': '[^']*'" | cut -d"'" -f4)
  [ -n "$uri" ] || return 2
  curl -sk -m 8 "$uri" -o "$shot" || return 2
  brightness=$(identify -format '%[fx:mean]' "$shot" 2>/dev/null) || return 2
  awk -v b="$brightness" 'BEGIN { exit !(b > 0.02) }'
}

case "$1" in
  off)
    dpms off
    log "off: dpms dispatched"
    ;;
  on)
    # wol is a no-op if the TV is already awake; never let it gate the dpms call
    wol "$TV_MAC" >> "$LOG" 2>&1
    # Wait for the TV's API to answer before modesetting: from deep standby its
    # network stack needs well over the old 2s, and without the API we cannot
    # verify pixels — "unreachable, accepting" is how the 13:17 wake failed.
    for wait in 1 2 3 4 5 6 7 8 9 10; do
      timeout 5 "${LG[@]}" get_power_state >> /dev/null 2>&1 && { log "on: tv api up after $wait probe(s)"; break; }
      sleep 3
    done
    for attempt in 1 2 3 4 5 6 7 8; do
      # Escalate before the retry: a plain dpms cycle rarely fixes a
      # trained-but-black FRL link, the TV-side actions do.
      case "$attempt" in
        4) log "on: escalating - input bounce"
           timeout 10 "${LG[@]}" set_input HDMI_1 >> "$LOG" 2>&1; sleep 4
           timeout 10 "${LG[@]}" set_input HDMI_4 >> "$LOG" 2>&1; sleep 6 ;;
        7) log "on: escalating - tv power cycle"
           timeout 10 "${LG[@]}" power_off >> "$LOG" 2>&1; sleep 6
           wol "$TV_MAC" >> "$LOG" 2>&1; sleep 12
           timeout 10 "${LG[@]}" set_input HDMI_4 >> "$LOG" 2>&1; sleep 3 ;;
      esac

      dpms on
      sleep 3
      if ! dpms_up; then
        log "on: attempt $attempt - dpms still down"
        continue
      fi

      tv_sees_picture
      case $? in
        0) log "on: verified picture (attempt $attempt)"; exit 0 ;;
        2) # Unverifiable is a failure, not a pass — the 13:17 wake proved
           # dpmsStatus lies exactly when the TV is too asleep to answer.
           # Accept blind only on the final attempt (TV may be genuinely off).
           if [ "$attempt" = 8 ]; then
             log "on: dpms up, tv api never came up - accepting blind"
             exit 0
           fi
           log "on: attempt $attempt - dpms up but tv api unreachable, retrying"
           sleep 3 ;;
        *) log "on: attempt $attempt - dpms up but TV SHOWS BLACK, retraining"
           dpms off; sleep 1 ;;
      esac
    done
    log "on: FAILED - all attempts exhausted, VT switch (ctrl+alt+f2, f1) may be needed"
    ;;
  panel-off)
    timeout 10 "${LG[@]}" turn_screen_off >> "$LOG" 2>&1 && log "panel-off: api ok"
    ;;
  panel-on)
    timeout 10 "${LG[@]}" turn_screen_on >> "$LOG" 2>&1 && log "panel-on: api ok"
    ;;
  *)
    echo "usage: tv-screen.sh on|off|panel-on|panel-off" >&2
    exit 2
    ;;
esac
