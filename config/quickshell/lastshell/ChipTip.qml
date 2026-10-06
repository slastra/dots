import Quickshell
import QtQuick

// Tooltip as a real popup window: QtQuick Controls ToolTip renders inside
// the bar window and clips, so every chip tooltip goes through this.
// Delay-on-hover, instant hide, multi-line capable.
PopupWindow {
    id: root

    required property Chip owner          // edge and hover follow it
    property string edge: owner.edge
    property bool ownerHovered: owner.hovered
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
        interval: Theme.tipDelay
        onTriggered: if (root.ownerHovered && root.text !== "") root.visible = true
    }

    Card {
        id: card
        width: tip.implicitWidth + 20
        height: tip.implicitHeight + 14

        PopText {
            id: tip
            anchors.centerIn: parent
            text: root.text
            size: 13
            textFormat: Text.PlainText
        }
    }
}
