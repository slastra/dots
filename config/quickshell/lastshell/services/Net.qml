pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Default-route interface state (wired on the desk, wifi on the laptop): ip +
// up/down throughput, 5s cadence, with a ring buffer feeding the popout graph.
Singleton {
    id: root

    property string iface: ""
    property string ip: ""
    property bool connected: false
    property bool wireless: false
    property real rxBps: 0
    property real txBps: 0
    // last 60 samples of [rx, tx] for the graph
    property var history: []

    property var _prev: null

    // Counters are plain sysfs reads every 5s; the exec probe (ip+jq for
    // the address and interface discovery) runs only once a minute — the
    // address changes approximately never.
    property int _tick: 0
    Timer {
        interval: 5000; running: true; repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (root._tick % 12 === 0 || root.iface === "") probe.running = true
            else if (root.iface !== "") counters()
            root._tick++
        }
    }

    FileView { id: rxF; path: root.iface ? `/sys/class/net/${root.iface}/statistics/rx_bytes` : ""; blockLoading: true }
    FileView { id: txF; path: root.iface ? `/sys/class/net/${root.iface}/statistics/tx_bytes` : ""; blockLoading: true }
    FileView { id: opF; path: root.iface ? `/sys/class/net/${root.iface}/operstate` : ""; blockLoading: true }

    function counters() {
        try {
            rxF.reload(); txF.reload(); opF.reload()
            const rx = Number(rxF.text().trim()), tx = Number(txF.text().trim())
            root.connected = opF.text().trim() === "up" && root.ip !== ""
            sample(rx, tx)
        } catch (e) { /* interface vanished; next probe re-discovers */ }
    }

    // one counter reading -> rates against the previous one (5 s apart)
    function sample(rx, tx) {
        if (root._prev) {
            root.rxBps = Math.max(0, (rx - root._prev.rx) / 5)
            root.txBps = Math.max(0, (tx - root._prev.tx) / 5)
            const h = root.history.slice(-59)
            h.push([root.rxBps, root.txBps])
            root.history = h
        }
        root._prev = { rx: rx, tx: tx }
    }

    Process {
        id: probe
        command: ["sh", "-c",
            // the default route's device, falling back to the first enp* so
            // an unplugged desk still names its port
            "n=$(ip -j route show default | jq -r '.[0].dev // empty'); " +
            "[ -n \"$n\" ] || { i=$(ls -d /sys/class/net/enp* 2>/dev/null | head -n1); n=${i##*/}; }; " +
            "[ -n \"$n\" ] || exit 0; i=/sys/class/net/$n; " +
            "ip -j -4 addr show $n | jq -r --arg n \"$n\" '.[0].addr_info[0].local // \"\" | $n+\" \"+.' ; " +
            "cat $i/statistics/rx_bytes $i/statistics/tx_bytes $i/operstate; " +
            "[ -d $i/wireless ] && echo wireless || echo wired"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n")
                if (lines.length < 4) { root.connected = false; return }
                const [name, addr] = lines[0].split(" ")
                const rx = Number(lines[1]), tx = Number(lines[2])
                root.iface = name
                root.ip = addr ?? ""
                root.connected = lines[3] === "up" && !!addr
                root.wireless = lines[4] === "wireless"
                root.sample(rx, tx)
            }
        }
    }
}
