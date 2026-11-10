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
    // Cached while the notification is alive: its row slides out after the
    // sender has closed it, and Quickshell has freed the object by then.
    property int urgency: 1
    property string appName: ""
    property string summary: ""
    property string body: ""
    readonly property int liveUrgency: notif?.urgency ?? 1
    readonly property string liveAppName: notif?.appName ?? ""
    readonly property string liveSummary: notif?.summary ?? ""
    readonly property string liveBody: notif?.body ?? ""
    onLiveUrgencyChanged: if (notif) urgency = liveUrgency
    onLiveAppNameChanged: if (notif) appName = liveAppName
    onLiveSummaryChanged: if (notif) summary = liveSummary
    onLiveBodyChanged: if (notif) body = liveBody
    Component.onCompleted: {
        urgency = liveUrgency; appName = liveAppName
        summary = liveSummary; body = liveBody
    }

    readonly property color tone:
        urgency === 2 ? Theme.crit : urgency === 0 ? Theme.ok : Theme.accent

    spacing: 2

    Row {
        spacing: 8
        PopText {
            id: app
            text: appName
            textFormat: Text.PlainText
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
        text: summary
        textFormat: Text.PlainText   // only the body may carry markup
        size: compact ? 14 : 15
        font.bold: true
        width: parent.width; elide: Text.ElideRight
    }
    PopText {
        // StyledText folds a newline into a space; senders mean a line break
        text: body.replace(/\n/g, "<br/>")
        dim: compact ? 0.65 : 0.75
        size: compact ? 12 : 13
        width: parent.width; wrapMode: Text.Wrap
        maximumLineCount: compact ? 2 : 3
        elide: Text.ElideRight; visible: text !== ""
        textFormat: Text.StyledText
    }
}
