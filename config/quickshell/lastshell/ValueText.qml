import QtQuick

// Chip value text. ShureTechMono's digits and caps leave the descender
// space unused, so a vertically-centered em box carries its ink high;
// +0.75 logical px puts the INK on the icons' measured center line
// (text ran 18.0 device, icons 19.0 — bar-m2 measurement, 2026-08-31).
Text {
    anchors.verticalCenter: parent.verticalCenter
    anchors.verticalCenterOffset: 0.75
    font.family: Theme.fontFamily
    font.pixelSize: 16
    color: Theme.text
    Behavior on color { ColorAnimation { duration: Theme.animDuration } }
}
