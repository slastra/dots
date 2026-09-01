#!/bin/bash
# Nightly OLED Pixel Cleaning for the LG B4, 4am timer (tv-pixel-refresh.timer).
#
# History: v1 dropped the TV into standby and trusted webOS to run its own
# compensation cycle "when due". Under the DPMS-free architecture (2026-08-31)
# the TV reaches real standby at every idle blank, so that version became a
# no-op; worse, its "is the screen idle" guard read dpmsStatus, which is now
# always 1. This version explicitly TRIGGERS Pixel Cleaning by driving the
# settings menu over the remote-key API — the sequence Shaun dictated and we
# verified by screenshot on 2026-08-31:
#   MENU, RIGHT x3, ENTER, (settle), DOWN x2, ENTER, DOWN x4, ENTER,
#   DOWN, ENTER, ENTER, DOWN, ENTER  -> lands on the Yes/No confirm
#   ENTER on Yes                     -> TV turns off, cleans ~10 min,
#                                       then TURNS ITSELF BACK ON.
#
# Determinism notes, each learned the hard way:
# - The quick bar's initial focus is only predictable from a clean state
#   (Dark Room Mode, leftmost). A blind ENTER once cycled Dark Room to Lv2.
# - The settings panel REMEMBERS its last category; a stale panel walked the
#   same key sequence into Support > Software Update (firmware is frozen —
#   never go near "Check for Updates"). Waking fresh from standby + BACK
#   presses first is the mitigation.
# - EXIT is NOT a safe "close menus" key: it leaves the input for the webOS
#   home screen. Use BACK.
# - A screenshot of the confirm dialog is saved before the final ENTER as an
#   audit trail (~/.config/lgtv/pixel-clean-audit.jpg), since this runs blind.
# - Turning the TV on mid-clean aborts it; user activity waking the TV via
#   swayidle does exactly that. Acceptable: user presence wins at 4am.
#
# Guard: skips unless the TV is genuinely in standby (nobody watching). The
# TV being off is also what makes the menu state deterministic after WOL.

TV_IP="192.168.11.243"
TV_MAC="84:a3:29:ad:42:5c"
PY="$HOME/.local/share/lgtv/venv/bin/python"
KEYS="$HOME/.config/lgtv/keys.sqlite"
LG=("$HOME/.local/share/lgtv/venv/bin/bscpylgtvcommand" -p "$KEYS" "$TV_IP")
LOG="$HOME/.config/lgtv/screen.log"
AUDIT="$HOME/.config/lgtv/pixel-clean-audit.jpg"
log() { printf '%s %s\n' "$(date '+%F %T')" "$*" >> "$LOG"; }

state=$(timeout 10 "${LG[@]}" get_power_state 2>/dev/null)
if [[ "$state" == *"'state': 'Active'"* ]]; then
  log "pixel-clean: skipped - tv is Active (in use)"
  exit 0
fi

log "pixel-clean: waking tv for cleaning run"
wol "$TV_MAC" >> "$LOG" 2>&1
for i in $(seq 1 40); do
  timeout 2 "${LG[@]}" get_power_state >/dev/null 2>&1 && break
  [ $((i % 10)) -eq 0 ] && wol "$TV_MAC" >> "$LOG" 2>&1
  sleep 1
done
if ! timeout 5 "${LG[@]}" get_power_state >/dev/null 2>&1; then
  log "pixel-clean: FAILED - tv never answered WOL"
  exit 1
fi
sleep 8  # let webOS finish coming up before driving menus

"$PY" - "$TV_IP" "$KEYS" "$AUDIT" <<'PYEOF' >> "$LOG" 2>&1
import asyncio, sys, urllib.request, ssl
from bscpylgtv import WebOsClient
ip, keys, audit = sys.argv[1], sys.argv[2], sys.argv[3]
async def main():
    c = await WebOsClient.create(ip, key_file_path=keys, states=[])
    await c.connect()
    async def press(k, d=0.8):
        await c.button(k); await asyncio.sleep(d)
    # clear any lingering overlay/panel; BACK is a no-op on live video
    await press('BACK', 1.0); await press('BACK', 1.0)
    await press('MENU', 1.5)
    for _ in range(3): await press('RIGHT')
    await press('ENTER', 3.0)
    for _ in range(2): await press('DOWN')
    await press('ENTER', 1.5)
    for _ in range(4): await press('DOWN')
    await press('ENTER', 1.5)
    await press('DOWN')
    await press('ENTER', 1.5)
    await press('ENTER', 1.5)
    await press('DOWN')
    await press('ENTER', 2.0)
    # audit shot of what we are about to confirm
    try:
        r = await c.take_screenshot()
        uri = r.get('imageUri')
        if uri:
            ctx = ssl.create_default_context(); ctx.check_hostname=False; ctx.verify_mode=ssl.CERT_NONE
            open(audit,'wb').write(urllib.request.urlopen(uri, timeout=8, context=ctx).read())
    except Exception as e:
        print('audit screenshot failed:', e)
    await press('ENTER', 1.0)  # Yes - start cleaning, TV powers off
    await c.disconnect()
asyncio.run(main())
PYEOF

sleep 25
if timeout 8 "${LG[@]}" get_power_state 2>/dev/null | grep -q "'Active'"; then
  log "pixel-clean: FAILED - tv still Active after confirm; returning it to standby (see $AUDIT)"
  timeout 10 "${LG[@]}" power_off >> "$LOG" 2>&1
  exit 1
fi
log "pixel-clean: started - tv off for ~10 min, will self-power-on"

# The clean ends with the TV turning itself ON. Wait for that, then put it
# back to standby so 4:20am doesn't leave a lit OLED playing to an empty room.
for i in $(seq 1 40); do  # up to 20 min
  sleep 30
  if timeout 5 "${LG[@]}" get_power_state 2>/dev/null | grep -q "'Active'"; then
    sleep 10
    timeout 10 "${LG[@]}" power_off >> "$LOG" 2>&1
    log "pixel-clean: complete - tv self-powered-on after $((i*30))s, returned to standby"
    exit 0
  fi
done
log "pixel-clean: tv did not self-power-on within 20 min (may have gone straight to standby) - done"
