import QtQuick

// Usage as a drawn ring gauge — the arc sweeps between values, the color
// carries the worst limit, and the frame label sits beside it. Click
// cycles frames; the hover card shows every window with its reset time.
Chip {
    id: root
    edge: "bottom"
    present: Claude.quota.frames.length > 0

    property int frame: 0
    onClicked: frame = (frame + 1) % Math.max(1, Claude.quota.frames.length)

    readonly property var shown: Claude.quota.frames[frame % Math.max(1, Claude.quota.frames.length)] ?? { id: "", pct: 0 }
    readonly property color accent: Theme.level(Claude.quota.worstPct, 70, 90, Theme.foam)

    // The animated value the arc actually draws — sweeps on frame change
    // and on live quota movement alike.
    property real drawnPct: 0
    Behavior on drawnPct { NumberAnimation { duration: Theme.sweepDuration; easing.type: Easing.OutCubic } }
    onShownChanged: drawnPct = shown.pct ?? 0
    Component.onCompleted: drawnPct = shown.pct ?? 0

    ChipBody {

        Canvas { // the ring
            id: ring
            anchors.verticalCenter: parent.verticalCenter
            width: 18; height: 18
            onPaint: {
                const ctx = getContext("2d")
                ctx.reset()
                const c = width / 2, r = c - 2
                ctx.lineWidth = 3
                ctx.lineCap = "round"
                // track: legible against surface, quiet under the arc
                ctx.strokeStyle = Qt.alpha(Theme.text, 0.22)
                ctx.beginPath(); ctx.arc(c, c, r, 0, 2 * Math.PI); ctx.stroke()
                if (root.drawnPct > 0) {
                    ctx.strokeStyle = Qt.alpha(root.accent, Claude.quota.stale ? 0.5 : 1)
                    ctx.beginPath()
                    ctx.arc(c, c, r, -Math.PI / 2,
                            -Math.PI / 2 + 2 * Math.PI * Math.min(1, root.drawnPct / 100))
                    ctx.stroke()
                }
            }
            Connections {
                target: root
                function onDrawnPctChanged() { ring.requestPaint() }
                function onAccentChanged() { ring.requestPaint() }
            }
        }

        ValueText {
            color: root.accent
            text: `${Math.round(root.shown.pct ?? 0)}%`
        }

        LucideIcon { // frame marker: hourglass for the 5h window, calendar for weeklies
            anchors.verticalCenter: parent.verticalCenter
            font.pixelSize: 14
            color: root.accent
            name: root.shown.id === "5h" ? "hourglass" : "calendar-days"
        }

        PopText { // model name, only where the calendar alone is ambiguous
            visible: root.shown.id !== "5h" && root.shown.id !== "wk"
            anchors.verticalCenter: parent.verticalCenter
            size: 12
            dim: 0.5
            text: root.shown.id
        }
    }

    // "resets in" is recomputed against this, refreshed once a minute while
    // the card is up, instead of a Date.now() that only re-ran on new frames
    property double now: Date.now()
    Timer { interval: 60000; running: pop.visible; repeat: true; onTriggered: root.now = Date.now() }

    Popout {
        id: pop
        owner: root
        onVisibleChanged: if (visible) root.now = Date.now()

        Column {
            spacing: 10

            Row { // header
                spacing: 8
                LucideIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: "sparkles"
                    color: Theme.rose
                    font.pixelSize: 14
                }
                PopText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Claude Code Usage"
                    size: 14; font.bold: true
                    font.letterSpacing: 0.5
                }
            }

            Divider { width: 264 }

            Repeater {
                model: Claude.quota.frames
                Item {
                    id: frameRow
                    required property var modelData
                    width: 264
                    height: 34
                    readonly property color tone: Theme.level(modelData.pct, 70, 90, Theme.foam)
                    readonly property var names: ({ "5h": "5-hour window", "wk": "weekly",
                                                    "opus": "weekly · opus", "sonnet": "weekly · sonnet" })

                    function resetsIn(v) {
                        if (!v) return ""
                        const t = typeof v === "number" ? v * 1000 : Date.parse(v)
                        const s = (t - root.now) / 1000
                        if (!(s > 0)) return ""
                        if (s < 5400) return `resets in ${Math.round(s / 60)}m`
                        if (s < 129600) return `resets in ${Math.round(s / 3600)}h`
                        return `resets in ${Math.round(s / 86400)}d`
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4

                        Item {
                            width: 264; height: 16
                            Row {
                                anchors.left: parent.left
                                spacing: 6
                                LucideIcon {
                                    name: frameRow.modelData.id === "5h" ? "hourglass" : "calendar-days"
                                    color: Qt.alpha(Theme.text, 0.55)
                                    font.pixelSize: 13
                                }
                                PopText {
                                    text: frameRow.names[frameRow.modelData.id] ?? frameRow.modelData.id
                                    dim: 0.85
                                    size: 13
                                }
                                PopText {
                                    visible: text !== ""
                                    text: {
                                        const r = frameRow.resetsIn(frameRow.modelData.resets)
                                        return r ? `(${r})` : ""
                                    }
                                    dim: 0.4
                                    size: 12
                                }
                            }
                            PopText {
                                anchors.right: parent.right
                                text: `${frameRow.modelData.pct.toFixed(0)}%`
                                color: frameRow.tone
                                size: 13; font.bold: true
                            }
                        }

                        SliderTrack { // same neutral track as the ring on the chip
                            width: 264; height: 6
                            frac: frameRow.modelData.pct / 100
                            fill: frameRow.tone
                            sweep: Theme.sweepDuration
                        }
                    }
                }
            }

            Divider { width: 264 }

            Item { // freshness footer
                width: 264; height: 14
                PopText {
                    anchors.left: parent.left
                    text: `${Claude.sessions.count} session${Claude.sessions.count === 1 ? "" : "s"}`
                    dim: 0.45
                    size: 11
                }
                PopText {
                    anchors.right: parent.right
                    text: Claude.quota.stale ? "stale data" : "live"
                    color: Claude.quota.stale ? Qt.alpha(Theme.gold, 0.8) : Qt.alpha(Theme.foam, 0.6)
                    size: 11
                    font.italic: Claude.quota.stale
                }
            }
        }
    }
}
