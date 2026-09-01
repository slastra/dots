pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// gpu-screen-recorder liveness (waybar custom/recording, was a 1s exec).
Singleton {
    id: root

    property bool recording: false

    function stop() {
        Quickshell.execDetached(["sh", "-c",
            "pkill -SIGINT -f gpu-screen-recorder; pkill -f recording-border.py"])
    }

    Timer {
        interval: 2000; running: true; repeat: true
        triggeredOnStart: true
        onTriggered: check.running = true
    }

    Process {
        id: check
        command: ["pgrep", "-x", "gpu-screen-reco"]
        onExited: code => root.recording = code === 0
    }
}
