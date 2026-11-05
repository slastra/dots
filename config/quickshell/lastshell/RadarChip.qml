import Quickshell
import QtQuick

// Storm radar chip. Absent on quiet days; foam radar while storms are
// around but none is aimed at home; gold lightning under a watch or a
// storm tracking toward home; love tornado, pulsing, under a tornado
// warning or an urgent track. The badge counts down to the nearest
// threat. Hover summarises, click opens RadarView (SUPER+Shift+R).
Chip {
    id: root
    edge: "top"
    present: Radar.active

    readonly property color tone:
        Radar.level === "urgent" ? Theme.love
        : Radar.level === "watch" ? Theme.gold
        : Theme.foam

    function tierTone(t) { return t === "urgent" ? Theme.love : t === "high" ? Theme.gold : Theme.foam }

    onClicked: Quickshell.execDetached(["qs", "-c", "lastshell", "ipc", "call", "overlays", "toggleRadar"])

    ChipBody {
        Badge {
            visible: Radar.nearest !== null && Radar.nearest.eta_min >= 0
            anchors.verticalCenter: parent.verticalCenter
            tone: root.tone
            text: Radar.nearest ? `${Math.round(Radar.nearest.eta_min)}m` : ""
        }

        LucideIcon {
            id: glyph
            anchors.verticalCenter: parent.verticalCenter
            name: Radar.level === "urgent" ? "tornado"
                : Radar.level === "watch" ? "cloud-lightning" : "radar"
            color: root.tone

            // same pulse as the REC chip
            SequentialAnimation on opacity {
                running: Radar.level === "urgent"
                loops: Animation.Infinite
                NumberAnimation { to: 0.45; duration: Theme.blinkDuration }
                NumberAnimation { to: 1.0; duration: Theme.blinkDuration }
                onRunningChanged: if (!running) glyph.opacity = 1
            }
        }
    }

    Popout {
        id: pop
        owner: root

        Column {
            spacing: 10
            width: 400

            PopoutHeader {
                title: "Storms near home"
                status: Radar.tornadoWarning ? "tornado warning"
                    : Radar.severeWarning ? "severe t-storm warning"
                    : Radar.watch ? "watch in effect"
                    : Radar.threats.length > 0 ? "storm headed this way" : "storms nearby"
                tone: root.tone
            }

            ThreatRibbon { width: parent.width; compact: true }

            Repeater { // watches at home; the ribbon already carries a warning
                model: Radar.homeAlerts.filter(a => /Watch/.test(a.event))
                Row {
                    required property var modelData
                    spacing: 7
                    LucideIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: "eye"
                        color: /Tornado/.test(modelData.event) ? Theme.love : Theme.gold
                        font.pixelSize: 13
                    }
                    PopText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: `${modelData.event}${modelData.ends ? "  until " + Radar.clock(modelData.ends) : ""}`
                        size: 13
                    }
                }
            }

            Repeater { // other storms worth a row; the ribbon has the nearest
                model: Radar.notable.filter(s => s.id !== Radar.nearest?.id).slice(0, 3)
                Item {
                    required property var modelData
                    width: parent.width
                    height: rowText.implicitHeight
                    Column {
                        id: rowText
                        width: parent.width - spark.width - 10
                        spacing: 1
                        Row {
                            spacing: 6
                            Badge {
                                visible: modelData.tier !== ""
                                anchors.verticalCenter: parent.verticalCenter
                                text: Radar.tierLabel(modelData.tier)
                                tone: root.tierTone(modelData.tier)
                            }
                            PopText { text: Radar.probs(modelData); size: 13 }
                        }
                        PopText {
                            width: parent.width
                            text: Radar.where(modelData)
                            wrapMode: Text.WordWrap
                            dim: 0.6
                            size: 12
                        }
                    }
                    TorSpark {
                        id: spark
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.topMargin: 2
                        live: pop.visible
                        values: modelData.tor_hist
                        tone: root.tierTone(modelData.tier)
                    }
                }
            }

            Rectangle { // map thumbnail, framed like the view's pane
                visible: thumb.status === Image.Ready
                width: parent.width
                height: visible ? width * thumb.sourceSize.height / Math.max(1, thumb.sourceSize.width) : 0
                radius: Theme.innerRadius
                color: Theme.base
                border.color: Theme.border
                clip: true
                Image {
                    id: thumb
                    anchors.fill: parent
                    anchors.margins: 1
                    source: Radar.url(Radar.images.map ?? "")
                    cache: false
                    asynchronous: true
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    mipmap: true
                }
            }

            PopText {
                width: parent.width
                elide: Text.ElideRight
                text: [
                    Radar.payload.valid ? `ProbSevere ${Radar.clock(Radar.payload.valid)}` : "",
                    Radar.images.scan ? `${Radar.payload.radar} ${Radar.images.scan}` : "",
                    "click to open",
                ].filter(s => s).join("  ·  ")
                dim: 0.45
                size: 12
            }
        }
    }
}
