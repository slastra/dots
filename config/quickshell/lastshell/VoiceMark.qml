import QtQuick

// deskvoice's mark: three drawn bars, the desk's mouth. One colour per voice
// (Voice.tone). The shape says what's happening:
//   idle       three low dots, muted         nobody is talking
//   speaking   bars stepping like speech     deskdoc, a Claude cue, the reader
//   listening  a still peak (low-high-low)   the mic is open for you
//   dictating  bars stepping, slower         you are being written down
//   thinking   one bar lit at a time, sweeping back and forth: working on it
// Stepped at 12fps by a Timer (StateDot's reasoning: an animation frame is a
// bar repaint), still in eco mode, and asleep whenever it isn't moving.
Item {
    id: root

    property string mode: "idle"
    property color tone: Theme.textMuted
    property real unit: 1            // 1 in the chip, larger in the popout's "now"

    readonly property int barW: Math.round(2 * unit)
    readonly property int gap: Math.round(2 * unit)
    readonly property int tall: Math.round(12 * unit)
    implicitWidth: barW * 3 + gap * 2
    implicitHeight: tall

    readonly property bool moving: (mode === "speaking" || mode === "dictating" || mode === "thinking")
                                   && visible && !Eco.active

    // heights as fractions of `tall`, one row per frame; speech is irregular
    // on purpose, a level meter would look mechanical
    readonly property var speech: [[0.45, 0.9, 0.6], [0.7, 0.5, 0.95], [0.35, 1.0, 0.55], [0.8, 0.65, 0.4],
                                   [0.5, 0.85, 0.75], [0.95, 0.45, 0.6], [0.4, 0.7, 0.9], [0.65, 1.0, 0.5]]
    // a scanner: the lit bar walks left to right and back, the others resting
    readonly property var sweep: [[1.0, 0.3, 0.3], [0.3, 1.0, 0.3], [0.3, 0.3, 1.0], [0.3, 1.0, 0.3]]
    property int frame: 0
    readonly property var heights: {
        if (mode === "listening") return [0.45, 1.0, 0.45]
        if (mode === "thinking") return moving ? sweep[frame % sweep.length] : [0.3, 1.0, 0.3]
        if (moving) return speech[frame % speech.length]
        if (mode === "speaking" || mode === "dictating") return [0.6, 0.9, 0.6]   // eco: a still "voice"
        return [0.25, 0.25, 0.25]
    }

    Timer {
        interval: root.mode === "dictating" ? 166 : root.mode === "thinking" ? 125 : 83
        repeat: true
        running: root.moving
        onTriggered: root.frame++
    }

    Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: root.gap
        Repeater {
            model: 3
            Rectangle {
                required property int index
                width: root.barW
                height: Math.max(root.barW, Math.round(root.tall * root.heights[index]))
                anchors.verticalCenter: parent.verticalCenter
                radius: width / 2
                color: root.tone
                // thinking lights one bar; the resting two dim behind it
                opacity: root.mode === "thinking" && root.heights[index] < 0.5 ? 0.4 : 1
            }
        }
    }
}
