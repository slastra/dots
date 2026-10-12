pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Eco mode, as hypr/scripts/eco.sh keeps it: on while its state file exists.
// eco.sh calls `qs -c lastshell ipc call eco sync` after each change, since
// a FileView cannot watch a file that does not exist yet. While on, the
// shell goes lean too: no animations (Theme durations drop to 0), the Claude
// dot holds still, and the 5 s pollers stretch to 15 s — each of those is a
// bar repaint that knocks the panel out of PSR2 self-refresh.
Singleton {
    id: root

    property bool active: false
    readonly property int pollMs: active ? 15000 : 5000

    FileView {
        id: state
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/eco"
        blockLoading: true
        printErrors: false
        onLoaded: root.active = true
        onLoadFailed: root.active = false
    }

    IpcHandler {
        target: "eco"
        function sync(): void { state.reload() }
    }
}
