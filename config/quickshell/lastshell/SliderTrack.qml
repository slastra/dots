import QtQuick

// Neutral track with an animated fill. `interactive` adds press/drag
// (only inside a Popout or overlay window: a MouseArea under a Chip's
// own MouseArea never fires). `seek` reports the pointer's fraction.
Rectangle {
    id: root
    property real frac: 0
    property color fill: Theme.pine
    property bool interactive: false
    property int sweep: Theme.dragDuration
    signal seek(real frac)

    height: 8
    radius: height / 2
    color: Theme.track

    Rectangle {
        width: parent.width * Math.max(0, Math.min(1, root.frac))
        height: parent.height
        radius: parent.radius
        color: root.fill
        Behavior on width { NumberAnimation { duration: root.sweep; easing.type: Easing.OutCubic } }
    }
    MouseArea {
        anchors.fill: parent
        enabled: root.interactive
        function at(x) { root.seek(Math.max(0, Math.min(1, x / width))) }
        onPressed: mouse => at(mouse.x)
        onPositionChanged: mouse => { if (pressed) at(mouse.x) }
    }
}
