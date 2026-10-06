import QtQuick

// Month grid for the clock popout. Hand-rolled: Qt.labs.calendar is gone in
// Qt6 and QtQuick.Controls has no MonthGrid outside labs; a 7x6 grid of Text
// is smaller than any import anyway.
Column {
    id: root
    property date shown: new Date()
    spacing: 6

    readonly property var monthStart: new Date(shown.getFullYear(), shown.getMonth(), 1)
    readonly property int daysInMonth: new Date(shown.getFullYear(), shown.getMonth() + 1, 0).getDate()
    // owner passes its clock so the ring moves at midnight without a restart
    property date today: new Date()

    Row {
        spacing: 8
        anchors.horizontalCenter: parent.horizontalCenter
        PopText {
            text: "󰅁"; color: Theme.iris; size: 16
            MouseArea { anchors.fill: parent; onClicked: root.shown = new Date(root.shown.getFullYear(), root.shown.getMonth() - 1, 1) }
        }
        PopText {
            text: Qt.formatDate(root.shown, "MMMM yyyy")
            size: 16; font.bold: true
        }
        PopText {
            text: "󰅂"; color: Theme.iris; size: 16
            MouseArea { anchors.fill: parent; onClicked: root.shown = new Date(root.shown.getFullYear(), root.shown.getMonth() + 1, 1) }
        }
    }

    Grid {
        columns: 7
        spacing: 2

        Repeater {
            model: ["Su","Mo","Tu","We","Th","Fr","Sa"]
            PopText {
                required property string modelData
                text: modelData; width: 30; horizontalAlignment: Text.AlignHCenter
                color: Theme.iris; size: 13
            }
        }
        Repeater {
            model: root.monthStart.getDay() + root.daysInMonth
            Item {
                required property int index
                readonly property int day: index - root.monthStart.getDay() + 1
                readonly property bool isToday: day === root.today.getDate()
                    && root.shown.getMonth() === root.today.getMonth()
                    && root.shown.getFullYear() === root.today.getFullYear()
                width: 30; height: 24
                Rectangle {
                    visible: parent.isToday
                    anchors.fill: parent; radius: Theme.innerRadius; color: Theme.overlay
                    border.color: Theme.rose; border.width: 1
                }
                PopText {
                    anchors.centerIn: parent
                    text: parent.day > 0 ? parent.day : ""
                    color: parent.isToday ? Theme.rose : Theme.text
                    size: 14
                }
            }
        }
    }
}
