pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// SDR-in-HDR brightness (Hyprland's per-monitor `sdrbrightness`). One source
// of truth: the value in hyprland.lua. Writing it is also applying it —
// Hyprland live-reloads the config within ~100 ms, no modeset, so there is
// no separate `hyprctl eval` path and no duplicated monitor block here.
Singleton {
    id: root

    readonly property real min: 1.0
    readonly property real max: 3.0
    readonly property real step: 0.05

    property real brightness: 1.0
    // value before the last reset-to-1.0, so a click can bounce back
    property real restore: 1.8

    readonly property string config: Quickshell.env("HOME") + "/.config/hypr/hyprland.lua"

    function set(v) {
        v = Math.round(Math.max(min, Math.min(max, v)) / step) * step
        v = Math.round(v * 100) / 100
        if (v === brightness) return
        if (v === 1.0 && brightness !== 1.0) restore = brightness
        brightness = v
        write.restart()
    }
    function nudge(delta) { set(brightness + delta) }
    function toggle() { set(brightness === 1.0 ? restore : 1.0) }

    // Wheel ticks arrive faster than a config reload is worth; coalesce.
    Timer {
        id: write
        interval: 120
        onTriggered: Quickshell.execDetached(["sed", "-i", "-E",
            `s/^(\\s*sdrbrightness\\s*=\\s*)[0-9.]+/\\1${root.brightness}/`, root.config])
    }

    // Adopt the live value at startup rather than trusting the file.
    Process {
        running: true
        command: ["hyprctl", "monitors", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const v = JSON.parse(text)[0].sdrBrightness
                    if (v > 0) { root.brightness = Math.round(v * 100) / 100; if (v !== 1.0) root.restore = root.brightness }
                } catch (e) {}
            }
        }
    }
}
