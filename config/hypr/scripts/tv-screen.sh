#!/bin/bash
# TV power for deskpresence (and tv-watchdog.sh if deskpresence is dead).
#
# The TV is the thing that sleeps; the GPU never stops driving the link.
# No DPMS anywhere: a dpms-on modeset on FRL (4K120 10-bit) is a one-shot link
# training the nvidia driver never retries, and losing it latches the desktop
# at 60 Hz until reboot (NVIDIA bug 5649321). Waking is the TV re-syncing plus
# a compositor output remove/re-add, which programs on the output must survive.
#
# Transport is LG IP Control on 9761 (lg-ipctl.py), since 2026-10-01. The webOS
# SSAP API (bscpylgtv, 3000/3001) it replaced rate-limited us ("Try Again
# Later"), failed 127 power_offs in three weeks, and wedged outright on
# 2026-09-30. IP Control is one TCP line and ~3x faster. It also tells the
# states apart on its own (measured 2026-10-01, cross-checked against SSAP):
#   on       CURRENT_APP answers "APP:... Signal:Yes"; POWER off answers OK
#   standby  CURRENT_APP answers with an EMPTY reply; POWER off answers NG
#   asleep   9761 refuses and ping is silent
# "It replied" is not "it is on": v1 made that mistake, read a dark TV as
# lit, never marked it off, and so never woke it again (2026-10-01 10:02).
# The SSAP-era version, with its screenshot verify and power-cycle escalation,
# is tv-screen.sh.bak-pressap-*. Rescue if the desktop is ever dark with the
# TV on: hyprctl dispatch 'hl.dsp.dpms({ mode = "on" })', or a VT switch.

TV_IP="192.168.11.243"
TV_MAC="84:a3:29:ad:42:5c"
IPCTL="$HOME/.config/hypr/scripts/lg-ipctl.py"

LOG="$HOME/.config/lgtv/screen.log"
log() { printf '%s %s\n' "$(date '+%F %T')" "$*" >> "$LOG"; }
log "invoked: $1"

# The TV state this script last achieved ("on"/"off"). deskpresence reads it
# back to decide whether the desk and the TV agree; keep it honest.
STATE="$HOME/.config/lgtv/state"
mark() { printf '%s\n' "$1" > "$STATE"; }
[ "$1" = state ] && { cat "$STATE" 2>/dev/null; exit 0; }

# Serialize every TV action. Two callers racing could land `off`'s POWER off
# AFTER `on`'s WOL and shut the TV down with the user sitting in front of it.
LOCK="${XDG_RUNTIME_DIR:-/tmp}/tv-screen.lock"
exec 9>"$LOCK"
flock -w 240 9 || { log "$1: gave up waiting for the lock (240s)"; exit 1; }

# Exit codes, read by deskpresence (the only caller that decides):
#   0 done, and confirmed
#   1 failed: the TV may be lit, or is on with no HDMI signal
#   2 abandoned: deskpresence's decision changed while this ran
#   3 unconfirmed: the TV cannot be reached and the state is unknown
# The state file holds only confirmed states: on, off, on-unverified, unknown.

# tv: sets TV to what the TV is doing -- on, standby, asleep, or unknown (it
# answers ping but 9761 will not connect) -- and TV_APP to the CURRENT_APP
# reply. Globals, not stdout: $(tv) would lose TV_APP in the subshell.
# Probes wait 2 s for a reply, not lg-ipctl's 5: a lit TV answers in ~60 ms,
# and a standby TV never does. `tv quick` waits 0.8 s and skips the ping, for
# the wake loop: there an unanswered probe is just "not yet" (TV=dark).
TV="" TV_APP=""
tv() {
  local wait=2; [ "$1" = quick ] && wait=0.8
  TV_APP=$(LG_IPCTL_TIMEOUT=$wait timeout 8 "$IPCTL" CURRENT_APP 2>&1)
  case $? in
    0|1) [[ "$TV_APP" == APP:* ]] && TV=on || TV=standby ;;
    *) if [ "$1" = quick ]; then TV=dark
       else ping -c 1 -W 1 "$TV_IP" >/dev/null 2>&1 && TV=unknown || TV=asleep; fi ;;
  esac
  [[ "$TV" == on && "$TV_APP" == *"Signal:Yes"* ]] && note signal || note "$TV"
}

# hdmi: whether Hyprland has the TV's output right now. A wake from deep
# standby drops HPD and reconnects ~10 s later (the TV booting its receiver);
# the reconnect is the modeset, i.e. the picture. IP Control reports the
# same thing 10-25 s later still, once webOS has booted, so for a wake the
# output coming back is the faster truth.
hdmi() { hyprctl -j monitors 2>/dev/null | jq -e 'any(.[]; .name == "HDMI-A-1")' >/dev/null 2>&1; }

# A wake's timeline, appended to its result line: each state change with the
# seconds since the start, e.g. "wol@0.0 standby@2.1 on@31.4 signal@33.0".
# Tells a slow TV boot apart from slow polling without guessing.
TRACE="" TRACE_LAST="" T0US=${EPOCHREALTIME/./}
note() {
  [ "$1" = "$TRACE_LAST" ] && return
  local ms=$(( (${EPOCHREALTIME/./} - T0US) / 1000 ))
  TRACE+=" $1@$((ms / 1000)).$((ms % 1000 / 100))"
  TRACE_LAST=$1
}

