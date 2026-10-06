import QtQuick
import ".."  // root module

// The typed query with a blinking rose caret riding its right edge.
Row {
    id: root
    property string text
    property bool active: true   // caret blinks only while the modal is open
    spacing: 2

    PopText {
        anchors.verticalCenter: parent.verticalCenter
        size: 17
        text: root.text
    }
    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: 2; height: 22; color: Theme.rose
        SequentialAnimation on opacity {
            running: root.active; loops: Animation.Infinite
            NumberAnimation { to: 0; duration: Theme.blinkDuration }
            NumberAnimation { to: 1; duration: Theme.blinkDuration }
        }
    }
}
