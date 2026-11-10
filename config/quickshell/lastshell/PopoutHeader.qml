import QtQuick

// Popout title row: the bold name on the left, its reading or verdict on the
// right in a tone (network · 192.168.1.4, deskwatch · all clear). The title
// gives way when the two do not fit.
Item {
    id: root
    property string title
    property string status
    property color tone: Theme.text
    implicitHeight: t.implicitHeight
    PopText {
        id: t
        width: Math.min(implicitWidth, root.width - (s.visible ? s.width + 12 : 0))
        elide: Text.ElideMiddle
        size: 14; font.bold: true
        text: root.title
    }
    PopText {
        id: s
        visible: text !== ""
        anchors.right: parent.right
        anchors.baseline: t.baseline
        width: Math.min(implicitWidth, root.width * 0.7)
        elide: Text.ElideRight
        color: root.tone
        text: root.status
    }
}
