import QtQuick

// The bottom bar: browser tabs left, (mpris + claude strip to come) right.
// One window, one exclusive zone — content items only below here.
BarWindow {
    anchors.bottom: true

    TabStrip {
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.leftMargin: 8
    }

    ClaudeStrip {
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
    }

    MprisChip {
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        anchors.rightMargin: 8
    }
}
