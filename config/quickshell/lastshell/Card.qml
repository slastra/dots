import QtQuick

// The floating surface every popup shares: surface fill, 2 px border,
// overlay radius. Popout, ChipTip and TrayMenu cards, the OSD pill.
Rectangle {
    radius: Theme.overlayRadius
    color: Theme.surface
    border.color: Theme.border
    border.width: 2
}
