#!/bin/bash
# Idle screen blanking for Hyprland: DPMS + WOL via tv-screen.sh, with resume
# retries to survive HDMI 2.1 FRL link training (webOS panel-off API dropped
# HPD and desynced DPMS — see tv-screen.sh header).

TV_SCREEN="$HOME/.config/hypr/scripts/tv-screen.sh"

swayidle -w \
  timeout 600 "$TV_SCREEN off" \
  resume "$TV_SCREEN on" \
  before-sleep "$TV_SCREEN off"
