import QtQuick

// One-of-n picker: equal segments, the current one rose-outlined (Eco's CPU
// profile, the reader's tidy mode). `options` is [{value, label}]; a click
// emits picked(value) and the owner decides what `current` becomes.
Row {
    id: root
    property var options: []
    property var current
    property bool enabled: true
    property int segmentHeight: 30
    signal picked(var value)

    spacing: 6
    opacity: enabled ? 1 : 0.45

    Repeater {
        model: root.options
        Rectangle {
            required property var modelData
            readonly property bool selected: root.current === modelData.value
            width: (root.width - root.spacing * (root.options.length - 1)) / root.options.length
            height: root.segmentHeight
            radius: Theme.innerRadius
            color: selected ? Qt.alpha(Theme.rose, 0.18) : hover.hovered ? Theme.border : Theme.overlay
            border.color: selected ? Theme.rose : "transparent"
            border.width: 1
            Behavior on color { ColorAnimation { duration: Theme.animDuration } }
            PopText {
                anchors.centerIn: parent
                size: 12
                color: parent.selected ? Theme.rose : Theme.textMuted
                text: parent.modelData.label
            }
            HoverHandler { id: hover; enabled: root.enabled; cursorShape: Qt.PointingHandCursor }
            TapHandler { enabled: root.enabled; onTapped: root.picked(parent.modelData.value) }
        }
    }
}
