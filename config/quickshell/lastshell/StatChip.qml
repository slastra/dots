import QtQuick

// A value and a Lucide glyph in one tone: the stat cluster's shape (net,
// cpu, disk, mem, weather, hdr). Popout/ChipTip children still land in
// the chip's content slot as with any Chip.
Chip {
    id: root
    property string value
    property string icon
    property color tone: Theme.text

    ChipBody {
        ValueText { color: root.tone; text: root.value }
        LucideIcon {
            anchors.verticalCenter: parent.verticalCenter
            name: root.icon
            color: root.tone
            visible: root.icon !== ""
        }
    }
}
