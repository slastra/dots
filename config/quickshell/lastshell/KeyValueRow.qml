import QtQuick

// One "key   value" line in a popout: dim key in a fixed column.
Row {
    property string key
    property string value
    property int keyWidth: 60
    spacing: 8
    PopText { width: parent.keyWidth; dim: 0.5; text: parent.key }
    PopText { text: parent.value }
}
