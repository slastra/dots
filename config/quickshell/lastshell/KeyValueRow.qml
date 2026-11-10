import QtQuick

// One "key ........ value" line in a popout: dim key at the left edge, the
// value at the right one. `tone` colors a value that is a reading.
Item {
    id: root
    property string key
    property string value
    property color tone: Theme.text
    width: parent ? parent.width : 0
    implicitHeight: k.implicitHeight
    PopText { id: k; dim: 0.55; text: root.key }
    PopText {
        anchors.right: parent.right
        width: Math.min(implicitWidth, root.width - k.width - 12)
        elide: Text.ElideRight
        horizontalAlignment: Text.AlignRight
        color: root.tone
        text: root.value
    }
}
