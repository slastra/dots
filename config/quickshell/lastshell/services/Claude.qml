pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Claude Code session state, from the slimmed claude-status.py daemon's
// snapshot. The daemon owns liveness, MQTT face state, quota parsing and
// the /proc ppid walk that maps sessions to windows; this just watches.
Singleton {
    id: root

    property var sessions: []
    property var quota: ({ frames: [], worstPct: 0, stale: false })

    FileView {
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/lastshell-claude.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: parse()
        function parse() {
            try {
                const j = JSON.parse(text())
                root.sessions = j.sessions ?? []
                root.quota = j.quota ?? { frames: [], worstPct: 0, stale: false }
            } catch (e) { /* mid-write */ }
        }
    }
}
