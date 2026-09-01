import QtQuick

// Text preset for chip contents: the bar font at bar size, vertically
// centered by the parent. `padRight` compensates trailing Nerd Font glyphs
// (waybar carried padding-right:17px for the same reason).
Text {
    property int padRight: 0
    font.family: Theme.fontFamily
    font.pixelSize: 16
    color: Theme.text
    verticalAlignment: Text.AlignVCenter
    rightPadding: padRight
    leftPadding: 12
    Behavior on color { ColorAnimation { duration: Theme.animDuration } }
}
