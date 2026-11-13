import QtQuick

// An 18 px image centred in a fixed-width slot: taskbar, tray and tab
// chips (which set Chip.contentPadding: 0 and size the slot themselves).
// With `placeholder`, a slot with no image to show draws a question mark
// in a hairline square instead of sitting empty.
Item {
    id: root
    property alias source: img.source
    property int slot: 34
    property bool placeholder: false    // draw the tile when there is no image

    readonly property bool missing: placeholder
        && (img.source.toString() === "" || img.status === Image.Error)
    implicitWidth: slot
    // Chip's content slot sits 1 px low for text ink; images carry no such
    // bias, so the body is 2 px shorter to centre on the chip fill instead.
    height: Theme.barHeight - 6
    Image {
        id: img
        anchors.centerIn: parent
        width: 18; height: 18
        sourceSize: Qt.size(36, 36) // decode above device pixels
        visible: !root.missing
    }
    Rectangle { // the placeholder tile
        visible: root.missing
        anchors.centerIn: parent
        width: 18; height: 18
        radius: Math.min(Theme.innerRadius, 4)
        color: Theme.overlay
        border.color: Theme.border
        border.width: Theme.hairline
        PopText {
            anchors.centerIn: parent
            size: 12; font.bold: true
            text: "?"
        }
    }
}
