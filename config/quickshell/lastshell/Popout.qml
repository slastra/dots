import Quickshell
import QtQuick

// Hover popout attached to a chip: a card hanging flush off the bar edge.
// Shows while the chip OR the card is hovered, with a grace timer so the
// pointer can travel between them. Never QtQuick ToolTip — that renders
// inside the bar window and clips.
//
// Every popout is the same sheet, top to bottom:
//
//   title ......... status     what this is, and its reading right now
//   ──────────────────────
//   body                       rows (KeyValueRow), meters, graphs, lists;
//                              a Divider between unrelated groups
//   ──────────────────────
//   note                       how to act on it, or where the data is from
//
// Type: title 14 bold, body 13, secondary 12 dimmed, note 11 faint. Width is
// one of Theme.popS / popM / popL. Children are the body and can size
// themselves with `width: parent.width`.
PopupWindow {
    id: root

    required property Chip owner          // the chip; edge and hover follow it
    property string edge: owner.edge
    property bool ownerHovered: owner.hovered

    property string title: ""
    property string status: ""
    property color tone: Theme.text      // the status word's color
    property string note: ""
    property int sheetWidth: Theme.popS
    property int spacing: 8
    default property alias content: body.data

    readonly property bool shouldShow: ownerHovered || cardHover.hovered

    implicitWidth: card.implicitWidth
    implicitHeight: card.implicitHeight + Theme.popoutGap
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
        attach: root.edge
        // the window spans chip edge to card; the gap is its transparent end
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.edge === "top" ? Theme.popoutGap : 0
        implicitWidth: sheet.width + 2 * Theme.popPad
        implicitHeight: sheet.height + 2 * Theme.popPad

        opacity: open ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.animDuration; easing.type: Easing.OutCubic } }
        onOpacityChanged: if (opacity === 0 && !open) root.visible = false

        Column {
            id: sheet
            x: Theme.popPad; y: Theme.popPad
            width: root.sheetWidth
            spacing: root.spacing

            PopoutHeader {
                visible: root.title !== ""
                width: parent.width
                title: root.title
                status: root.status
                tone: root.tone
            }
            Divider { visible: root.title !== "" && body.height > 0; width: parent.width }
            Column {
                id: body
                visible: height > 0
                width: parent.width
                spacing: root.spacing
            }
            Divider { visible: root.note !== ""; width: parent.width }
            PopNote { visible: root.note !== ""; width: parent.width; text: root.note }
        }

        HoverHandler { id: cardHover }
    }
}
