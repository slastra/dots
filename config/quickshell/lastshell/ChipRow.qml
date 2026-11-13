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
        // inside the hairline drawn over it, so no fill fringes the frame
        anchors.fill: parent
        anchors.leftMargin: Theme.hairline
        anchors.rightMargin: Theme.hairline
        anchors.topMargin: zone.edge === "top" ? 0 : Theme.hairline
        anchors.bottomMargin: zone.edge === "top" ? Theme.hairline : 0
        color: Theme.surface
        // only the corners away from the screen edge round
        topLeftRadius: zone.edge === "top" ? 0 : Theme.insetRadius
        topRightRadius: topLeftRadius
        bottomLeftRadius: zone.edge === "top" ? Theme.insetRadius : 0
        bottomRightRadius: bottomLeftRadius
    }

    // Tell the items at either end of the plate to round with its corners,
    // so a hover fill does not poke past them. Items can sit
    // several levels down (a nested row, a Repeater), so this walks the
    // tree and asks each where it landed.
    // Items call this as they move or resize (the row's own transitions
    // slide them after its width has settled); a row nested in a plate
    // passes it up.
    function cap() {
        if (!plate) {
            for (let p = parent; p; p = p.parent)
                if (p.plate === true && typeof p.cap === "function") { Qt.callLater(p.cap); break }
            return
        }
        const walk = it => {
            for (const c of it.children) {
                if (c.capStart !== undefined && c.capEnd !== undefined) {
                    if (!c.visible) continue
                    const x = c.mapToItem(zone, 0, 0).x
                    c.capStart = x < 1
                    c.capEnd = x + c.width > zone.width - 1
                } else walk(c)
            }
        }
        walk(row)
    }
    onWidthChanged: Qt.callLater(cap)
    onXChanged: if (!plate) Qt.callLater(cap)
    Component.onCompleted: Qt.callLater(cap)

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