# A WOL that lands while the TV is still powering down can leave webOS half
# up (2026-09-30 17:28: an "on" 9 s after an "off", SSAP dead for hours). `on`
# holds its WOL until MIN_OFF_GAP seconds after the last POWER off.
OFF_STAMP="${XDG_RUNTIME_DIR:-/tmp}/tv-screen.last-off"
MIN_OFF_GAP=${MIN_OFF_GAP:-20}

# wanted_other ACTION: deskpresence now wants something else. Its status is
# the only authority on what the TV should be; a stale or older status
# (no "want") never abandons.
DP_STATUS="$HOME/.local/state/deskpresence/status.json"
wanted_other() {
  [ -f "$DP_STATUS" ] || return 1
  [ $(( $(date +%s) - $(stat -c %Y "$DP_STATUS") )) -le 15 ] || return 1
  jq -e --arg a "$1" '(.want // "") as $w | $w != "" and $w != $a' "$DP_STATUS" >/dev/null 2>&1
}

case "$1" in
  off)
    tv
    case "$TV" in
      standby|asleep) log "off: already dark ($TV)"; mark off; exit 0 ;;
      unknown) log "off: TV answers ping but not IP Control ($TV_APP) - may be lit"; mark unknown; exit 3 ;;
    esac
    reply=$(timeout 8 "$IPCTL" "POWER off" 2>&1)
    if [ "$reply" != OK ]; then
      log "off: POWER off failed ($reply) - TV may be lit"
      exit 1
    fi
    touch "$OFF_STAMP"
    # CURRENT_APP goes silent within ~2 s of an accepted POWER off.
    for i in 1 2 3 4 5; do
      sleep 1
      tv
      [ "$TV" != on ] && { log "off: confirmed ($TV, ${i}s)"; mark off; exit 0; }
    done
    log "off: TV LEFT ON - still answering 5s after POWER off"
    exit 1
    ;;
  on)
    T0=$SECONDS
    # Safety net: respawn the wallpaper if the wake's output cycle killed it
    # (it survives that on its own since 2026-09-12). 9>&- is load-bearing:
    # flock is held by the open file description, so a long-lived child that
    # inherits fd 9 keeps the lock forever (2026-09-09: TV never slept again).
    trap 'pgrep -x hyprglaze >/dev/null || { setsid hyprglaze 9>&- >/dev/null 2>&1 & log "on: respawned hyprglaze (it was not running)"; }' EXIT

    # Hold the wake right after a POWER off (the wedge above). The stamp says
    # so without touching the network.
    if [ -f "$OFF_STAMP" ]; then
      gap=$(( MIN_OFF_GAP - ($(date +%s) - $(stat -c %Y "$OFF_STAMP")) ))
      if [ "$gap" -gt 0 ]; then
        log "on: POWER off too recent; holding the wake ${gap}s"
        for (( ; gap > 0; gap-- )); do
          wanted_other on && { log "on: abandoned, deskpresence wants the TV off"; exit 2; }
          sleep 1
        done
      fi
    fi

    # WOL before any probe: a dark TV makes a probe wait out its timeout, and
    # probing first delayed every wake by ~5 s. WOL to a lit TV does nothing.
    # Then poll fast, resending WOL every 3 s until the TV says it is on,
    # until either the TV reports its HDMI signal or Hyprland gets the
    # output back after the wake dropped it. Whichever comes first.
    wol "$TV_MAC" >/dev/null; note wol
    next_wol=$((SECONDS + 3)) deadline=$((SECONDS + 90)) dropped=""
    while :; do
      tv quick
      [ "$TV" = on ] && [[ "$TV_APP" == *"Signal:Yes"* ]] && break
      if hdmi; then
        [ -n "$dropped" ] && { note picture; break; }
      elif [ -z "$dropped" ]; then
        dropped=1; note hdmi-dropped
      fi
      wanted_other on && { log "on: abandoned, deskpresence wants the TV off [${TRACE# }]"; exit 2; }
      if [ "$TV" != on ] && [ "$SECONDS" -ge "$next_wol" ]; then
        wol "$TV_MAC" >/dev/null; next_wol=$((SECONDS + 3))
      fi
      if [ "$SECONDS" -ge "$deadline" ]; then
        if [ "$TV" = on ]; then
          log "on: TV up but no HDMI signal ($TV_APP) [${TRACE# }]"
          mark on-unverified; exit 1
        fi
        tv
        log "on: TV never came up ($TV, $((SECONDS-T0))s) [${TRACE# }]"
        mark unknown; exit 3
      fi
      sleep 0.3
    done

    # The refresh rate as a number; if hyprctl cannot say, that is unknown,
    # never "stuck at 60 Hz". A 60 Hz latch survives everything but a reboot.
    rr=$(hyprctl -j monitors 2>/dev/null | jq -r '[.[].refreshRate] | max // empty' 2>/dev/null)
    if [ -n "$rr" ] && ! awk -v r="$rr" 'BEGIN { exit !(r >= 100) }'; then
      log "on: up BUT STUCK AT 60HZ - reboot needed for 120 ($((SECONDS-T0))s) [${TRACE# }]"
      "$HOME/.claude/bin/claude-speak" --kind error "Display woke at sixty hertz. Reboot needed for one twenty." 2>/dev/null
    else
      log "on: up with signal ($((SECONDS-T0))s) [${TRACE# }]"
    fi
    mark on; exit 0
    ;;
  *)
    echo "usage: tv-screen.sh on|off|state" >&2
    exit 2
    ;;
esac
