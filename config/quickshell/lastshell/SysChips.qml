import QtQuick

// The foam-family stat cluster: network, cpu, temp, disk, memory, recording,
// weather — thin views over the polled singletons, waybar thresholds kept.
ChipRow {
    spacing: 8

    StatChip {
        id: net
        edge: "top"
        tone: Net.connected ? Theme.foam : Theme.love
        value: Net.connected ? Net.ip : "Disconnected"
        icon: Net.wireless ? (Net.connected ? "wifi" : "wifi-off")
            : Net.connected ? "ethernet-port" : "unplug"

        Popout {
            id: netPop
            owner: net
            Column {
                spacing: 6
                PopText {
                    text: `${Net.iface}: ${Net.ip}`
                    size: 14
                }
                PopText {
                    function fmt(b) {
                        return b > 1e6 ? `${(b / 1e6).toFixed(1)} MB/s`
                             : b > 1e3 ? `${(b / 1e3).toFixed(0)} kB/s` : `${b.toFixed(0)} B/s`
                    }
                    text: `↓ ${fmt(Net.rxBps)}   ↑ ${fmt(Net.txBps)}`
                    color: Theme.foam; size: 14
                }
                NetGraph { width: 240; height: 60; live: netPop.visible }
            }
        }
    }

    StatChip {
        id: cpu
        edge: "top"
        tone: Theme.level(SysStat.cpuPct, 25, 50)
        value: `${SysStat.cpuPct}%`
        icon: "cpu"
        ChipTip {
            owner: cpu
            text: `CPU ${SysStat.cpuPct}%\nload ${SysStat.loadAvg}`
        }
    }

    Chip {
        id: temp
        edge: "top"

        ChipBody {
            ValueText {
                color: Theme.level(SysStat.tempC, 70, 80)
                text: `${SysStat.tempC}°C`
            }

            Canvas { // thermometer: mercury tracks the reading (tip on chip below)
                id: thermo
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
            Column {
                spacing: 6
                Row {
                    spacing: 8
                    PopText {
                        text: "package temperature"
                        size: 14
                    }
                    PopText {
                        text: `${SysStat.tempC}°C`
                        color: Theme.level(SysStat.tempC, 70, 80)
                        size: 14
                    }
                }
                PopText {
                    readonly property var h: SysStat.tempHistory
                    text: h.length > 1
                        ? `5 min: low ${Math.min(...h)}°  ·  high ${Math.max(...h)}°`
                        : "collecting…"
                    dim: 0.6
                    size: 12
                }
                TempGraph { width: 240; height: 60; live: tempPop.visible }
            }
        }
    }

    StatChip {
        id: disk
        edge: "top"
        tone: Theme.level(SysStat.diskPct, 70, 90)
        value: `${SysStat.diskPct}%`
        icon: "hard-drive"
        ChipTip {
            owner: disk
            text: `/ — ${SysStat.diskUsed} of ${SysStat.diskTotal} used`
        }
    }

    StatChip {
        id: mem
        edge: "top"
        tone: Theme.level(SysStat.memPct, 50, 75)
        value: `${SysStat.memPct}%`
        icon: "memory-stick"
        ChipTip {
            owner: mem
            text: `${SysStat.memUsedGiB.toFixed(1)} / ${SysStat.memTotalGiB.toFixed(1)} GiB`
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
                color: Theme.love
            }
            ValueText {
                color: Theme.love
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
        tone: Theme.foam
        value: `${Weather.now.temp ?? "?"}°F`
        icon: Weather.icon
        present: Weather.text !== ""

        Popout {
            owner: weather

            Column {
                spacing: 8

                Row {
                    spacing: 8
                    PopText {
                        text: `${Weather.now.condition ?? "—"}`
                        size: 14; font.bold: true
                    }
                    PopText {
                        text: `${Weather.now.temp ?? "?"}°`
                        color: Theme.foam
                        size: 14
                    }
                }
                PopText {
                    text: `feels ${Weather.now.feels ?? "?"}°  ·  ${Weather.now.wind ?? ""}  ·  ${Weather.now.humidity ?? ""}`
                    dim: 0.6
                    size: 12
                }
                Divider { width: 200 }
                Repeater {
                    model: Weather.days
                    Item {
                        required property var modelData
                        width: 200; height: 20
                        PopText {
                            anchors.left: parent.left
                            text: modelData.name
                            dim: 0.8
                            size: 13
                        }
                        PopText {
                            anchors.right: parent.right
                            text: `${modelData.hi}° / ${modelData.lo}°`
                            color: Theme.foam
                            size: 13
                        }
                    }
                }
            }
        }
    }
}
