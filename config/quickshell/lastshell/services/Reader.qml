pragma Singleton
import Quickshell
import Quickshell.Io
import ".."  // root module: EngineProcess
import QtQuick

// The narrator (Super+T): reads the selection, else the clipboard, aloud.
// scripts/reader.py is the engine (the old piper-reader GTK app's speech
// pipeline, headless): Piper or Kokoro renders passages ahead of the
// playhead into an mpv playlist, and terminal-looking text is rewritten for
// speech on OpenRouter first. It starts on the first read and then idles in
// its main loop, waking for nothing, so voices stay warm between reads.
Singleton {
    id: root

    property var voices: []          // [{key, label}]
    property var config: ({})        // {voice, speed, tidy, tidy_available}
    property var state: ({ active: false })

    // Super+T was pressed and the engine hasn't answered yet: the chip shows
    // at once instead of after the first passage renders (~1 s, longer on a
    // cold start). Cleared by the next state, or by a "nothing to read" notice.
    property bool preparing: false
    readonly property bool active: state.active === true || preparing
    readonly property bool finished: state.finished === true
    // no audio yet: before the first passage renders, or when rendering
    // falls behind playback (mpv sits idle until the next file lands)
    readonly property bool starting: preparing || (state.active === true && state.idle === true && !finished)
    readonly property bool playing: state.active === true && !state.paused && !state.idle && !finished
    readonly property real progress: state.total > 0 ? Math.min(1, state.elapsed / state.total) : 0
    readonly property var tidyModes: ["Off", "Auto", "Always"]
    readonly property real speed: config.speed ?? 1

    function send(cmd) { proc.send(cmd) }

    function read() { preparing = true; send("read") }
    function toggle() { if (active) send("toggle") }
    function next() { send("next") }
    function prev() { send("prev") }
    function stop() { send("stop") }
    function setSpeed(x) {
        const v = Math.max(0.5, Math.min(3, Math.round(x * 20) / 20))   // 0.05 steps
        if (v !== speed) send(`speed ${v}`)
    }
    function nudgeSpeed(d) { setSpeed(speed + d * 0.05) }
    function pickVoice(key) { if (key !== config.voice) send(`voice ${key}`) }
    function setTidy(mode) { if (mode !== config.tidy) send(`tidy ${mode}`) }
    function voiceLabel() {
        return voices.find(v => v.key === config.voice)?.label ?? (config.voice || "no voices")
    }
    function clock(s) {
        s = Math.max(0, Math.floor(s || 0))
        const h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60), sec = String(s % 60).padStart(2, "0")
        return h ? `${h}:${String(m).padStart(2, "0")}:${sec}` : `${m}:${sec}`
    }

    EngineProcess {
        id: proc
        command: ["python3", Quickshell.shellDir + "/scripts/reader.py"]
        onExited: { root.state = { active: false }; root.preparing = false }
        onEvent: (name, v) => {
            if (name === "state") { root.state = v; if (v.active) root.preparing = false }
            else if (name === "config") root.config = v
            else if (name === "voices") root.voices = v
            else if (name === "notice") {  // comes back in as one of the shell's own toasts
                root.preparing = false
                Quickshell.execDetached(["notify-send", "-a", "Reader", "Reader", v])
            }
        }
    }

    // A finished read clears itself; Super+T or the popout's play starts over.
    Timer {
        interval: 10000
        running: root.finished
        onTriggered: root.stop()
    }

    IpcHandler {
        target: "reader"
        function read(): void { root.read() }
        function toggle(): void { root.toggle() }
        function stop(): void { root.stop() }
    }
}
