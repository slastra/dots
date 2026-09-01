#!/bin/bash
# Screen capture menu using rofi
# Screenshots: grim + slurp + satty
# Recording: gpu-screen-recorder + recording-border overlay

VIDEOS_DIR="$HOME/Videos"
PID_FILE="/tmp/gpu-screen-recorder.pid"
BORDER_PID_FILE="/tmp/recording-border.pid"
BORDER_SCRIPT="$HOME/.config/hypr/scripts/recording-border.py"
MONITOR="HDMI-A-1"

# Rosé Pine colors for slurp
SLURP_ARGS='-b 191724cc -c eb6f92ff -w 2'

# Check if currently recording
is_recording() {
    pgrep -x gpu-screen-reco > /dev/null 2>&1
}

# Get active window geometry in X,Y WxH format
get_active_window_geometry() {
    hyprctl activewindow -j | jq -r '"\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"'
}

# Wait for rofi to be gone from the screen, not merely gone from the layer list.
#
# Hyprland drops a closing layer out of `hyprctl layers` as soon as the client
# destroys the surface (measured: 11ms) but keeps compositing a fading snapshot
# for the whole layersOut animation after that. Polling the layer list alone
# returns while rofi is still visibly on screen, so grim captures a ghost of the
# menu. Only Full Screen and Window hit this: Region and Scan run slurp first,
# which takes far longer than the fade.
#
# The fade duration is read from the compositor rather than hardcoded, so
# retuning `layersOut` in hyprland.lua does not silently reintroduce this.
# Hyprland's animation speed unit is 100ms.
#
# Waiting for the pixels to settle instead is not an option here: the wallpaper
# is animated, so the screen never stops changing.
rofi_fade_ms() {
    local speed
    speed=$(hyprctl -j animations 2>/dev/null |
        jq -r '.[0][] | select(.name=="layersOut" and .enabled) | .speed' 2>/dev/null | head -1)
    [[ -z "$speed" || "$speed" == "null" ]] && { echo 0; return; }
    # +40ms so the final frame has been presented, not just computed.
    awk -v s="$speed" 'BEGIN { printf "%d", s * 100 + 40 }'
}

wait_for_rofi_close() {
    while hyprctl layers -j | jq -e '.. | select(.namespace? == "rofi")' > /dev/null 2>&1; do
        sleep 0.01
    done
    local ms
    ms=$(rofi_fade_ms)
    (( ms > 0 )) && sleep "$(awk -v m="$ms" 'BEGIN { print m / 1000 }')"
}

# Stop border overlay
stop_border() {
    if [[ -f "$BORDER_PID_FILE" ]]; then
        local border_pid
        border_pid=$(cat "$BORDER_PID_FILE")
        kill "$border_pid" 2>/dev/null
        rm -f "$BORDER_PID_FILE"
    fi
    pkill -f "recording-border.py" 2>/dev/null
}

# Start border overlay for region recording (expects logical/unscaled WxH+X+Y)
start_border() {
    local region="$1"
    LD_PRELOAD=/usr/lib/libgtk4-layer-shell.so setsid python3 "$BORDER_SCRIPT" "$region" > /dev/null 2>&1 &
    local pid=$!
    sleep 0.2
    echo "$pid" > "$BORDER_PID_FILE"
}

# Convert X,Y WxH to WxH+X+Y (no scaling, for overlay)
convert_to_region_format() {
    local geom="$1"
    local xy=$(echo "$geom" | cut -d' ' -f1)
    local wh=$(echo "$geom" | cut -d' ' -f2)
    local x=$(echo "$xy" | cut -d',' -f1)
    local y=$(echo "$xy" | cut -d',' -f2)
    echo "${wh}+${x}+${y}"
}

# Stop recording
stop_recording() {
    if is_recording; then
        pkill -SIGINT -f gpu-screen-recorder
        rm -f "$PID_FILE"
        stop_border
        notify-send "Recording" "Recording saved to $VIDEOS_DIR"
    fi
}

# Get active monitor geometry in X,Y WxH format (logical pixels)
get_monitor_geometry() {
    hyprctl monitors -j | jq -r '.[] | select(.focused) | "\(.x),\(.y) \(.width/.scale|round)x\(.height/.scale|round)"'
}

# Screenshot functions (grim -g captures in logical coordinate space with proper color management)
screenshot_fullscreen() {
    local geometry
    geometry=$(get_monitor_geometry)
    grim -g "$geometry" - | satty --filename - --copy-command "wl-copy"
}

screenshot_region() {
    local geometry
    geometry=$(slurp $SLURP_ARGS) || return
    grim -g "$geometry" - | satty --filename - --copy-command "wl-copy"
}

