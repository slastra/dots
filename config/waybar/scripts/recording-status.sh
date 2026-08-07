#!/bin/bash
# Waybar module script for recording indicator
# Outputs JSON: shows indicator only when recording

# Check if gpu-screen-recorder is actually running (process name truncated to 16 chars)
if pgrep -x gpu-screen-reco > /dev/null 2>&1; then
    echo '{"text": "󰑊 REC", "class": "recording", "tooltip": "Click to stop recording"}'
else
    # Empty text hides the module
    echo '{"text": "", "class": ""}'
fi
