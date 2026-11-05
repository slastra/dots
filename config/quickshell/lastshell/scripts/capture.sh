#!/bin/bash
# lastshell's capture engine. overlays/CapturePicker.qml (Print) is the menu
# and calls this by subcommand; services/Recorder.qml stops a recording
# through `capture.sh stop`. Run with no argument, it falls back to its old
# rofi menu.
# Screenshots: grim + slurp + satty
# Recording: gpu-screen-recorder + recording-border.py, then capture-sfx.py
# mixes in the click/key sounds and VideoUpload offers to upload it

# this script's directory: recording-border.py and capture-sfx.py live beside it
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

VIDEOS_DIR="$HOME/Videos"
PID_FILE="/tmp/gpu-screen-recorder.pid"
# the file the current recording writes to, for the post-stop upload offer
OUTPUT_FILE="/tmp/gpu-screen-recorder.output"
# What is being recorded, for lastshell's key display (overlays/InputCast.qml):
# {"output": name} or {"region": [x, y, w, h]} in logical layout coords
CAPTURE_STATE="${XDG_RUNTIME_DIR:-/tmp}/lastshell-capture.json"
# Click/key sounds are mixed in after the recording (capture-sfx.py)
SFX_SCRIPT="$SCRIPT_DIR/capture-sfx.py"
# Every recording: desktop audio, plus the first frame's timestamp (VIDEO.ts)
# that capture-sfx.py aligns the sounds by
GSR_ARGS=(-f 60 -q very_high -c mp4 -a default_output -ac aac -write-first-frame-ts yes)
BORDER_PID_FILE="/tmp/recording-border.pid"
BORDER_SCRIPT="$SCRIPT_DIR/recording-border.py"
# the focused output: HDMI-A-1 on the desk, eDP-1 on the laptop
focused_monitor() { hyprctl monitors -j | jq -r '.[] | select(.focused) | .name'; }

# Rosé Pine colors for slurp
SLURP_ARGS='-b 191724cc -c eb6f92ff -w 2'

# Check if currently recording
is_recording() {
    pgrep -x gpu-screen-reco > /dev/null 2>&1
}

# Window recorded by record_window, whose rounding is flattened until stop
FLAT_WINDOW_FILE="/tmp/capture-flat-window"

# Active window box for an on-screen capture, X,Y WxH (logical).
#
# at/size is the window's own box: Hyprland's border sits outside it. But with
# `rounding` on, the corners are cut away inside that box and the border follows
# the curve, so a box capture shows the pink/rose border in all four corners.
# Callers flatten the window (flatten_window) first.
#
# The box is also inset by 1 logical px per side. At a fractional scale (1.25
# on the desk) a window at an odd logical x/y starts mid-pixel, and that edge
# pixel blends in the border (measured at x=974: 1217.5 physical). Even with
# square corners, the full box keeps a faint border line along such edges.
get_active_window_inner_geometry() {
    hyprctl activewindow -j | jq -r '"\(.at[0] + 1),\(.at[1] + 1) \(.size[0] - 2)x\(.size[1] - 2)"'
}

active_window_address() { hyprctl activewindow -j | jq -r '.address // empty'; }

# Hyprland's ext-foreign-toplevel-list identifier is the window's stableId,
# which is what `grim -T` takes.
active_window_toplevel_id() { hyprctl activewindow -j | jq -r '.stableId // empty'; }

# Per-window prop override; value "unset" restores the configured value.
set_window_prop() {
    hyprctl dispatch "hl.dsp.window.set_prop({ window = \"address:$1\", prop = \"$2\", value = \"$3\" })" > /dev/null 2>&1
}

# Square a window's corners so its border lies wholly outside its box. Not
# `decorate 0`: that drops the border width from the layout and the tiled
# window grows 2px per side, so the geometry read before it would be stale.
flatten_window() {
    set_window_prop "$1" rounding 0
    sleep 0.05  # one frame at 60Hz, so the square corners are on screen
}
unflatten_window() { set_window_prop "$1" rounding unset; }

