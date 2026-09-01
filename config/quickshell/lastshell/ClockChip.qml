import Quickshell
import QtQuick

// Clock chip: 12h time beside a tiny drawn analog face — hour hand only,
// which at 18px is the honest amount of information. Click toggles the
// date form; the calendar lives in the hover popout.
Chip {
    id: root
    edge: "top"

    property bool showDate: false
    onClicked: showDate = !showDate

    SystemClock { id: clock; precision: SystemClock.Seconds }

    Row {
        height: root.height - 2
        spacing: 9
        leftPadding: 12
        rightPadding: 12

        ValueText {
            color: Theme.text
            text: root.showDate
                ? Qt.formatDateTime(clock.date, "ddd, dd MMM yyyy")
                : Qt.formatDateTime(clock.date, "hh:mm AP")
        }

        Canvas { // the face
            id: face
            anchors.verticalCenter: parent.verticalCenter
            width: 18; height: 18

            // fractional hour drives the hand; minutes advance it smoothly
            readonly property real hour12:
                (clock.date.getHours() % 12) + clock.date.getMinutes() / 60
            onHour12Changed: requestPaint()

            onPaint: {
                const ctx = getContext("2d")
                ctx.reset()
                const c = width / 2, r = c - 1.5
                // rim
                ctx.lineWidth = 1.5
                ctx.strokeStyle = Qt.alpha(Theme.text, 0.35)
                ctx.beginPath(); ctx.arc(c, c, r, 0, 2 * Math.PI); ctx.stroke()
                // noon tick, so the hand has a reference
                ctx.strokeStyle = Qt.alpha(Theme.text, 0.35)
                ctx.beginPath(); ctx.moveTo(c, c - r); ctx.lineTo(c, c - r + 2.5); ctx.stroke()
                // the hour hand
                const a = hour12 / 12 * 2 * Math.PI - Math.PI / 2
                ctx.lineWidth = 2
                ctx.lineCap = "round"
                ctx.strokeStyle = Theme.rose
                ctx.beginPath()
                ctx.moveTo(c, c)
                ctx.lineTo(c + Math.cos(a) * r * 0.62, c + Math.sin(a) * r * 0.62)
                ctx.stroke()
                // hub
                ctx.fillStyle = Theme.rose
                ctx.beginPath(); ctx.arc(c, c, 1.5, 0, 2 * Math.PI); ctx.fill()
            }
        }
    }

    Popout {
        owner: root
        edge: "top"
        ownerHovered: root.hovered
        Calendar {}
    }
}
