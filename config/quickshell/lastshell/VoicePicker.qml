import QtQuick

// A voice list for one of the voice popout's lanes (VoiceChip): five rows
// tall, scrolling, the current voice outlined in the lane's colour. Picking
// is the lane's business (deskvoice's voice op, or the reader's own).
ListView {
    id: root
    property var voices: []          // [{key, label}]
    property string current: ""
    property color tone: Theme.rose
    signal picked(string key)

    readonly property int rowH: 26
    height: Math.min(count, 5) * (rowH + 2)
    clip: true
    spacing: 2
    boundsBehavior: Flickable.StopAtBounds
    model: voices
    currentIndex: voices.findIndex(v => v.key === current)
    Component.onCompleted: positionViewAtIndex(currentIndex, ListView.Center)

    delegate: Rectangle {
        required property var modelData
        readonly property bool isCurrent: modelData.key === root.current
        width: root.width
        height: root.rowH
        radius: Theme.innerRadius
        color: hover.hovered ? Theme.overlay : "transparent"
        border.color: isCurrent ? Qt.alpha(root.tone, 0.6) : "transparent"
        border.width: 1
        PopText {
            x: 18
            width: parent.width - 28
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            size: 12
            color: parent.isCurrent ? root.tone : Theme.text
            text: parent.modelData.label
        }
        HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.picked(parent.modelData.key) }
    }
}