# Hyprland keeps compositing a closing layer for its whole fade-out after the
# client destroyed it: the layer is gone from `hyprctl layers` (measured: 11ms)
# while a fading snapshot is still on screen. A capture taken in that window
# photographs a ghost of the menu, or of slurp's pink selection outline, which
# slurp strokes ON the selection edge so half of it lands inside the region.
#
# The fade duration is read from the compositor rather than hardcoded, so
# retuning the layer animations in hyprland.lua does not silently reintroduce
# this. It is the longer of layersOut and fadeLayersOut (both run on close).
# Hyprland's animation speed unit is 100ms.
#
# Waiting for the pixels to settle instead is not an option here: the wallpaper
# is animated, so the screen never stops changing.
layer_fade_ms() {
    hyprctl -j animations 2>/dev/null | jq -r '
        [.[0][] | select((.name == "layersOut" or .name == "fadeLayersOut") and .enabled) | .speed]
        | (max // 0) * 100 | if . > 0 then . + 40 else 0 end | floor' 2>/dev/null || echo 0
}

# Wait until the layer with this namespace is off the screen, fade included.
wait_for_layer_gone() {
    local ns="$1" ms
    for _ in $(seq 200); do
        hyprctl layers -j | jq -e --arg ns "$ns" '.. | select(.namespace? == $ns)' > /dev/null 2>&1 || break
        sleep 0.01
    done
    ms=$(layer_fade_ms)
    (( ms > 0 )) && sleep "$(awk -v m="$ms" 'BEGIN { print m / 1000 }')"
}

wait_for_rofi_close() { wait_for_layer_gone rofi; }

# slurp, then wait out its fade so its outline is not in what we capture next
select_region() {
    local geometry
    geometry=$(slurp $SLURP_ARGS) || return 1
    [[ -n "$geometry" ]] || return 1
    wait_for_layer_gone selection  # slurp's layer namespace
    echo "$geometry"
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

# Stop recording, mix in the click/key sounds, then offer to upload it
# (lastshell's VideoUpload dialog). gsr finalizes the mp4 (moov atom) after
# SIGINT, so wait for it to exit before touching the file: an unfinished file
# fails to probe. Removing the pid file stops inputcast.py, which closes the
# input log capture-sfx.py reads.
stop_recording() {
    if is_recording; then
        local file
        file=$(cat "$OUTPUT_FILE" 2>/dev/null)
        pkill -SIGINT -f gpu-screen-recorder
        rm -f "$PID_FILE" "$OUTPUT_FILE" "$CAPTURE_STATE"
        stop_border
        if [[ -f "$FLAT_WINDOW_FILE" ]]; then
            unflatten_window "$(cat "$FLAT_WINDOW_FILE")"
            rm -f "$FLAT_WINDOW_FILE"
        fi
        for _ in $(seq 100); do is_recording || break; sleep 0.1; done
        if [[ -s "$file" && -f "$SFX_SCRIPT" ]]; then
            python3 "$SFX_SCRIPT" "$file" 2>/dev/null
        fi
        if [[ -s "$file" ]] && qs -c lastshell ipc call overlays offerUpload "$file" > /dev/null 2>&1; then
            return
        fi
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
    geometry=$(select_region) || return
    grim -g "$geometry" - | satty --filename - --copy-command "wl-copy"
}

scan_region() {
    local geometry output codes
    geometry=$(select_region) || return
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

# Window shots copy the window's own buffer (ext-image-copy-capture through
# grim -T), so no border, rounded corner, shadow or overlapping window can be in
# it, and a translucent window keeps its alpha. If the compositor cannot do
# that, capture its on-screen box with the corners squared for the moment.
screenshot_window() {
    local id addr geometry shot
    id=$(active_window_toplevel_id)
    addr=$(active_window_address)
    [[ -n "$addr" ]] || return
    shot=$(mktemp --tmpdir="${XDG_RUNTIME_DIR:-/tmp}" capture-XXXXXX.png)
    if ! { [[ -n "$id" ]] && grim -T "$id" "$shot" 2>/dev/null; }; then
        flatten_window "$addr"
        geometry=$(get_active_window_inner_geometry)
        grim -g "$geometry" "$shot"
        unflatten_window "$addr"
    fi
    [[ -s "$shot" ]] && satty --filename "$shot" --copy-command "wl-copy"
    rm -f "$shot"
}

# Recording helpers. No "started" toast: it would be in the first seconds of
# the video. lastshell's REC chip shows the state and stops the recording.
start_recording_monitor() {
    local monitor="$1"
    local filename="$VIDEOS_DIR/recording_$(date +%Y%m%d_%H%M%S).mp4"

    printf '{"output":"%s"}\n' "$monitor" > "$CAPTURE_STATE"
    setsid gpu-screen-recorder -w "$monitor" "${GSR_ARGS[@]}" -o "$filename" > /dev/null 2>&1 &
    local pid=$!
    echo "$filename" > "$OUTPUT_FILE"
    echo "$pid" > "$PID_FILE"
}

start_recording_region() {
    local geometry="$1"  # X,Y WxH format (logical/unscaled)
    local filename="$VIDEOS_DIR/recording_$(date +%Y%m%d_%H%M%S).mp4"

    # Both the overlay and gpu-screen-recorder expect logical/unscaled
    # coordinates. gsr's -region is documented as slurp-compatible, and slurp
    # already outputs logical coords, so no scaling is applied.
    local region=$(convert_to_region_format "$geometry")
    start_border "$region"

    local x y w h
    IFS=', x' read -r x y w h <<< "$geometry"
    printf '{"region":[%d,%d,%d,%d]}\n' "$x" "$y" "$w" "$h" > "$CAPTURE_STATE"
    # -w WxH+X+Y: gsr 6 deprecated `-w region -region WxH+X+Y`
    setsid gpu-screen-recorder -w "$region" "${GSR_ARGS[@]}" -o "$filename" > /dev/null 2>&1 &
    local pid=$!
    echo "$filename" > "$OUTPUT_FILE"
    echo "$pid" > "$PID_FILE"
}

# Recording functions
record_fullscreen() {
    if is_recording; then
        notify-send "Recording" "Already recording!"
        return
    fi
    start_recording_monitor "$(focused_monitor)"
}

record_region() {
    if is_recording; then
        notify-send "Recording" "Already recording!"
        return
    fi

    geometry=$(select_region) || return
    start_recording_region "$geometry"
}

record_window() {
    if is_recording; then
        notify-send "Recording" "Already recording!"
        return
    fi

    # gsr has no window source on Wayland short of the portal picker, so this
    # records the window's box. Square its corners for the recording so the
    # border stays outside the box; stop_recording restores them.
    local addr
    addr=$(active_window_address)
    [[ -n "$addr" ]] || return
    flatten_window "$addr"
    echo "$addr" > "$FLAT_WINDOW_FILE"
    geometry=$(get_active_window_inner_geometry)
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
