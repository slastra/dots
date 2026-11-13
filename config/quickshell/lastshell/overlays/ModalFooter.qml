import QtQuick
import ".."  // root module

// The seam and 32 px band at the bottom of a modal: key hints left and a
// count right, both in the secondary color.
Item {
    property string hint
    property string count: ""

    width: parent.width
    height: 33

    Rectangle { width: parent.width; height: Theme.hairline; color: Theme.seam }
    Rectangle {
        y: 1
        width: parent.width
        height: 32
        bottomLeftRadius: Theme.bandRadius
        bottomRightRadius: Theme.bandRadius
        color: Qt.alpha(Theme.overlay, 0.55)

        PopText {
            anchors.left: parent.left
            anchors.leftMargin: 18
            anchors.verticalCenter: parent.verticalCenter
            size: 12
            color: Theme.secondary
            text: parent.parent.hint
        }
        PopText {
            anchors.right: parent.right
            anchors.rightMargin: 18
            anchors.verticalCenter: parent.verticalCenter
            size: 12
            color: Theme.secondary
            text: parent.parent.count
        }
    }
}
