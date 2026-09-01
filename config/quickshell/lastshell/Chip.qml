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
    // Border accent when active; rose is the identity accent, sys chips
    // pass foam-family accents through their text instead and keep rose here.
    property color accent: Theme.rose
    property alias hovered: mouse.containsMouse
    default property alias content: contentSlot.data

    signal clicked()
    signal rightClicked()
    signal wheelUp()
    signal wheelDown()

    implicitWidth: inner.implicitWidth + 4
    // Uniform by construction: every chip is exactly this tall, so no
    // instance can drift a pixel from its neighbours.
    height: Theme.barHeight - 2

    color: active ? accent : Theme.overlay
    topLeftRadius: edge === "bottom" ? 8 : 0
    topRightRadius: edge === "bottom" ? 8 : 0
    bottomLeftRadius: edge === "top" ? 8 : 0
    bottomRightRadius: edge === "top" ? 8 : 0

    Behavior on color { ColorAnimation { duration: Theme.animDuration } }

    Rectangle {
        id: inner
        anchors.fill: parent
        anchors.topMargin: chip.edge === "bottom" ? 2 : 0
        anchors.bottomMargin: chip.edge === "top" ? 2 : 0
        anchors.leftMargin: 2
        anchors.rightMargin: 2
        topLeftRadius: chip.topLeftRadius > 0 ? 6 : 0
        topRightRadius: chip.topRightRadius > 0 ? 6 : 0
        bottomLeftRadius: chip.bottomLeftRadius > 0 ? 6 : 0
        bottomRightRadius: chip.bottomRightRadius > 0 ? 6 : 0
        color: mouse.containsMouse ? Theme.overlay : Theme.surface
        implicitWidth: contentSlot.childrenRect.width
        Behavior on color { ColorAnimation { duration: Theme.animDuration } }

        Item {
            id: contentSlot
            anchors.fill: parent
            // text ink rides high in its em box; one uniform pixel down
            // centers every chip's ensemble optically (measured, not felt)
            anchors.topMargin: 1
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
