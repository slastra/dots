import QtQuick

// A lucide glyph inside a drawn ring: the play/pause mark, on the bar and in
// the popouts. Round like the other instruments (clock, quota ring).
Item {
    id: root
    property string name
    property color color: Theme.text
    property int diameter: 18
    width: diameter; height: diameter
    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: "transparent"
        border.width: Math.max(1, Math.round(root.diameter / 20))
        border.color: Qt.alpha(root.color, 0.6)
    }
    LucideIcon {
        anchors.centerIn: parent
        // a triangle's weight sits left of its box; nudge it to look centered
        anchors.horizontalCenterOffset: root.name === "play" ? Math.max(1, root.diameter / 18) / 2 : 0
        name: root.name
        color: root.color
        font.pixelSize: Math.round(root.diameter * 0.52)
    }
}
