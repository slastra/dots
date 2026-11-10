import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import QtQuick

// Battery chip (waybar battery). Hidden entirely when no battery exists —
// this is a desktop; the chip appears only if UPower reports a display
// device that is present (e.g. a UPS or BT peripheral promoted to display).
// The popout charts charge and power draw from UPower's history files, so
// the record survives shell restarts; click a span to change the window.
// Clicking the chip itself opens the Eco dialog.
Chip {
    id: root
    edge: "top"
    present: UPower.displayDevice?.isPresent ?? false

    readonly property var dev: UPower.displayDevice
    readonly property real pct: (dev?.percentage ?? 0) * 100
    readonly property bool charging: dev?.state === UPowerDeviceState.Charging
    readonly property real watts: dev?.changeRate ?? 0

    // the power dialog: eco, CPU profile and what eco switches off
    onClicked: Quickshell.execDetached(["qs", "-c", "lastshell", "ipc", "call", "overlays", "toggleEco"])

    ChipBody {
        ValueText {
            rightPadding: 5 // trailing Nerd Font glyph overhangs its advance
            color: Theme.level(100 - root.pct, 80, 90) // warn 20, crit 10 remaining
            text: {
                const ramp = root.charging
                    ? ["󰢜","󰂆","󰂇","󰂈","󰢝","󰂉","󰢞","󰂊","󰂋","󰂅"]
                    : ["󰁺","󰁻","󰁼","󰁽","󰁾","󰁿","󰂀","󰂁","󰂂","󰁹"]
                if (root.pct >= 100 && !root.charging) return "Charged "
                const i = Math.min(9, Math.floor(root.pct / 10))
                return `${Theme.pad(Math.round(root.pct), 3)}% ${ramp[i]}`
            }
        }
    }

    // --- history ------------------------------------------------------------
    // UPower keeps /var/lib/upower/history-{charge,rate}-<id>.dat per battery
    // (rate every 30 s, charge on each 1 % step, thinned with age). The id is
    // model, design capacity and serial, so find the internal battery's
    // files as the most recently written rate log rather than spelling it.
    property string rateFile: ""
    readonly property string chargeFile: rateFile.replace("history-rate-", "history-charge-")
    property var rateLog: []
    property var chargeLog: []
    property real span: 12 * 3600
    readonly property var spans: [[3, "3 h"], [12, "12 h"], [24, "24 h"], [72, "3 d"]]

    function parseLog(text) {
        const out = []
        for (const line of text.split("\n")) {
            const f = line.split("\t")
            if (f.length >= 3) out.push([+f[0], +f[1], f[2]])
        }
        return out
    }
    function duration(secs) {
        if (!(secs > 0)) return ""
        const h = Math.floor(secs / 3600), m = Math.round(secs % 3600 / 60)
        return h > 0 ? `${h}h ${m}m` : `${m}m`
    }

    Process {
        id: findLog
        command: ["sh", "-c", "ls -t /var/lib/upower/history-rate-*.dat 2>/dev/null | grep -v generic_id | head -1"]
        stdout: StdioCollector { onStreamFinished: root.rateFile = text.trim() }
    }
    FileView {
        id: rateView
        path: root.rateFile
        onLoaded: root.rateLog = root.parseLog(text())
    }
    FileView {
        id: chargeView
        path: root.rateFile ? root.chargeFile : ""
        onLoaded: root.chargeLog = root.parseLog(text())
    }
    // UPower rewrites the files every 30 s while discharging; re-read on
    // open and once a minute while the popout is up
    function refresh() {
        if (!rateFile) { findLog.running = true; return }
        rateView.reload(); chargeView.reload()
        chargeGraph.now = rateGraph.now = Date.now() / 1000
    }
    onRateFileChanged: refresh()
    Timer {
        interval: 60000; repeat: true; triggeredOnStart: true
        running: pop.visible
        onTriggered: root.refresh()
    }

    Popout {
        id: pop
        owner: root
        sheetWidth: Theme.popM
        title: "battery"
        status: `${Math.round(root.pct)}%  ·  ` + (root.charging ? "charging"
            : root.dev?.state === UPowerDeviceState.FullyCharged ? "full" : "discharging")
        tone: Theme.level(100 - root.pct, 80, 90, root.charging ? Theme.ok : Theme.calm)

        KeyValueRow { visible: root.watts > 0; key: "power"; value: `${root.watts.toFixed(1)} W` }
        KeyValueRow {
            readonly property string eta: root.duration(root.charging ? root.dev?.timeToFull : root.dev?.timeToEmpty)
            visible: eta !== ""
            key: root.charging ? "full in" : "remaining"
            value: eta
        }
        KeyValueRow {
            visible: root.dev?.healthSupported ?? false
            key: "health"
            value: `${Math.round(root.dev?.healthPercentage ?? 0)}%`
        }

        Divider { width: parent.width }

        Row {
            spacing: 10
            Repeater {
                model: root.spans
                PopText {
                    required property var modelData
                    readonly property bool selected: root.span === modelData[0] * 3600
                    text: modelData[1]
                    size: 12
                    color: selected ? Theme.accent : Theme.textMuted
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -3
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { root.span = parent.modelData[0] * 3600; root.refresh() }
                    }
                }
            }
        }

        BatteryGraph {
            id: chargeGraph
            width: parent.width; height: 56
            live: pop.visible
            mode: "charge"
            samples: root.chargeLog
            span: root.span
            current: root.pct
            charging: root.charging
        }
        PopNote { text: "charge" }

        BatteryGraph {
            id: rateGraph
            width: parent.width; height: 44
            live: pop.visible
            mode: "rate"
            samples: root.rateLog
            span: root.span
        }
        PopNote {
            width: parent.width
            text: {
                const scale = rateGraph.peak > 0 ? `power draw, scale ${Math.round(rateGraph.peak)} W` : "power draw"
                // energy-weighted average over the window, discharging only
                const start = Date.now() / 1000 - root.span
                const d = root.rateLog.filter(s => s[0] >= start && s[1] > 0 && s[2] === "discharging")
                if (d.length < 2) return `${scale}  ·  no discharge in this window`
                const avg = d.reduce((a, s) => a + s[1], 0) / d.length
                return `${scale}  ·  avg ${avg.toFixed(1)} W on battery  ·  peak ${Math.max(...d.map(s => s[1])).toFixed(1)} W`
            }
        }
    }
}
