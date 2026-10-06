import QtQuick

// Body text for popouts, tips and menus: the shell font at a given size,
// Theme.text or a dimmed alpha of it. Toned text overrides `color`.
Text {
    property int size: 13
    property real dim: 1     // 1 = full Theme.text; < 1 = Qt.alpha(Theme.text, dim)
    font.family: Theme.fontFamily
    font.pixelSize: size
    color: dim < 1 ? Qt.alpha(Theme.text, dim) : Theme.text
}
