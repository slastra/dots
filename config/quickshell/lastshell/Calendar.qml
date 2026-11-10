import QtQuick

// Month grid for the clock popout. Hand-rolled: Qt.labs.calendar is gone in
// Qt6 and QtQuick.Controls has no MonthGrid outside labs; a 7x6 grid of Text
// is smaller than any import anyway.
Column {
    id: root
    property date shown: new Date()
    spacing: 8
    width: parent ? parent.width : implicitWidth

    readonly property var monthStart: new Date(shown.getFullYear(), shown.getMonth(), 1)
    readonly property int daysInMonth: new Date(shown.getFullYear(), shown.getMonth() + 1, 0).getDate()
    // owner passes its clock so the ring moves at midnight without a restart
    property date today: new Date()

    Item { // the sheet's header: month on the left, the arrows on the right
        width: parent.width
        height: month.implicitHeight
        PopText {
            id: month
            text: Qt.formatDate(root.shown, "MMMM yyyy").toLowerCase()
            size: 14; font.bold: true
        }
        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 12
            PopText {
                text: "󰅁"; color: Theme.textMuted; size: 14
                MouseArea { anchors.fill: parent; anchors.margins: -4; onClicked: root.shown = new Date(root.shown.getFullYear(), root.shown.getMonth() - 1, 1) }
            }
            PopText {
                text: "󰅂"; color: Theme.textMuted; size: 14
                MouseArea { anchors.fill: parent; anchors.margins: -4; onClicked: root.shown = new Date(root.shown.getFullYear(), root.shown.getMonth() + 1, 1) }
            }
        }
    }
    Divider { width: parent.width }

    Grid {
        id: grid
        columns: 7
        spacing: 0
        readonly property real cell: Math.floor(root.width / 7)

        Repeater {
            model: ["Su","Mo","Tu","We","Th","Fr","Sa"]
            PopText {
                required property string modelData
                text: modelData.toLowerCase(); width: grid.cell; horizontalAlignment: Text.AlignHCenter
                dim: 0.55; size: 12
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
                width: grid.cell; height: 24
                Rectangle {
                    visible: parent.isToday
                    anchors.fill: parent; radius: Theme.innerRadius; color: Theme.overlay
                    border.color: Theme.accent; border.width: 1
                }
                PopText {
                    anchors.centerIn: parent
                    text: parent.day > 0 ? parent.day : ""
                    color: parent.isToday ? Theme.accent : Theme.text
                    size: 13
                }
            }
        }
    }
}
