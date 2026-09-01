#!/bin/bash
# TV screen control for idle blanking (swayidle) and manual use.
#
# The TV is the thing that sleeps; the GPU never stops driving the link.
# No DPMS anywhere: a dpms-on dispatch forces a modeset, and on FRL (4K120
# 10-bit, since HDR) that modeset is a one-shot link training the nvidia
# driver never retries -- one lost race against a sleepy TV receiver latches
# the desktop at 60 Hz until reboot (NVIDIA bug 5649321). Even a redundant
# dpms-on against a lit display cycles the output (observed 2026-08-31: the
# dispatch itself flipped dpmsStatus and caused a visible dim seconds after
# the TV had already shown picture). power_off keeps HPD up (verified: the
# connector never leaves "connected", hyprglaze keeps its pid), so waking is
# the TV re-syncing to a signal that never stopped.
#
# History: DPMS blanking was only ever the workaround for having no TV
# control. The API pairing (2026-07-22) removed that constraint; the DPMS era
# ended 2026-08-31. If the desktop is ever genuinely dark with the TV on and
# verified (shouldn't happen without DPMS in play), the rescue is
#   hyprctl dispatch 'hl.dsp.dpms({ mode = "on" })'
# or a VT switch. NOT turn_screen_off on the idle path -- it drops HPD and
# wedged Hyprland on 2026-07-23.

TV_IP="192.168.11.243"
TV_MAC="84:a3:29:ad:42:5c"
LG=("$HOME/.local/share/lgtv/venv/bin/bscpylgtvcommand" -p "$HOME/.config/lgtv/keys.sqlite" "$TV_IP")

LOG="$HOME/.config/lgtv/screen.log"
log() { printf '%s %s\n' "$(date '+%F %T')" "$*" >> "$LOG"; }
log "invoked: $1"

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
    if timeout 10 "${LG[@]}" power_off >> "$LOG" 2>&1; then
      log "off: tv power_off ok (link kept up)"
    else
      # No DPMS fallback: blanking via dpms is what risks the 60 Hz latch.
      # An unreachable TV just stays lit; rare, and strictly better.
      log "off: tv api unreachable, TV LEFT ON"
    fi
    ;;
  on)
    T0=$SECONDS
    # wol is a no-op if the TV is already awake
    wol "$TV_MAC" >> "$LOG" 2>&1
    for wait in $(seq 1 40); do
      timeout 2 "${LG[@]}" get_power_state >> /dev/null 2>&1 \
        && { log "on: tv api up after ${wait} probe(s), $((SECONDS-T0))s"; break; }
      [ $((wait % 10)) -eq 0 ] && wol "$TV_MAC" >> "$LOG" 2>&1
      sleep 1
    done

    for attempt in 1 2 3 4 5; do
      # The TV re-syncs to the live signal on its own; attempts exist only to
      # verify pixels and escalate if the receiver comes up black. The power
      # cycle is the one escalation ever measured to fix a black link.
      if [ "$attempt" = 4 ]; then
        log "on: escalating - tv power cycle"
        timeout 10 "${LG[@]}" power_off >> "$LOG" 2>&1; sleep 6
        wol "$TV_MAC" >> "$LOG" 2>&1; sleep 12
        timeout 10 "${LG[@]}" set_input HDMI_4 >> "$LOG" 2>&1; sleep 3
      fi

      tv_sees_picture
      case $? in
        0) # The wake's FRL renegotiation briefly removes the output, which
           # kills programs whose surfaces lived on it (observed: hyprglaze
           # exits quietly; lastshell heals itself via Variants). Respawn
           # the wallpaper if the wake orphaned it.
           pgrep -x hyprglaze >/dev/null || { setsid hyprglaze >/dev/null 2>&1 & log "on: respawned hyprglaze (output cycle killed it)"; }
           if hyprctl monitors | grep -q '@119'; then
             log "on: verified picture (attempt $attempt, $((SECONDS-T0))s)"
           else
             # Real picture but the desktop is limping at 60 Hz; nothing short
             # of a reboot recovers it. Be loud instead of silently degraded.
             log "on: verified picture BUT STUCK AT 60HZ - reboot needed for 120 (attempt $attempt, $((SECONDS-T0))s)"
             "$HOME/.claude/bin/claude-speak" --kind error "Display woke at sixty hertz. Reboot needed for one twenty." 2>/dev/null
           fi
           exit 0 ;;
        2) if [ "$attempt" = 5 ]; then
             log "on: tv api never became verifiable - accepting blind"
             exit 0
           fi
           log "on: attempt $attempt - tv api unreachable, retrying"
           sleep 3 ;;
        *) log "on: attempt $attempt - TV SHOWS BLACK, waiting for resync"
           sleep 3 ;;
      esac
    done
    log "on: FAILED - TV up but showing black; rescue: hyprctl dispatch dpms on, or VT switch"
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
