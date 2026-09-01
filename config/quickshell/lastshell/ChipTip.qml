import Quickshell
import QtQuick

// Tooltip as a real popup window: QtQuick Controls ToolTip renders inside
// the 30px bar window and clips, so every chip tooltip goes through this.
// Delay-on-hover, instant hide, multi-line capable.
PopupWindow {
    id: root

    required property Item owner
    property string edge: "top"
    property bool ownerHovered: false
    property string text: ""

    visible: false
    color: "transparent"
    implicitWidth: card.width
    implicitHeight: card.height

    anchor {
        item: owner
        edges: edge === "top" ? Edges.Bottom : Edges.Top
        gravity: edge === "top" ? Edges.Bottom : Edges.Top
    }

    onOwnerHoveredChanged: ownerHovered ? showTimer.restart() : hide()
    onTextChanged: if (text === "") hide()
    function hide() { showTimer.stop(); visible = false }
    Timer {
        id: showTimer
        interval: 400
        onTriggered: if (root.ownerHovered && root.text !== "") root.visible = true
    }

    Rectangle {
        id: card
        width: tip.implicitWidth + 20
        height: tip.implicitHeight + 14
        radius: 6
        color: Theme.surface
        border.color: Theme.overlay
        border.width: 2

        Text {
            id: tip
            anchors.centerIn: parent
            text: root.text
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: 13
            textFormat: Text.PlainText
        }
    }
}
