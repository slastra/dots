import Quickshell
import QtQuick

// Default-sink volume chip: click toggles mute, wheel steps 1%, glyph
// tracks level / mute / bluetooth. State comes from the Audio singleton.
Chip {
    id: root
    edge: "bottom"

    readonly property real vol: Audio.vol
    readonly property bool muted: Audio.muted
    readonly property bool bluetooth: Audio.bluetooth

    onClicked: Audio.toggleMute()
    onWheelUp: Audio.step(0.01)
    onWheelDown: Audio.step(-0.01)

    Popout {
        owner: root

        Column {
            spacing: 8
            PopText {
                text: Audio.description
                size: 14
                width: 220; elide: Text.ElideRight
            }
            SliderTrack {
                width: 220
                frac: root.vol
                fill: root.muted ? Theme.love : Theme.pine
                interactive: true
                onSeek: f => Audio.setVolume(f)
            }
        }
    }

    ChipBody {

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
