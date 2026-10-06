import QtQuick

// The signature lastshell element: a tab chip hanging off a screen edge.
// Surface fill, 2px overlay border on three sides, rounded on the far
// corners, OPEN on the screen-edge side so the chip reads as attached.
// `edge` names the open side: a top-bar chip has edge "top" (hangs down,
// bottom corners round); a bottom-bar chip has edge "bottom".
Rectangle {
    id: chip

    property string edge: "bottom"
    property bool active: false
    // Use `present` instead of `visible`: the chip slides out of its screen
    // edge before it actually hides, and slides back in on show. Bottom-bar
    // chips rise from below the bar, top-bar chips drop from above it.
    property bool present: true
    // Border accent when active; rose is the identity accent, sys chips
    // pass foam-family accents through their text instead and keep rose here.
    property color accent: Theme.rose
    property alias hovered: mouse.containsMouse
    // horizontal room around the content; 0 for content that carries its own
    property int contentPadding: 12
    default property alias content: contentSlot.data

    signal clicked()
    signal rightClicked()
    signal wheelUp()
    signal wheelDown()

    implicitWidth: inner.implicitWidth + 4
    // Uniform by construction: every chip is exactly this tall, so no
    // instance can drift a pixel from its neighbours.
    height: Theme.barHeight - 2

    color: active ? accent : Theme.border

    readonly property real slideOffset: edge === "bottom" ? height : -height
    // width collapses with the slide so neighbours glide in the same beat
    property real widthFactor: 0
    width: Math.round(implicitWidth * widthFactor)
    clip: widthFactor < 1
    visible: present || exitAnim.running
    transform: Translate { id: slide; y: chip.slideOffset }
    opacity: 0

    onPresentChanged: {
        if (present) { exitAnim.stop(); enterAnim.restart() }
        else       { enterAnim.stop(); exitAnim.restart() }
    }
    // Repeater-created chips (tabs, tasks, tray, sessions) and startup: the
    // enter animation runs on completion, so every appearance slides in.
    Component.onCompleted: if (present) enterAnim.start()

    ParallelAnimation {
        id: enterAnim
        NumberAnimation { target: slide; property: "y"; to: 0; duration: Theme.slideDuration; easing.type: Easing.OutCubic }
        NumberAnimation { target: chip; property: "opacity"; to: 1; duration: Theme.slideDuration; easing.type: Easing.OutCubic }
        NumberAnimation { target: chip; property: "widthFactor"; to: 1; duration: Theme.slideDuration; easing.type: Easing.OutCubic }
    }
    ParallelAnimation {
        id: exitAnim
        NumberAnimation { target: slide; property: "y"; to: chip.slideOffset; duration: Theme.slideDuration; easing.type: Easing.InCubic }
        NumberAnimation { target: chip; property: "opacity"; to: 0; duration: Theme.slideDuration; easing.type: Easing.InCubic }
        NumberAnimation { target: chip; property: "widthFactor"; to: 0; duration: Theme.slideDuration; easing.type: Easing.InCubic }
    }
    topLeftRadius: edge === "bottom" ? Theme.overlayRadius : 0
    topRightRadius: edge === "bottom" ? Theme.overlayRadius : 0
    bottomLeftRadius: edge === "top" ? Theme.overlayRadius : 0
    bottomRightRadius: edge === "top" ? Theme.overlayRadius : 0

    Behavior on color { ColorAnimation { duration: Theme.animDuration } }

    Rectangle {
        id: inner
        anchors.fill: parent
        anchors.topMargin: chip.edge === "bottom" ? 2 : 0
        anchors.bottomMargin: chip.edge === "top" ? 2 : 0
        anchors.leftMargin: 2
        anchors.rightMargin: 2
        topLeftRadius: chip.topLeftRadius > 0 ? Theme.overlayRadius - 2 : 0
        topRightRadius: chip.topRightRadius > 0 ? Theme.overlayRadius - 2 : 0
        bottomLeftRadius: chip.bottomLeftRadius > 0 ? Theme.overlayRadius - 2 : 0
        bottomRightRadius: chip.bottomRightRadius > 0 ? Theme.overlayRadius - 2 : 0
        color: mouse.containsMouse ? Theme.overlay : Theme.surface
        implicitWidth: contentSlot.childrenRect.width + 2 * chip.contentPadding
        Behavior on color { ColorAnimation { duration: Theme.animDuration } }

        Item {
            id: contentSlot
            anchors.fill: parent
            // text ink rides high in its em box; one uniform pixel down
            // centers every chip's ensemble optically (measured, not felt)
            anchors.topMargin: 1
            anchors.leftMargin: chip.contentPadding
            anchors.rightMargin: chip.contentPadding
        }
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
