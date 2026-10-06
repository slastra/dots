pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import ".."  // root module: Host

// Desk presence, from deskpresence's status snapshot (written tmp+rename, so
// every change is one reload). The daemon owns the sensor and the TV; this
// only mirrors its verdict.
Singleton {
    id: root

    property bool loaded: false
    property bool present: false
    property bool known: false
    property bool sensorOk: false
    property bool busy: false
    property bool paused: false
    property string tv: ""          // "on" | "off" | "on-unverified" | "unknown" | ""
    // The input layer under the radar (hypridle): "active", "quiet", "idle",
    // "away" (an hour without input: the TV is off whatever the radar says)
    // or "unknown" (hypridle not running). want is the daemon's decision.
    property string input: ""
    property string want: ""
    property int state: 0           // sensor target: 0 none 1 moving 2 static 3 both
    property int distance: 0        // cm, closest reported target
    property double since: 0        // ms epoch of the last verdict flip
    property real fade: 0           // 0..1: how far the absence timer has run into its warning window
    property int fadeMs: 5000       // length of that window (the daemon's -fade), so the shade can run it in one motion
    // last 60 s of the signal the verdict is made from: max moving energy in
    // the near gates per 500 ms bin, oldest first, plus the verdict per bin
    property var history: []
    property var historyPresent: []
    property int threshold: 0
    // history.json is rewritten twice a second and only feeds the popout
    // graph, so it is watched only while a popout that draws it is open
    // (ref-counted: one chip per screen)
    property int historyWatchers: 0

    readonly property string stateWord:
        state === 1 ? "moving" : state === 2 ? "static" : state === 3 ? "both" : "none"

    // Office Light follows presence unless this says "off" (read by
    // ~/.config/deskpresence/light-hook on every on|off; persists across reboots)
    property bool lightFollow: true
    readonly property string lightFlag: Quickshell.env("HOME") + "/.local/state/deskpresence/light-follow"
    // audio fade + MPRIS pause, gated inside the daemon by its -audio-flag file
    property bool audioFollow: true
    readonly property string audioFlag: Quickshell.env("HOME") + "/.local/state/deskpresence/audio-follow"
    // "keep awake": a timed pause the daemon expires itself; ms epoch, 0 = none
    property double holdUntil: 0
    // away timer, live from the daemon; the slider writes it back through
    // `deskpresence absence Ns` (debounced, so a drag is one write)
    property int absenceSecs: 0
    readonly property int absenceMin: 10
    // the daemon clamps to 10-60 s: radar noise refreshes presence about
    // once a minute, so a longer timer never expires in an empty room
    readonly property int absenceMax: 60
    property int pendingAbsence: 0
    readonly property string deskpresence: Quickshell.env("HOME") + "/go/bin/deskpresence"

    readonly property string pauseFile: Quickshell.env("XDG_RUNTIME_DIR") + "/deskpresence.pause"

    function togglePause() {
        Quickshell.execDetached(["sh", "-c",
            `if [ -e "${pauseFile}" ]; then rm -f "${pauseFile}"; else : > "${pauseFile}"; fi`])
    }

    // flip the flag; on re-enable, bring the light in line with the verdict
    // right away instead of waiting for the next presence change
    function toggleLight() {
        if (!Host.desk) return
        const next = lightFollow ? "off" : "on"
        lightFollow = next !== "off"   // our own write does not re-emit loaded
        lightFlagView.setText(next)
        if (next === "on" && known)
            Quickshell.execDetached([Quickshell.env("HOME") + "/.config/deskpresence/light-hook", present ? "on" : "off"])
    }

    // status.json is the source of truth for audioFollow (the daemon reads
    // the flag within a tick); the flag file is only written here
    function toggleAudio() {
        audioFollow = !audioFollow
        audioFlagView.setText(audioFollow ? "on" : "off")
    }

    function setAbsence(secs) {
        // 5 s steps; `deskpresence hold` is the film-night escape hatch now
        const v = Math.max(absenceMin, Math.min(absenceMax, secs))
        pendingAbsence = Math.round(v / 5) * 5
        absenceSecs = pendingAbsence   // shown at once; status.json confirms within a tick
        absenceWrite.restart()
    }
    Timer {
        id: absenceWrite
        interval: 150
        onTriggered: Quickshell.execDetached([root.deskpresence, "absence", `${root.pendingAbsence}s`])
    }

    // hold(0) releases; status.json carries hold_until back within a tick
    function hold(minutes) {
        Quickshell.execDetached([deskpresence, "hold", minutes > 0 ? `${minutes}m` : "off"])
    }

    function openView() {
        Quickshell.execDetached(["xdg-open", "http://127.0.0.1:7391/"])
    }

    FileView {
        id: lightFlagView
        path: Host.desk ? root.lightFlag : ""
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.lightFollow = text().trim() !== "off"
    }

    FileView { id: audioFlagView; path: root.audioFlag }

    FileView {
        path: Quickshell.env("HOME") + "/.local/state/deskpresence/history.json"
        watchChanges: root.historyWatchers > 0
        onWatchChangesChanged: if (watchChanges) reload()
        onFileChanged: reload()
        onLoaded: parse()
        function parse() {
            try {
                const j = JSON.parse(text())
                root.history = j.near ?? []
                root.historyPresent = j.present ?? []
                root.threshold = j.threshold ?? 0
            } catch (e) { /* mid-write */ }
        }
    }

    FileView {
        path: Quickshell.env("HOME") + "/.local/state/deskpresence/status.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: parse()
        function parse() {
            try {
                const j = JSON.parse(text())
                root.present = !!j.present
                root.known = !!j.known
                root.sensorOk = !!j.sensor_ok
                root.busy = !!j.busy
                root.paused = !!j.paused
                root.holdUntil = j.hold_until ?? 0
                if (!absenceWrite.running) root.absenceSecs = Math.round((j.rule?.absence_ms ?? 0) / 1000)
                root.audioFollow = j.audio_follow ?? true
                root.tv = j.tv ?? ""
                root.input = j.input ?? ""
                root.want = j.want ?? ""
                root.state = j.state ?? 0
                root.distance = j.distance ?? 0
                root.since = j.since ?? 0
                root.fadeMs = j.rule?.fade_ms ?? 5000   // before fade: DimOverlay reads it on the change
                root.fade = j.fade ?? 0
                root.loaded = true
            } catch (e) { /* mid-write */ }
        }
    }
}
