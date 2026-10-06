import QtQuick
import ".."  // root module

// The 54 px band at the top of a modal: identity glyph, optional title,
// optional chevron-led query, and the seam under it. Extra children
// (a clear-all button) land in the band and may anchor to it.
Item {
    id: root
    property string icon
    property string title: ""
    property string query: ""
    property bool showQuery: true
    property bool active: true
    default property alias extras: band.data

    width: parent.width
    height: 55

    Rectangle {
        id: band
        width: parent.width
        height: 54
        topLeftRadius: Theme.innerRadius
        topRightRadius: Theme.innerRadius
        color: Theme.overlay

        Row {
            anchors.verticalCenter: parent.verticalCenter
            x: 18
            spacing: 12

            LucideIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: root.icon
                font.pixelSize: 18
                color: Theme.rose
            }
            PopText {
                visible: root.title !== ""
                anchors.verticalCenter: parent.verticalCenter
                size: 16; font.bold: true
                text: root.title
            }
            LucideIcon { // chevron leads from identity into the input
                visible: root.showQuery
                anchors.verticalCenter: parent.verticalCenter
                name: "chevron-right"
                font.pixelSize: 14
                color: Theme.textFaint
            }
            QueryInput {
                visible: root.showQuery
                anchors.verticalCenter: parent.verticalCenter
                text: root.query
                active: root.active
            }
        }
    }
    Rectangle { y: 54; width: parent.width; height: 1; color: Theme.seam }
}
