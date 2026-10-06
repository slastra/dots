import QtQuick
import ".."  // root module

// A notification's text: app name and time on one baseline, bold summary,
// wrapped body. The toast and the center row share it; `compact` is the
// center's smaller cut (two body lines, quieter alphas). Urgency tone:
// critical love, low foam, normal rose.
Column {
    property var notif
    property string time
    property bool compact: false
    readonly property color tone:
        notif.urgency === 2 ? Theme.love : notif.urgency === 0 ? Theme.foam : Theme.rose

    spacing: 2

    Row {
        spacing: 8
        PopText {
            id: app
            text: notif.appName ?? ""
            color: Qt.alpha(tone, 0.9)
            size: compact ? 11 : 12
            visible: text !== ""
        }
        PopText {
            anchors.baseline: app.baseline
            text: time
            color: Theme.textFaint
            size: 11
        }
    }
    PopText {
        text: notif.summary ?? ""
        size: compact ? 14 : 15
        font.bold: true
        width: parent.width; elide: Text.ElideRight
    }
    PopText {
        text: notif.body ?? ""
        dim: compact ? 0.65 : 0.75
        size: compact ? 12 : 13
        width: parent.width; wrapMode: Text.Wrap
        maximumLineCount: compact ? 2 : 3
        elide: Text.ElideRight; visible: text !== ""
        textFormat: Text.StyledText
    }
}
