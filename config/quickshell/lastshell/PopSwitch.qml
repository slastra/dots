import QtQuick

// A setting in a popout: an optional icon and the name on the left, a muted
// word for its state and a drawn switch on the right. The whole row is the
// hit target, and its hover fill bleeds past the sheet's text edge so the
// text itself stays on it.
Rectangle {
    id: row
    property string icon
    property bool on
    property string label
    property string word        // muted word beside the switch
    signal clicked()
    x: -6
    width: parent.width + 12
    height: 28
    color: area.containsMouse ? Theme.overlay : Theme.clear(Theme.overlay)
    Behavior on color { ColorAnimation { duration: Theme.animDuration } }
    Row {
        anchors.verticalCenter: parent.verticalCenter
        x: 6
        spacing: 8
        LucideIcon {
            visible: row.icon !== ""
            anchors.verticalCenter: parent.verticalCenter
            name: row.icon
            color: row.on ? Theme.accent : Qt.alpha(Theme.text, 0.45)
        }
        PopText {
            anchors.verticalCenter: parent.verticalCenter
            text: row.label
            size: 13
        }
    }
    Row {
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right
        anchors.rightMargin: 6
        spacing: 8
        PopText {
            anchors.verticalCenter: parent.verticalCenter
            text: row.word
            color: row.on ? Qt.alpha(Theme.accent, 0.9) : Qt.alpha(Theme.text, 0.45)
            size: 12
            Behavior on color { ColorAnimation { duration: Theme.animDuration } }
        }
        // switch: track + knob, gold when on
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 30; height: 16
            color: row.on ? Qt.alpha(Theme.accent, 0.35) : Qt.alpha(Theme.text, 0.12)
            border.width: 1
            border.color: row.on ? Theme.accent : Qt.alpha(Theme.text, 0.25)
            Behavior on color { ColorAnimation { duration: Theme.animDuration } }
            Behavior on border.color { ColorAnimation { duration: Theme.animDuration } }
            Rectangle {
                width: 10; height: 10
                y: 3
                x: row.on ? parent.width - width - 3 : 3
                color: row.on ? Theme.accent : Qt.alpha(Theme.text, 0.5)
                Behavior on x { NumberAnimation { duration: Theme.animDuration; easing.type: Easing.OutCubic } }
                Behavior on color { ColorAnimation { duration: Theme.animDuration } }
            }
        }
    }
    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: row.clicked()
    }
    opacity: enabled ? 1 : 0.4
}
