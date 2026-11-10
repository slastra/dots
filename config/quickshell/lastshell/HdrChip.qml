import QtQuick

// SDR brightness chip: the desktop's lift against the HDR range. Click
// toggles 1.0 ↔ last value, wheel steps 0.05, popout drags 1.0–3.0.
StatChip {
    id: root
    edge: "top"

    readonly property real b: Hdr.brightness
    readonly property bool lifted: b > 1.0
    tone: lifted ? Theme.warn : Theme.text
    value: `${b.toFixed(1)}×`
    icon: "sun"

    onClicked: Hdr.toggle()
    onWheelUp: Hdr.nudge(Hdr.step)
    onWheelDown: Hdr.nudge(-Hdr.step)

    Popout {
        owner: root
        title: "sdr brightness"
        status: `${root.b.toFixed(2)}×`

        SliderTrack { // 1.0 at the left edge
            width: parent.width
            frac: (root.b - Hdr.min) / (Hdr.max - Hdr.min)
            interactive: true
            onSeek: f => Hdr.set(Hdr.min + (Hdr.max - Hdr.min) * f)
        }
        PopNote { text: "how bright SDR content is drawn on the HDR display" }
    }

}
