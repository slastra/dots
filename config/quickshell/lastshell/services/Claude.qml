pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import ".."

// Claude Code session state, from the slimmed claude-status.py daemon's
// snapshot. The daemon owns liveness, MQTT face state, quota parsing and
// the /proc ppid walk that maps sessions to windows; this just watches.
Singleton {
    id: root

    // keyed so a changed snapshot only touches the sessions that came or went
    readonly property SyncedList sessions: SyncedList {}
    property var quota: ({ frames: [], worstPct: 0, stale: false })

    FileView {
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/lastshell-claude.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: parse()
        function parse() {
            try {
                const j = JSON.parse(text())
                root.sessions.sync(j.sessions ?? [], "pid")
                root.quota = j.quota ?? { frames: [], worstPct: 0, stale: false }
            } catch (e) { /* mid-write */ }
        }
    }
}
