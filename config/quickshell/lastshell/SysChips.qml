import Quickshell
import QtQuick

// The foam-family stat cluster: network, cpu, temp, disk, memory, recording,
// weather — thin views over the polled singletons, waybar thresholds kept.
ChipRow {

    StatChip {
        id: net
        edge: "top"
        tone: Net.connected ? Theme.calm : Theme.crit
        value: Net.connected ? Net.ip : "Disconnected"
        icon: Net.wireless ? (Net.connected ? "wifi" : "wifi-off")
            : Net.connected ? "ethernet-port" : "unplug"
        // the laptop's Wi-Fi picker; the desk is wired only
        onClicked: if (Host.laptop) Quickshell.execDetached(["qs", "-c", "lastshell", "ipc", "call", "overlays", "toggleWifi"])

        Popout {
            id: netPop
            owner: net
            title: "network"
            status: Net.connected ? Net.ip : "disconnected"
            tone: Net.connected ? Theme.calm : Theme.crit

            function rate(b) {
                return b > 1e6 ? `${(b / 1e6).toFixed(1)} MB/s`
                     : b > 1e3 ? `${(b / 1e3).toFixed(0)} kB/s` : `${b.toFixed(0)} B/s`
            }
            KeyValueRow { key: "interface"; value: Net.iface || "—" }
            KeyValueRow { key: "down"; value: netPop.rate(Net.rxBps) }
            KeyValueRow { key: "up"; value: netPop.rate(Net.txBps) }
            NetGraph { width: parent.width; height: 56; live: netPop.visible }
        }
    }

    StatChip {
        id: cpu
        edge: "top"
        tone: Theme.level(SysStat.cpuPct, 25, 50)
        value: `${Theme.pad(SysStat.cpuPct, 3)}%`
        icon: "cpu"
        Popout {
            owner: cpu
            title: "cpu"
            status: `${SysStat.cpuPct}%`
            tone: Theme.level(SysStat.cpuPct, 25, 50)
            PopMeter { frac: SysStat.cpuPct / 100; fill: Theme.level(SysStat.cpuPct, 25, 50, Theme.accent) }
            KeyValueRow { key: "load"; value: SysStat.loadAvg }
        }
    }

    Chip {
        id: temp
        edge: "top"

        ChipBody {
            ValueText {
                color: Theme.level(SysStat.tempC, 70, 80)
                text: `${Theme.pad(SysStat.tempC, 2)}°C`
            }

            Canvas { // thermometer: mercury tracks the reading (tip on chip below)
                id: thermo
                // drawn, not bound: repaint when the color scheme changes
                Connections { target: Theme; function onSchemeChanged() { thermo.requestPaint() } }
                anchors.verticalCenter: parent.verticalCenter
                width: 10; height: 18
                Connections {
                    target: SysStat
                    function onTempCChanged() { thermo.requestPaint() }
                }
                onPaint: {
                    const ctx = getContext("2d")
                    ctx.reset()
                    const cx = width / 2
                    const bulbR = 3.4, bulbY = height - bulbR - 1
                    const tubeW = 3.4, tubeTop = 2
                    const tone = Theme.level(SysStat.tempC, 70, 80)
                    // glass
                    ctx.lineWidth = 1.3
                    ctx.strokeStyle = Qt.alpha(Theme.text, 0.4)
                    ctx.beginPath()
                    ctx.arc(cx, bulbY, bulbR, 0, 2 * Math.PI)
                    ctx.moveTo(cx - tubeW / 2, bulbY - bulbR + 0.8)
                    ctx.lineTo(cx - tubeW / 2, tubeTop + tubeW / 2)
                    ctx.arc(cx, tubeTop + tubeW / 2, tubeW / 2, Math.PI, 0)
                    ctx.lineTo(cx + tubeW / 2, bulbY - bulbR + 0.8)
                    ctx.stroke()
                    // mercury: 30..90°C maps to the tube; bulb always filled
                    ctx.fillStyle = tone
                    ctx.beginPath(); ctx.arc(cx, bulbY, bulbR - 1.2, 0, 2 * Math.PI); ctx.fill()
                    const frac = Math.max(0, Math.min(1, (SysStat.tempC - 30) / 60))
                    const tubeLen = (bulbY - bulbR) - tubeTop
                    const h = frac * tubeLen
                    if (h > 0) {
                        ctx.fillRect(cx - (tubeW - 2.2) / 2, bulbY - bulbR - h + 1,
                                     tubeW - 2.2, h)
                    }
                }
            }
        }

        Popout {
            id: tempPop
            owner: temp
            title: "temperature"
            status: `${SysStat.tempC}°C`
            tone: Theme.level(SysStat.tempC, 70, 80)

            KeyValueRow {
                readonly property var h: SysStat.tempHistory
                key: "last 5 min"
                value: h.length > 1 ? `${Math.min(...h)}° to ${Math.max(...h)}°` : "collecting…"
            }
            TempGraph { width: parent.width; height: 56; live: tempPop.visible }
            PopNote { text: "cpu package" }
        }
    }

    StatChip {
        id: disk
        edge: "top"
        tone: Theme.level(SysStat.diskPct, 70, 90)
        value: `${Theme.pad(SysStat.diskPct, 2)}%`
        icon: "hard-drive"
        Popout {
            owner: disk
            title: "disk"
            status: `${SysStat.diskPct}%`
            tone: Theme.level(SysStat.diskPct, 70, 90)
            PopMeter { frac: SysStat.diskPct / 100; fill: Theme.level(SysStat.diskPct, 70, 90, Theme.accent) }
            KeyValueRow { key: "used on /"; value: `${SysStat.diskUsed} of ${SysStat.diskTotal}` }
        }
    }

    StatChip {
        id: mem
        edge: "top"
        tone: Theme.level(SysStat.memPct, 50, 75)
        value: `${Theme.pad(SysStat.memPct, 2)}%`
        icon: "memory-stick"
        Popout {
            owner: mem
            title: "memory"
            status: `${SysStat.memPct}%`
            tone: Theme.level(SysStat.memPct, 50, 75)
            PopMeter { frac: SysStat.memPct / 100; fill: Theme.level(SysStat.memPct, 50, 75, Theme.accent) }
            KeyValueRow { key: "used"; value: `${SysStat.memUsedGiB.toFixed(1)} of ${SysStat.memTotalGiB.toFixed(1)} GiB` }
        }
    }

    Chip {
        id: rec
        edge: "top"
        present: Recorder.recording
        onClicked: Recorder.stop()
        ChipBody {
            id: recRow
            LucideIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: "circle-dot"
                color: Theme.crit
            }
            ValueText {
                color: Theme.crit
                text: "REC"
            }
            SequentialAnimation on opacity {
                running: Recorder.recording
                loops: Animation.Infinite
                NumberAnimation { to: 0.5; duration: Theme.blinkDuration }
                NumberAnimation { to: 1.0; duration: Theme.blinkDuration }
            }
        }
    }

    StatChip {
        id: weather
        edge: "top"
        tone: Theme.calm
        value: `${Theme.pad(Weather.now.temp ?? "?", 2)}°F`
        icon: Weather.icon
        present: Weather.text !== ""

        Popout {
            owner: weather
            title: (Weather.now.condition ?? "weather").toLowerCase()
            status: `${Weather.now.temp ?? "?"}°F`
            tone: Theme.calm

            KeyValueRow { key: "feels like"; value: `${Weather.now.feels ?? "?"}°` }
            KeyValueRow { key: "wind"; value: Weather.now.wind ?? "—" }
            KeyValueRow { key: "humidity"; value: Weather.now.humidity ?? "—" }
            Divider { width: parent.width; visible: Weather.days.length > 0 }
            Repeater {
                model: Weather.days
                KeyValueRow {
                    required property var modelData
                    key: modelData.name.toLowerCase()
                    value: `${modelData.hi}° / ${modelData.lo}°`
                }
            }
        }
    }
}
