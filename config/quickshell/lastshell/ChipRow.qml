import QtQuick

// A row of bar items. With `plate` it is a ZONE: one flat surface flush to
// the screen edge, a hairline on its three open sides, the items laid out
// inside with nothing between them but space. Neighbours glide rather than
// jump when an item appears or leaves (the item handles its own fade, see
// Chip), and a zone with nothing in it is not drawn.
Item {
    id: zone

    property bool plate: false
    property string edge: "top"          // the screen edge a plate sits on
    property alias spacing: row.spacing
    default property alias content: row.data

    implicitWidth: row.width
    implicitHeight: plate ? Theme.barHeight - 2 : row.height

    Rectangle { // the plate
        visible: zone.plate && row.width > 0
        anchors.fill: parent
        color: Theme.surface
        // only the corners away from the screen edge round
        topLeftRadius: zone.edge === "top" ? 0 : Theme.overlayRadius
        topRightRadius: topLeftRadius
        bottomLeftRadius: zone.edge === "top" ? Theme.overlayRadius : 0
        bottomRightRadius: bottomLeftRadius
    }

    Row {
        id: row
        move: Transition { NumberAnimation { properties: "x"; duration: Theme.slideDuration; easing.type: Easing.OutCubic } }
        add:  Transition { NumberAnimation { properties: "x"; duration: Theme.slideDuration; easing.type: Easing.OutCubic } }
    }

    Rectangle { // its hairline, over the items so a hover fill cannot break it;
                // the side on the screen edge hangs one pixel off the screen
        visible: zone.plate && row.width > 0
        x: 0; width: parent.width
        y: zone.edge === "top" ? -Theme.hairline : 0
        height: parent.height + Theme.hairline
        color: "transparent"
        border.color: Theme.border
        border.width: Theme.hairline
        topLeftRadius: zone.edge === "top" ? 0 : Theme.overlayRadius
        topRightRadius: topLeftRadius
        bottomLeftRadius: zone.edge === "top" ? Theme.overlayRadius : 0
        bottomRightRadius: bottomLeftRadius
    }
}
