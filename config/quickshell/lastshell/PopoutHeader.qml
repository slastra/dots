import QtQuick

// Popout title row: bold name, then a toned status word on the same
// baseline (deskpresence · present, deskwatch · all clear).
Row {
    property string title
    property string status
    property color tone: Theme.text
    spacing: 8
    PopText { id: t; size: 14; font.bold: true; text: parent.title }
    PopText { anchors.baseline: t.baseline; size: 13; color: parent.tone; text: parent.status }
}
