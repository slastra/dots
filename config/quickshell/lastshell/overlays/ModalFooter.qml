import QtQuick
import ".."  // root module

// The seam and 32 px band at the bottom of a modal: key hints left in
// dim iris, a count right in dim text.
Item {
    property string hint
    property string count: ""

    width: parent.width
    height: 33

    Rectangle { width: parent.width; height: 1; color: Theme.seam }
    Rectangle {
        y: 1
        width: parent.width
        height: 32
        bottomLeftRadius: Theme.innerRadius
        bottomRightRadius: Theme.innerRadius
        color: Qt.alpha(Theme.overlay, 0.55)

        PopText {
            anchors.left: parent.left
            anchors.leftMargin: 18
            anchors.verticalCenter: parent.verticalCenter
            size: 12
            color: Qt.alpha(Theme.iris, 0.55)
            text: parent.parent.hint
        }
        PopText {
            anchors.right: parent.right
            anchors.rightMargin: 18
            anchors.verticalCenter: parent.verticalCenter
            size: 12
            dim: 0.4
            text: parent.parent.count
        }
    }
}
