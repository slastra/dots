import Quickshell
import QtQuick
import ".."  // root module

// Full storm view (SUPER+Shift+R, or click the radar chip). An instrument,
// not a dashboard: the map pane on the left at the renderer's own aspect,
// and on the right the threat ribbon, what is in force at home, and the
// storms ProbSevere is scoring, each with its ProbTor trace. One map pane
// at a time (1-4 / ←→) so the card fits a 1536x864 logical screen. Images
// change filename per render, so a new render reloads by itself.
Overlay {
    id: root

    cardWidth: 1140
    contentPadding: 2

    property int pane: 0
    readonly property var panes: [
        { key: "map", label: "Reflectivity" },
        { key: "velocity", label: "Velocity" },
        { key: "mrms", label: "Rotation" },
        { key: "loop", label: "Loop" },
    ]
    readonly property string src: Radar.url(Radar.images[panes[pane].key] ?? "")
    // the renderer draws at (lon span · cos lat) / lat span ≈ 0.95
    readonly property real paneH: 660
    readonly property real paneW: Math.round(paneH * 0.952)

    function tierTone(t) { return t === "urgent" ? Theme.crit : t === "high" ? Theme.warn : Theme.calm }

    Column {
        width: parent.width
        focus: true

        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) root.dismiss()
            else if (event.key === Qt.Key_Right || event.key === Qt.Key_Tab) root.pane = (root.pane + 1) % root.panes.length
            else if (event.key === Qt.Key_Left || event.key === Qt.Key_Backtab) root.pane = (root.pane + root.panes.length - 1) % root.panes.length
            else if (event.key >= Qt.Key_1 && event.key <= Qt.Key_4) root.pane = event.key - Qt.Key_1
            else return
            event.accepted = true
        }

        ModalHeader {
            icon: Radar.level === "urgent" ? "tornado" : "cloud-lightning"
            title: "Radar"
            showQuery: false
            active: root.open

            Segmented {
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                anchors.rightMargin: 18
                width: 440
                options: root.panes.map((p, i) => ({ value: i, label: `${i + 1}  ${p.label}` }))
                current: root.pane
                onPicked: v => root.pane = v
            }
        }

        Row {
            x: 18
            topPadding: 14
            bottomPadding: 14
            spacing: 20

            Rectangle { // map pane
                width: root.paneW
                height: root.paneH
                radius: Theme.innerRadius
                color: Theme.base
                border.color: Theme.border
                clip: true

                Image {
                    anchors.fill: parent
                    anchors.margins: 1
                    visible: root.panes[root.pane].key !== "loop"
                    source: visible ? root.src : ""
                    cache: false
                    asynchronous: true
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    mipmap: true
                }
                AnimatedImage {
                    anchors.fill: parent
                    anchors.margins: 1
                    visible: root.panes[root.pane].key === "loop"
                    source: visible ? root.src : ""
                    playing: visible && root.open
                    cache: false
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                }
                Column {
                    anchors.centerIn: parent
                    visible: root.src === ""
                    spacing: 8
                    LucideIcon { anchors.horizontalCenter: parent.horizontalCenter; name: "radar"; color: Theme.textFaint; font.pixelSize: 28 }
                    PopText { text: "no imagery yet: the renderer runs while storms are near"; dim: 0.5 }
                }
            }

            Column { // what the daemon knows
                width: 1140 - 36 - root.paneW - 20
                spacing: 14

                ThreatRibbon { width: parent.width }

                Column { // in force at home
                    width: parent.width
                    spacing: 6
                    visible: homeRep.count > 0
                    SectionLabel { text: "At home" }
                    Repeater {
                        id: homeRep
                        model: Radar.homeAlerts.filter(a => /Warning|Watch|Statement/.test(a.event))
                        Row {
                            required property var modelData
                            width: parent.width
                            spacing: 8
                            LucideIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                name: /Warning/.test(modelData.event) ? "siren" : /Watch/.test(modelData.event) ? "eye" : "info"
                                color: /Tornado/.test(modelData.event) ? Theme.crit
                                    : /Thunderstorm/.test(modelData.event) ? Theme.warn : Theme.calm
                                font.pixelSize: 13
                            }
                            PopText {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 21
                                elide: Text.ElideRight
                                text: `${modelData.event}${modelData.ends ? "  until " + Radar.clock(modelData.ends) : ""}`
                                size: 13
                            }
                        }
                    }
                }

                Column { // the vortex the renderer tracked across volumes
                    width: parent.width
                    spacing: 4
                    visible: !!Radar.images.vortex
                    SectionLabel { text: "Rotation" }
                    PopText {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        size: 13
                        text: Radar.images.vortex
                            ? `${Math.round(Radar.images.vortex.dv_kt)} kt ΔV, tracked over ${Radar.images.vortex.scans} scans, ${Radar.images.vortex.mph} mph → ${Radar.point(Radar.images.vortex.heading)}`
                            : ""
                    }
                }

                Column { // the storms
                    width: parent.width
                    spacing: 10
                    SectionLabel { text: "Storms"; visible: Radar.notable.length > 0 }
                    Repeater {
                        model: Radar.notable.slice(0, 5)
                        Item {
                            required property var modelData
                            width: parent.width
                            height: rowText.implicitHeight
                            Column {
                                id: rowText
                                width: parent.width - spark.width - 12
                                spacing: 2
                                Row {
                                    spacing: 7
                                    Badge {
                                        visible: modelData.tier !== ""
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: Radar.tierLabel(modelData.tier)
                                        tone: root.tierTone(modelData.tier)
                                    }
                                    PopText {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: `#${modelData.id}  ${Radar.probs(modelData)}`
                                        size: 13
                                    }
                                }
                                PopText {
                                    width: parent.width
                                    wrapMode: Text.WordWrap
                                    dim: 0.65
                                    size: 12
                                    text: Radar.where(modelData)
                                }
                                PopText {
                                    width: parent.width
                                    elide: Text.ElideRight
                                    dim: 0.42
                                    size: 11
                                    text: `SRH ${Math.round(modelData.env.srh01)} · shear ${Math.round(modelData.env.ebshear)} kt · CAPE ${Math.round(modelData.env.mlcape)} · LCL ${Math.round(modelData.env.lcl)} m`
                                }
                            }
                            TorSpark {
                                id: spark
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.topMargin: 2
                                width: 84
                                height: 22
                                live: root.open
                                values: modelData.tor_hist
                                tone: root.tierTone(modelData.tier)
                            }
                        }
                    }
                    PopText {
                        visible: Radar.notable.length === 0
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: "No storm near home is scoring a tornado or wind signal."
                        dim: 0.5
                        size: 12
                    }
                }
            }
        }

        ModalFooter {
            hint: "1-4 or ←→ pane   esc close"
            count: [
                Radar.payload.valid ? `ProbSevere ${Radar.clock(Radar.payload.valid)}` : "",
                Radar.images.scan ? `${Radar.payload.radar ?? ""} ${Radar.images.scan}` : "",
                Radar.images.rendered_at ? `rendered ${Radar.clock(Radar.images.rendered_at)}` : "",
            ].filter(s => s).join("  ·  ")
        }
    }
}
