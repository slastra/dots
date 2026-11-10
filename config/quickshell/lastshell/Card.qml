import QtQuick

// The floating surface every popup shares: surface fill, a hairline border,
// the overlay radius. Popout, ChipTip and TrayMenu cards, the OSD.
// `attach` names the bar a card hangs flush from ("top" or "bottom"); the
// corners on that side stay square so it reads as part of the plate.
Rectangle {
    property string attach: ""
    radius: Theme.overlayRadius
    topLeftRadius: attach === "top" ? 0 : Theme.overlayRadius
    topRightRadius: topLeftRadius
    bottomLeftRadius: attach === "bottom" ? 0 : Theme.overlayRadius
    bottomRightRadius: bottomLeftRadius
    color: Theme.surface
    border.color: Theme.border
    border.width: Theme.hairline
}
