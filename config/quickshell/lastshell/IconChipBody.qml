import QtQuick

// An 18 px image centred in a fixed-width slot: taskbar, tray and tab
// chips (which set Chip.contentPadding: 0 and size the slot themselves).
Item {
    property alias source: img.source
    property int slot: 34
    implicitWidth: slot
    // Chip's content slot sits 1 px low for text ink; images carry no such
    // bias, so the body is 2 px shorter to centre on the chip fill instead.
    height: Theme.barHeight - 6
    Image {
        id: img
        anchors.centerIn: parent
        width: 18; height: 18
        sourceSize: Qt.size(36, 36) // decode above device pixels
    }
}
