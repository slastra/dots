import Quickshell
import QtQuick

// Hover popout attached to a chip: a floating card just off the bar edge.
// Shows while the chip OR the card is hovered, with a grace timer so the
// pointer can travel across the gap. Never QtQuick ToolTip — that renders
// inside the bar window and clips.
PopupWindow {
    id: root

    required property Chip owner          // the chip; edge and hover follow it
    property string edge: owner.edge
    property bool ownerHovered: owner.hovered
    default property alias content: inner.data

    readonly property bool shouldShow: ownerHovered || cardHover.hovered

    implicitWidth: card.implicitWidth
    implicitHeight: card.implicitHeight
    color: "transparent"
    visible: false

    anchor {
        item: owner
        edges: edge === "top" ? Edges.Bottom : Edges.Top
        gravity: edge === "top" ? Edges.Bottom : Edges.Top
    }

    onShouldShowChanged: {
        if (shouldShow) { hideTimer.stop(); visible = true; card.open = true }
        else hideTimer.restart()
    }
    Timer {
        id: hideTimer
        interval: Theme.popoutGrace
        onTriggered: if (!root.shouldShow) card.open = false
    }

    Card {
        id: card
        property bool open: false
        anchors.centerIn: parent
        implicitWidth: inner.childrenRect.width + 24
        implicitHeight: inner.childrenRect.height + 24

        opacity: open ? 1 : 0
        scale: open ? 1 : 0.96
        Behavior on opacity { NumberAnimation { duration: Theme.animDuration; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: Theme.animDuration; easing.type: Easing.OutCubic } }
        onOpacityChanged: if (opacity === 0 && !open) root.visible = false

        Item {
            id: inner
            x: 12; y: 12
            width: parent.width - 24
            height: parent.height - 24
        }

        HoverHandler { id: cardHover }
    }
}
