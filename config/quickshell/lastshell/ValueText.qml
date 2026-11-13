import QtQuick

// Bar text: shell text at the bar's size, centered in its item's row.
ShellText {
    size: 16
    anchors.verticalCenter: parent.verticalCenter
    Behavior on color { ColorAnimation { duration: Theme.animDuration } }
}
