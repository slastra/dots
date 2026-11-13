import QtQuick

// One item in a bar zone: content on the zone's plate, no box of its own.
// Hover fills its full height; `active` (the focused workspace, window, tab
// or session) draws a 2 px rule in the accent along the screen edge.
// `edge` names that edge: "top" in the top bar, "bottom" in the bottom bar.
Rectangle {
    id: chip

    property string edge: "bottom"
    property bool active: false
    // Use `present` instead of `visible`: the item fades and narrows out
    // before it actually hides, and the zone closes over it in the same beat.
    property bool present: true
    property color accent: Theme.accent
    // set by the zone: this item sits at the plate's leading or trailing
    // end, so its fill rounds with the plate's corner there
    property bool capStart: false
    property bool capEnd: false
    function recap() {
        for (let p = parent; p; p = p.parent)
            if (typeof p.cap === "function") { Qt.callLater(p.cap); return }
    }
    onXChanged: recap()
    onWidthChanged: recap()
    onVisibleChanged: recap()
    property alias hovered: mouse.containsMouse
    // horizontal room around the content; 0 for content that carries its own
    property int contentPadding: 12
    // a hairline on the item's leading edge, dividing it from its neighbor
    // (the first item's falls on the plate's own border). Off for the icon
    // strips (tabs, tasks, tray), which carry no padding and read as one group.
    property bool separator: contentPadding > 0
    default property alias content: contentSlot.data

    signal clicked()
    signal rightClicked()
    signal wheelUp()
    signal wheelDown()

    implicitWidth: contentSlot.childrenRect.width + 2 * contentPadding
    // Uniform by construction: every item is exactly this tall.
    height: Theme.barHeight - 2

    color: "transparent"
    Rectangle { // the hover fill, kept inside the plate's
                // hairline where the item touches it so a rounded corner
                // shows no fringe of fill outside the frame
        anchors.fill: parent
        anchors.leftMargin: chip.capStart ? Theme.hairline : 0
        anchors.rightMargin: chip.capEnd ? Theme.hairline : 0
        anchors.topMargin: chip.edge === "top" ? 0 : Theme.hairline
        anchors.bottomMargin: chip.edge === "top" ? Theme.hairline : 0
        topLeftRadius: chip.capStart && chip.edge !== "top" ? Theme.insetRadius : 0
        topRightRadius: chip.capEnd && chip.edge !== "top" ? Theme.insetRadius : 0
        bottomLeftRadius: chip.capStart && chip.edge === "top" ? Theme.insetRadius : 0
        bottomRightRadius: chip.capEnd && chip.edge === "top" ? Theme.insetRadius : 0
        color: mouse.containsMouse ? Theme.overlay : Theme.clear(Theme.overlay)
        Behavior on color { ColorAnimation { duration: Theme.animDuration } }
    }

    property real widthFactor: 0
    width: Math.round(implicitWidth * widthFactor)
    clip: widthFactor < 1
    visible: present || exitAnim.running
    opacity: 0

    onPresentChanged: {
        if (present) { exitAnim.stop(); enterAnim.restart() }
        else       { enterAnim.stop(); exitAnim.restart() }
    }
    // Repeater-created items (tabs, tasks, tray, sessions) and startup: the
    // enter animation runs on completion, so every appearance eases in.
    Component.onCompleted: if (present) enterAnim.start()

    ParallelAnimation {
        id: enterAnim
        NumberAnimation { target: chip; property: "opacity"; to: 1; duration: Theme.slideDuration; easing.type: Easing.OutCubic }
        NumberAnimation { target: chip; property: "widthFactor"; to: 1; duration: Theme.slideDuration; easing.type: Easing.OutCubic }
    }
    ParallelAnimation {
        id: exitAnim
        NumberAnimation { target: chip; property: "opacity"; to: 0; duration: Theme.slideDuration; easing.type: Easing.InCubic }
        NumberAnimation { target: chip; property: "widthFactor"; to: 0; duration: Theme.slideDuration; easing.type: Easing.InCubic }
    }

    Rectangle { // the separator
        // not on the plate's first item: the plate's own frame is there,
        // and a straight line would cut across its rounded corner
        visible: chip.separator && !chip.capStart
        width: Theme.hairline
        height: parent.height
        color: Theme.border
    }

    Rectangle { // the active rule
        width: parent.width
        height: 2
        y: chip.edge === "top" ? 0 : parent.height - height
        color: chip.accent
        opacity: chip.active ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.animDuration } }
    }

    Item {
        id: contentSlot
        anchors.fill: parent
        // text ink rides high in its em box; one uniform pixel down
        // centers every item's ensemble optically (measured, not felt)
        anchors.topMargin: 1
        anchors.leftMargin: chip.contentPadding
        anchors.rightMargin: chip.contentPadding
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        hoverEnabled: true
        onClicked: mouse => mouse.button === Qt.RightButton ? chip.rightClicked() : chip.clicked()
        onWheel: wheel => wheel.angleDelta.y > 0 ? chip.wheelUp() : chip.wheelDown()
    }
}
