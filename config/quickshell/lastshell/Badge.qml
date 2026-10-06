import QtQuick

// 16 px count pill beside a chip glyph: agent count (iris), attention
// count (love). Overlay fill, tone-tinted border, tone text.
Rectangle {
    property string text
    property color tone: Theme.iris
    width: t.implicitWidth + 10
    height: 16
    radius: 8
    color: Theme.overlay
    border.color: Qt.alpha(tone, 0.6)
    border.width: 1
    PopText { id: t; anchors.centerIn: parent; size: 11; color: parent.tone; text: parent.text }
}
