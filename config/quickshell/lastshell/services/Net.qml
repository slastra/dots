pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Wired interface state (waybar network with interface enp*): ip + up/down
// throughput, 5s cadence, with a ring buffer feeding the popout graph.
Singleton {
    id: root

    property string iface: ""
    property string ip: ""
    property bool connected: false
    property real rxBps: 0
    property real txBps: 0
    // last 60 samples of [rx, tx] for the graph
    property var history: []

    property var _prev: null

    Timer {
        interval: 5000; running: true; repeat: true
        triggeredOnStart: true
        onTriggered: probe.running = true
    }

    Process {
        id: probe
        command: ["sh", "-c",
            "for i in /sys/class/net/enp*; do [ -d \"$i\" ] || continue; n=$(basename $i); " +
            "ip -j -4 addr show $n | jq -r --arg n \"$n\" '.[0].addr_info[0].local // \"\" | $n+\" \"+.' ; " +
            "cat $i/statistics/rx_bytes $i/statistics/tx_bytes $i/operstate; break; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n")
                if (lines.length < 4) { root.connected = false; return }
                const [name, addr] = lines[0].split(" ")
                const rx = Number(lines[1]), tx = Number(lines[2])
                root.iface = name
                root.ip = addr ?? ""
                root.connected = lines[3] === "up" && !!addr
                if (root._prev) {
                    root.rxBps = Math.max(0, (rx - root._prev.rx) / 5)
                    root.txBps = Math.max(0, (tx - root._prev.tx) / 5)
                    const h = root.history.slice(-59)
                    h.push([root.rxBps, root.txBps])
                    root.history = h
                }
                root._prev = { rx: rx, tx: tx }
            }
        }
    }
}
