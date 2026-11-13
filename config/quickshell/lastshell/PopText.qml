import QtQuick

// Body text for popouts, tips and menus: shell text at a given size,
// Theme.text or a dimmed alpha of it. Toned text overrides `color`.
ShellText {
    property real dim: 1     // 1 = full Theme.text; < 1 = Qt.alpha(Theme.text, dim)
    color: dim < 1 ? Qt.alpha(Theme.text, dim) : Theme.text
}
