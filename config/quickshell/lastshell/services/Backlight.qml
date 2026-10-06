pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Panel backlight (the laptop; the desk has none, and brightnessctl there
// falls through to a NIC LED, so `present` gates everything). sysfs never
// fires inotify, but the kernel sends a backlight uevent on every change,
// so a udevadm watch reloads the value: hardware keys, the chip and a bare
// brightnessctl all land here the same way.
//
// Auto mode follows the ambient light sensor through iio-sensor-proxy
// (monitor-sensor --light). Brightness tracks log(lux) along `curve`, plus
// a learned offset: any change that is not auto's own (keys, chip, slider)
// becomes "this much brighter or darker than the curve", saved across runs.
// Auto neither adjusts nor learns while hypridle holds the screen dimmed
// (presence-guard's dim marker) or the panel is off.
Singleton {
    id: root

    property string device: ""
    readonly property bool present: device !== ""
    property int max: 0
    property int raw: 0
    readonly property real frac: max > 0 ? raw / max : 0
    readonly property real step: 0.05
    // the floor keeps the panel lit: 0 turns it fully dark
    readonly property real min: 0.01

    // a change auto did not make: the OSD shows these and only these
    signal userChanged()

    // --- ambient light -----------------------------------------------------
    property bool hasSensor: false
    property real lux: -1           // smoothed; -1 until the first reading
    property bool auto: true
    property real offset: 0         // learned, in brightness fraction
    readonly property bool autoActive: present && hasSensor && auto && lux >= 0

    // log10(lux) -> brightness: dark room, lamp-lit, office, window, daylight
    readonly property var curve: [[0, 0.04], [1, 0.15], [2, 0.40], [3, 0.80], [3.5, 1.0]]
    function curveAt(l) {
        const x = Math.log10(Math.max(0, l) + 1)
        const c = curve
        if (x <= c[0][0]) return c[0][1]
        for (let i = 1; i < c.length; i++) {
            if (x <= c[i][0]) {
                const t = (x - c[i - 1][0]) / (c[i][0] - c[i - 1][0])
                return c[i - 1][1] + t * (c[i][1] - c[i - 1][1])
            }
        }
        return c[c.length - 1][1]
    }
    readonly property real target: Math.max(min, Math.min(1, curveAt(lux) + offset))

    function set(f) {
        f = Math.max(min, Math.min(1, f))
        Quickshell.execDetached(["brightnessctl", "-q", "-c", "backlight", "set", `${Math.round(f * 100)}%`])
    }
    function nudge(delta) { set(frac + delta) }
    function toggleAuto() {
        auto = !auto
        save()
        if (auto) settle.restart()
    }

    // --- held off: hypridle's dim, or the panel off ----------------------
    readonly property string dimMark: Quickshell.env("XDG_RUNTIME_DIR") + "/presence-guard.dim"
    readonly property string screenState: Quickshell.env("HOME") + "/.local/state/laptop-screen/state"
    property bool heldOff: false
    // hypridle's resume restores its saved value just before the marker goes;
    // treat changes for a moment after that as not the user's either
    property double heldUntil: 0
    Process {
        id: holdProbe
        command: ["sh", "-c", `{ [ -e "${root.dimMark}" ] || [ "$(cat "${root.screenState}" 2>/dev/null)" = off ]; } && echo held || echo free`]
        stdout: StdioCollector {
            onStreamFinished: {
                const held = text.trim() === "held"
                if (root.heldOff && !held) root.heldUntil = Date.now() + 3000
                root.heldOff = held
            }
        }
    }
    Timer { interval: 2000; repeat: true; running: root.autoActive; triggeredOnStart: true; onTriggered: holdProbe.running = true }

    // --- applying: a short ramp, marked as auto's own ------------------------
    property double ownUntil: 0     // uevents before this are auto's writes
    property real rampTo: -1
    Timer {
        id: ramp
        interval: 60
        repeat: true
        onTriggered: {
            const d = root.rampTo - root.frac
            if (Math.abs(d) < 0.011) { stop(); return }
            // a quarter of the gap a step, at least 1%: a glide of about a second
            const next = root.frac + Math.sign(d) * Math.max(0.01, Math.abs(d) / 4)
            root.ownUntil = Date.now() + 500
            root.set(next)
        }
    }
    // Lux settles for a beat before auto acts, so a passing shadow or a hand
    // over the sensor does not pump the panel.
    Timer {
        id: settle
        interval: 1500
        onTriggered: {
            if (!root.autoActive || root.heldOff || Date.now() < root.heldUntil) return
            if (Math.abs(root.target - root.frac) < 0.03) return
            root.rampTo = root.target
            ramp.start()
        }
    }
    onTargetChanged: if (autoActive) settle.restart()

    Process {
        running: root.present
        command: ["monitor-sensor", "--light"]
        stdout: SplitParser {
            onRead: line => {
                if (line.includes("Has ambient light sensor")) { root.hasSensor = true; return }
                const m = line.match(/Light changed: ([0-9.]+)/)
                if (!m) return
                const v = parseFloat(m[1])
                // smooth in log space: a lamp switching on still lands fast
                root.lux = root.lux < 0 ? v
                    : Math.pow(10, 0.6 * Math.log10(root.lux + 1) + 0.4 * Math.log10(v + 1)) - 1
            }
        }
    }

    // --- the panel ------------------------------------------------------------
    Process {
        running: true
        command: ["sh", "-c", "ls /sys/class/backlight | head -n1"]
        stdout: StdioCollector { onStreamFinished: root.device = text.trim() }
    }

    FileView {
        path: root.device ? `/sys/class/backlight/${root.device}/max_brightness` : ""
        onLoaded: root.max = parseInt(text()) || 0
    }
    FileView {
        id: cur
        path: root.device ? `/sys/class/backlight/${root.device}/brightness` : ""
        onLoaded: {
            const was = root.raw
            root.raw = parseInt(text()) || 0
            if (was === 0 || root.raw === was) return   // startup read, or no change
            const now = Date.now()
            if (now < root.ownUntil) return             // auto's own ramp
            if (root.heldOff || now < root.heldUntil) return  // hypridle's dim and restore
            ramp.stop()
            root.userChanged()
            // learn: the user's level, as an offset from where auto would sit
            if (root.autoActive) {
                root.offset = Math.max(-0.6, Math.min(0.6, root.frac - root.curveAt(root.lux)))
                root.save()
            }
        }
    }

    Process {
        running: root.present
        command: ["udevadm", "monitor", "--kernel", "--subsystem-match=backlight"]
        stdout: SplitParser { onRead: line => { if (line.includes(" change ")) cur.reload() } }
    }

    // --- persistence: auto on/off and the learned offset ------------------
    readonly property string prefsDir: Quickshell.env("HOME") + "/.local/state/lastshell"
    // made up front: a mkdir alongside the first save would race the write
    onPresentChanged: if (present) Quickshell.execDetached(["mkdir", "-p", prefsDir])
    function save() {
        prefs.setText(JSON.stringify({ auto: root.auto, offset: Math.round(root.offset * 1000) / 1000 }) + "\n")
    }
    FileView {
        id: prefs
        path: root.present ? root.prefsDir + "/brightness.json" : ""
        printErrors: false
        onLoaded: {
            try {
                const j = JSON.parse(text())
                root.auto = j.auto ?? true
                root.offset = j.offset ?? 0
            } catch (e) {}
        }
    }
}