scan_region() {
    local geometry output codes
    geometry=$(slurp $SLURP_ARGS) || return
    # zbarimg output is TYPE:data per line (e.g. UPC-A:012345678905)
    output=$(grim -g "$geometry" - | zbarimg -q -)
    if [[ -n "$output" ]]; then
        codes=$(sed 's/^[^:]*://' <<< "$output")
        printf '%s' "$codes" | wl-copy
        notify-send "Barcode" "Copied: $(sed 's/:/ /' <<< "$output")"
    else
        notify-send "Barcode" "No barcode found"
    fi
}

screenshot_window() {
    local geometry
    geometry=$(get_active_window_geometry)
    [[ -n "$geometry" ]] && grim -g "$geometry" - | satty --filename - --copy-command "wl-copy"
}

# Recording helpers
start_recording_monitor() {
    local monitor="$1"
    local filename="$VIDEOS_DIR/recording_$(date +%Y%m%d_%H%M%S).mp4"

    setsid gpu-screen-recorder -w "$monitor" -f 60 -q very_high -c mp4 -o "$filename" > /dev/null 2>&1 &
    local pid=$!
    echo "$pid" > "$PID_FILE"

    notify-send "Recording" "Started recording"
}

start_recording_region() {
    local geometry="$1"  # X,Y WxH format (logical/unscaled)
    local filename="$VIDEOS_DIR/recording_$(date +%Y%m%d_%H%M%S).mp4"

    # Both the overlay and gpu-screen-recorder expect logical/unscaled
    # coordinates. gsr's -region is documented as slurp-compatible, and slurp
    # already outputs logical coords, so no scaling is applied.
    local region=$(convert_to_region_format "$geometry")
    start_border "$region"

    setsid gpu-screen-recorder -w region -region "$region" -f 60 -q very_high -c mp4 -o "$filename" > /dev/null 2>&1 &
    local pid=$!
    echo "$pid" > "$PID_FILE"

    notify-send "Recording" "Started recording"
}

# Recording functions
record_fullscreen() {
    if is_recording; then
        notify-send "Recording" "Already recording!"
        return
    fi
    start_recording_monitor "$MONITOR"
}

record_region() {
    if is_recording; then
        notify-send "Recording" "Already recording!"
        return
    fi

    geometry=$(slurp $SLURP_ARGS)
    [[ -z "$geometry" ]] && return
    start_recording_region "$geometry"
}

record_window() {
    if is_recording; then
        notify-send "Recording" "Already recording!"
        return
    fi

    geometry=$(get_active_window_geometry)
    [[ -z "$geometry" ]] && return
    start_recording_region "$geometry"
}

# Build menu options
build_menu() {
    echo "󰊓  Full Screen 󰁔  Image"
    echo "󰊓  Full Screen 󰁔  Video"
    echo "󰩬  Region 󰁔  Image"
    echo "󰩬  Region 󰁔  Video"
    echo "󰩬  Region 󰁔  Scan Barcode"
    echo "󰖲  Window 󰁔  Image"
    echo "󰖲  Window 󰁔  Video"
}

# CLI subcommand path (used by lastshell's capture modal — rofi menu below
# stays as fallback). "stop" is also safe to call while not recording.
if [[ -n "${1:-}" ]]; then
    case "$1" in
        stop)              stop_recording ;;
        fullscreen-image)  screenshot_fullscreen ;;
        fullscreen-video)  record_fullscreen ;;
        region-image)      screenshot_region ;;
        region-video)      record_region ;;
        region-scan)       scan_region ;;
        window-image)      screenshot_window ;;
        window-video)      record_window ;;
        *) echo "unknown capture action: $1" >&2; exit 2 ;;
    esac
    exit 0
fi

# If recording, stop it and exit
if is_recording; then
    stop_recording
    exit 0
fi

# Show menu and handle selection
selected=$(build_menu | rofi -dmenu -i -p "󰑋 " -theme ~/.config/rofi/themes/capture.rasi)
[[ -z "$selected" ]] && exit 0

# Wait for rofi to fully disappear before capturing
wait_for_rofi_close

case "$selected" in
    *"Full Screen"*"Image"*)
        screenshot_fullscreen
        ;;
    *"Full Screen"*"Video"*)
        record_fullscreen
        ;;
    *"Region"*"Image"*)
        screenshot_region
        ;;
    *"Region"*"Video"*)
        record_region
        ;;
    *"Region"*"Scan"*)
        scan_region
        ;;
    *"Window"*"Image"*)
        screenshot_window
        ;;
    *"Window"*"Video"*)
        record_window
        ;;
esac
