pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// gpu-screen-recorder liveness. capture.sh maintains /tmp/gpu-screen-recorder.pid
// on every start/stop path, so WATCHING that file replaces the old 2s pgrep
// (~43k process spawns a day for a feature used minutes a week). One pgrep
// at startup adopts a recording that predates the shell.
Singleton {
    id: root

    property bool recording: false

    function stop() {
        Quickshell.execDetached(["sh", "-c",
            "pkill -SIGINT -f gpu-screen-recorder; pkill -f recording-border.py"])
    }

    FileView {
        path: "/tmp/gpu-screen-recorder.pid"
        watchChanges: true
        onLoaded: root.recording = true
        onLoadFailed: root.recording = false
        onFileChanged: reload()
    }

    Process {
        id: adopt
        running: true
        command: ["pgrep", "-x", "gpu-screen-reco"]
        onExited: code => { if (code === 0) root.recording = true }
    }
}
