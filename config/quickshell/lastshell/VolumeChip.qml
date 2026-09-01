import Quickshell
import Quickshell.Services.Pipewire
import QtQuick

// Default-sink volume chip (waybar wireplumber): click toggles mute,
// wheel steps 1%, glyph tracks level / mute / bluetooth.
Chip {
    id: root
    edge: "top"

    readonly property PwNode sink: Pipewire.defaultAudioSink
    PwObjectTracker { objects: [root.sink] }

    readonly property real vol: sink?.audio?.volume ?? 0
    readonly property bool muted: sink?.audio?.muted ?? false
    readonly property bool bluetooth: (sink?.name ?? "").startsWith("bluez")

    onClicked: if (sink?.audio) sink.audio.muted = !sink.audio.muted
    onWheelUp: if (sink?.audio) sink.audio.volume = Math.min(1.5, vol + 0.01)
    onWheelDown: if (sink?.audio) sink.audio.volume = Math.max(0, vol - 0.01)

    Popout {
        owner: root
        edge: "top"
        ownerHovered: root.hovered

        Column {
            spacing: 8
            Text {
                text: root.sink?.description ?? "no sink"
                color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: 14
                width: 220; elide: Text.ElideRight
            }
            Rectangle { // slider track
                width: 220; height: 8; radius: 4
                color: Qt.alpha(Theme.text, 0.22)
                Rectangle {
                    width: parent.width * Math.min(1, root.vol)
                    height: parent.height; radius: 4
                    color: root.muted ? Theme.love : Theme.pine
                    Behavior on width { NumberAnimation { duration: 80 } }
                }
                MouseArea {
                    anchors.fill: parent
                    onPressed: mouse => { if (root.sink?.audio) root.sink.audio.volume = mouse.x / width }
                    onPositionChanged: mouse => { if (pressed && root.sink?.audio) root.sink.audio.volume = Math.max(0, Math.min(1, mouse.x / width)) }
                }
            }
        }
    }

    Row {
        height: root.height - 2
        spacing: 9
        leftPadding: 12
        rightPadding: 12

        ValueText {
            color: Theme.text
            text: `${Math.round(root.vol * 100)}%`
        }

        Canvas { // drawn speaker: wave arcs grow with volume, slash when muted
            id: spk
            anchors.verticalCenter: parent.verticalCenter
            width: 18; height: 18

            Connections {
                target: root
                function onVolChanged() { spk.requestPaint() }
                function onMutedChanged() { spk.requestPaint() }
            }

            onPaint: {
                const ctx = getContext("2d")
                ctx.reset()
                const h = height, cy = h / 2
                const tone = root.muted ? Qt.alpha(Theme.text, 0.45) : Theme.text
                // body: box + cone
                ctx.fillStyle = tone
                ctx.beginPath()
                ctx.moveTo(1, cy - 2.5); ctx.lineTo(4, cy - 2.5)
                ctx.lineTo(8, cy - 6.5); ctx.lineTo(8, cy + 6.5)
                ctx.lineTo(4, cy + 2.5); ctx.lineTo(1, cy + 2.5)
                ctx.closePath(); ctx.fill()
                // wave arcs: first at >2%, second at >50%; sweep tracks level
                if (!root.muted) {
                    ctx.lineWidth = 1.6
                    ctx.lineCap = "round"
                    ctx.strokeStyle = tone
                    if (root.vol > 0.02) {
                        ctx.beginPath(); ctx.arc(8.5, cy, 4, -0.7, 0.7); ctx.stroke()
                    }
                    if (root.vol > 0.5) {
                        ctx.strokeStyle = Qt.alpha(Theme.text, Math.min(1, (root.vol - 0.5) * 2 + 0.35))
                        ctx.beginPath(); ctx.arc(8.5, cy, 7, -0.75, 0.75); ctx.stroke()
                    }
                } else {
                    // mute slash in love
                    ctx.lineWidth = 2
                    ctx.lineCap = "round"
                    ctx.strokeStyle = Theme.love
                    ctx.beginPath(); ctx.moveTo(1.5, cy - 6.5); ctx.lineTo(12.5, cy + 6.5); ctx.stroke()
                }
                // bluetooth tick: small iris dot above the cone
                if (root.bluetooth && !root.muted) {
                    ctx.fillStyle = Theme.iris
                    ctx.beginPath(); ctx.arc(15, cy - 6, 1.8, 0, 2 * Math.PI); ctx.fill()
                }
            }
        }
    }
}
