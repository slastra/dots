pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import ".."  // root module

// Launch-frequency store for the launcher: count with a two-week half-life.
// Best-effort state — corruption resets to empty.
Singleton {
    id: root

    property var data: ({})
    readonly property string path: Quickshell.env("HOME") + "/.local/state/lastshell/frecency.json"

    FileView {
        id: file
        path: root.path
        blockLoading: true
        onLoaded: {
            try { root.data = JSON.parse(text()) } catch (e) { root.data = {} }
        }
    }

    function weight(id) {
        const e = data[id]
        if (!e) return 0
        const ageDays = (Date.now() - e.last) / 86400e3
        return e.count * Math.pow(0.5, ageDays / 14)
    }

    function record(id) {
        const d = Object.assign({}, data)
        d[id] = { count: (d[id]?.count ?? 0) + 1, last: Date.now() }
        data = d
        write.running = true
    }

    // Serialized through one Process; mkdir -p covers first run.
    Process {
        id: write
        command: ["sh", "-c",
            `mkdir -p "$(dirname '${root.path}')" && cat > '${root.path}.tmp' && mv '${root.path}.tmp' '${root.path}'`]
        stdinEnabled: true
        onStarted: { write.write(JSON.stringify(root.data)); write.stdinEnabled = false }
    }
}
