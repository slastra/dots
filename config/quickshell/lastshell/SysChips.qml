import QtQuick

// The foam-family stat cluster: network, cpu, temp, disk, memory, recording,
// weather — thin views over the polled singletons, waybar thresholds kept.
Row {
    spacing: 8

    Chip {
        id: net
        edge: "top"
        visible: true

        Popout {
            owner: net
            edge: "top"
            ownerHovered: net.hovered
            Column {
                spacing: 6
                Text {
                    text: `${Net.iface}: ${Net.ip}`
                    color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: 14
                }
                Text {
                    function fmt(b) {
                        return b > 1e6 ? `${(b / 1e6).toFixed(1)} MB/s`
                             : b > 1e3 ? `${(b / 1e3).toFixed(0)} kB/s` : `${b.toFixed(0)} B/s`
                    }
                    text: `↓ ${fmt(Net.rxBps)}   ↑ ${fmt(Net.txBps)}`
                    color: Theme.foam; font.family: Theme.fontFamily; font.pixelSize: 14
                }
                NetGraph { width: 240; height: 60 }
            }
        }

        Row {
            height: net.height - 2
            spacing: 8
            leftPadding: 12
            rightPadding: 12
            ValueText {
                color: Net.connected ? Theme.foam : Theme.love
                text: Net.connected ? Net.ip : "Disconnected"
            }
            LucideIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: Net.connected ? "ethernet-port" : "unplug"
                color: Net.connected ? Theme.foam : Theme.love
            }
        }
    }

    Chip {
        id: cpu
        edge: "top"
        Row {
            height: cpu.height - 2
            spacing: 8
            leftPadding: 12
            rightPadding: 12
            ValueText {
                color: Theme.level(SysStat.cpuPct, 25, 50)
                text: `${SysStat.cpuPct}%`
            }
            LucideIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: "cpu"
                color: Theme.level(SysStat.cpuPct, 25, 50)
            }
        }
        ChipTip {
            owner: cpu; edge: "top"; ownerHovered: cpu.hovered
            text: `CPU ${SysStat.cpuPct}%\nload ${SysStat.loadAvg}`
        }
    }

    Chip {
        id: temp
        edge: "top"

        Row {
            height: temp.height - 2
            spacing: 8
            leftPadding: 12
            rightPadding: 12

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

        ChipTip {
            owner: temp; edge: "top"; ownerHovered: temp.hovered
            text: `package temperature ${SysStat.tempC}°C\nwarning 70°C · critical 80°C`
        }
    }

    Chip {
        id: disk
        edge: "top"
        Row {
            height: disk.height - 2
            spacing: 8
            leftPadding: 12
            rightPadding: 12
            ValueText {
                color: Theme.level(SysStat.diskPct, 70, 90)
                text: `${SysStat.diskPct}%`
            }
            LucideIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: "hard-drive"
                color: Theme.level(SysStat.diskPct, 70, 90)
            }
        }
        ChipTip {
            owner: disk; edge: "top"; ownerHovered: disk.hovered
            text: `/ — ${SysStat.diskUsed} of ${SysStat.diskTotal} used`
        }
    }

    Chip {
        id: mem
        edge: "top"
        Row {
            height: mem.height - 2
            spacing: 8
            leftPadding: 12
            rightPadding: 12
            ValueText {
                color: Theme.level(SysStat.memPct, 50, 75)
                text: `${SysStat.memPct}%`
            }
            LucideIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: "memory-stick"
                color: Theme.level(SysStat.memPct, 50, 75)
            }
        }
        ChipTip {
            owner: mem; edge: "top"; ownerHovered: mem.hovered
            text: `${SysStat.memUsedGiB.toFixed(1)} / ${SysStat.memTotalGiB.toFixed(1)} GiB`
        }
    }

    Chip {
        id: rec
        edge: "top"
        visible: Recorder.recording
        onClicked: Recorder.stop()
        Row {
            id: recRow
            height: rec.height - 2
            spacing: 8
            leftPadding: 12
            rightPadding: 12
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
                NumberAnimation { to: 0.5; duration: 500 }
                NumberAnimation { to: 1.0; duration: 500 }
            }
        }
    }

    Chip {
        id: weather
        edge: "top"
        visible: Weather.text !== ""

        Popout {
            owner: weather
            edge: "top"
            ownerHovered: weather.hovered

            Column {
                spacing: 8

                Row {
                    spacing: 8
                    Text {
                        text: `${Weather.now.condition ?? "—"}`
                        color: Theme.text; font.family: Theme.fontFamily
                        font.pixelSize: 15; font.bold: true
                    }
                    Text {
                        text: `${Weather.now.temp ?? "?"}°`
                        color: Theme.foam; font.family: Theme.fontFamily
                        font.pixelSize: 15
                    }
                }
                Text {
                    text: `feels ${Weather.now.feels ?? "?"}°  ·  ${Weather.now.wind ?? ""}  ·  ${Weather.now.humidity ?? ""}`
                    color: Qt.alpha(Theme.text, 0.6)
                    font.family: Theme.fontFamily; font.pixelSize: 12
                }
                Rectangle { width: 200; height: 1; color: Theme.overlay }
                Repeater {
                    model: Weather.days
                    Item {
                        required property var modelData
                        width: 200; height: 20
                        Text {
                            anchors.left: parent.left
                            text: modelData.name
                            color: Qt.alpha(Theme.text, 0.8)
                            font.family: Theme.fontFamily; font.pixelSize: 13
                        }
                        Text {
                            anchors.right: parent.right
                            text: `${modelData.hi}° / ${modelData.lo}°`
                            color: Theme.foam
                            font.family: Theme.fontFamily; font.pixelSize: 13
                        }
                    }
                }
            }
        }

        Row {
            height: weather.height - 2
            spacing: 8
            leftPadding: 12
            rightPadding: 12
            ValueText {
                color: Theme.foam
                text: `${Weather.now.temp ?? "?"}°F`
            }
            LucideIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: Weather.icon
                color: Theme.foam
            }
        }
    }
}
