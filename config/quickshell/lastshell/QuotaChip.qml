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
    readonly property color accent: Theme.level(Claude.quota.worstPct, 70, 90)
    // the ring's arc: the accent while usage is normal, warn and crit past 70 and 90
    readonly property color arc: Theme.level(Claude.quota.worstPct, 70, 90, Theme.accent)

    // The animated value the arc actually draws — sweeps on frame change
    // and on live quota movement alike.
    property real drawnPct: 0
    Behavior on drawnPct { NumberAnimation { duration: Theme.sweepDuration; easing.type: Easing.OutCubic } }
    onShownChanged: drawnPct = shown.pct ?? 0
    Component.onCompleted: drawnPct = shown.pct ?? 0

    ChipBody {

        Canvas { // the ring
            id: ring
            // drawn, not bound: repaint when the color scheme changes
            Connections { target: Theme; function onSchemeChanged() { ring.requestPaint() } }
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
                    ctx.strokeStyle = Qt.alpha(root.arc, Claude.quota.stale ? 0.5 : 1)
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
                function onArcChanged() { ring.requestPaint() }
            }
        }

        ValueText {
            color: root.accent
            text: `${Theme.pad(Math.round(root.shown.pct ?? 0), 3)}%`
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
        sheetWidth: Theme.popM
        title: "claude usage"
        status: Claude.quota.stale ? "stale" : `${Math.round(Claude.quota.worstPct)}%`
        tone: Claude.quota.stale ? Theme.warn : root.accent
        note: `${Claude.sessions.count} session${Claude.sessions.count === 1 ? "" : "s"} open`

        Repeater {
            model: Claude.quota.frames
            Column {
                id: frameRow
                required property var modelData
                width: parent.width
                spacing: 4
                readonly property color tone: Theme.level(modelData.pct, 70, 90)
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

                KeyValueRow {
                    key: frameRow.names[frameRow.modelData.id] ?? frameRow.modelData.id
                    value: `${frameRow.modelData.pct.toFixed(0)}%`
                    tone: frameRow.tone
                }
                PopMeter {
                    frac: frameRow.modelData.pct / 100
                    fill: Theme.level(frameRow.modelData.pct, 70, 90, Theme.accent)
                }
                PopNote {
                    visible: text !== ""
                    text: frameRow.resetsIn(frameRow.modelData.resets)
                }
            }
        }
    }
}
