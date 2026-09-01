import Quickshell
import QtQuick
import ".."  // root module

// Notification history (SUPER+N, replaces the broken rofi mako-history
// bind). Reads the popup stack's history model: everything not yet
// dismissed, newest first, capped at 50. Per-row dismiss, clear-all,
// Esc / click-outside to leave.
Overlay {
    id: root

    required property ListModel history
    cardWidth: 460
    contentPadding: 2

    Column {
        width: parent.width
        focus: true
        Keys.onEscapePressed: root.dismiss()

        Rectangle { // header
            width: parent.width
            height: 54
            topLeftRadius: 6
            topRightRadius: 6
            color: Theme.overlay

            Row {
                anchors.verticalCenter: parent.verticalCenter
                x: 18
                spacing: 12
                LucideIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: "bell"
                    font.pixelSize: 18
                    color: Theme.rose
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Notifications"
                    color: Theme.text; font.family: Theme.fontFamily
                    font.pixelSize: 16; font.bold: true
                }
            }

            Rectangle { // clear all
                visible: root.history.count > 0
                anchors.right: parent.right
                anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                width: clearRow.implicitWidth + 20
                height: 28
                radius: 6
                color: clearHover.hovered ? Qt.alpha(Theme.love, 0.15) : "transparent"
                border.color: Qt.alpha(Theme.love, 0.5)
                border.width: 1
                Behavior on color { ColorAnimation { duration: Theme.animDuration } }
                HoverHandler { id: clearHover }
                Row {
                    id: clearRow
                    anchors.centerIn: parent
                    spacing: 6
                    LucideIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: "trash-2"; font.pixelSize: 12
                        color: Theme.love
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "clear"
                        color: Theme.love; font.family: Theme.fontFamily; font.pixelSize: 12
                    }
                }
                TapHandler {
                    onTapped: {
                        for (let i = root.history.count - 1; i >= 0; i--)
                            root.history.get(i).notif.dismiss()
                    }
                }
            }
        }

        Rectangle { width: parent.width; height: 1; color: Qt.alpha("#000000", 0.35) }

        ListView { // body
            id: list
            width: parent.width
            height: Math.min(contentHeight, 560)
            clip: true
            interactive: contentHeight > height
            model: root.history
            spacing: 0

            remove: Transition {
                NumberAnimation { property: "opacity"; to: 0; duration: 150 }
            }
            displaced: Transition {
                NumberAnimation { property: "y"; duration: 180; easing.type: Easing.OutCubic }
            }

            delegate: Item {
                id: row
                required property var notif
                required property string time
                width: list.width
                implicitHeight: rowCol.implicitHeight + 20

                readonly property color tone:
                    notif.urgency === 2 ? Theme.love : notif.urgency === 0 ? Theme.foam : Theme.rose

                Rectangle {
                    anchors.fill: parent
                    color: Qt.alpha(Theme.overlay, 0.6)
                    opacity: rowHover.hovered ? 1 : 0
                    // opacity, not color: fading a fixed fill moves smoothly
                    // between rows where restarting color animations stuttered
                    Behavior on opacity { NumberAnimation { duration: 100 } }
                }
                HoverHandler { id: rowHover }

                Column {
                    id: rowCol
                    x: 18; y: 10
                    width: parent.width - 60
                    spacing: 2
                    Row {
                        spacing: 8
                        Text {
                            id: rowApp
                            text: row.notif.appName ?? ""
                            color: Qt.alpha(row.tone, 0.9)
                            font.family: Theme.fontFamily; font.pixelSize: 11
                        }
                        Text {
                            anchors.baseline: rowApp.baseline
                            text: row.time
                            color: Qt.alpha(Theme.text, 0.35)
                            font.family: Theme.fontFamily; font.pixelSize: 11
                        }
                    }
                    Text {
                        text: row.notif.summary ?? ""
                        color: Theme.text; font.family: Theme.fontFamily
                        font.pixelSize: 14; font.bold: true
                        width: parent.width; elide: Text.ElideRight
                    }
                    Text {
                        text: row.notif.body ?? ""
                        color: Qt.alpha(Theme.text, 0.65)
                        font.family: Theme.fontFamily; font.pixelSize: 12
                        width: parent.width; wrapMode: Text.Wrap
                        maximumLineCount: 2; elide: Text.ElideRight
                        visible: text !== ""
                        textFormat: Text.StyledText
                    }
                }

                Text { // per-row dismiss — fades rather than popping
                    opacity: rowHover.hovered ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 100 } }
                    anchors.right: parent.right
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    text: "✕"; color: Qt.alpha(Theme.text, 0.5)
                    font.pixelSize: 13
                    TapHandler { enabled: rowHover.hovered; onTapped: row.notif.dismiss() }
                }

                Rectangle { // row divider
                    anchors.bottom: parent.bottom
                    width: parent.width; height: 1
                    color: Qt.alpha(Theme.overlay, 0.6)
                }
            }
        }

        Item { // empty state
            visible: root.history.count === 0
            width: parent.width; height: 110
            Column {
                anchors.centerIn: parent
                spacing: 8
                LucideIcon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    name: "inbox"; font.pixelSize: 26
                    color: Qt.alpha(Theme.text, 0.3)
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "all clear"
                    color: Qt.alpha(Theme.text, 0.4)
                    font.family: Theme.fontFamily; font.pixelSize: 13; font.italic: true
                }
            }
        }

        Rectangle { width: parent.width; height: 1; color: Qt.alpha("#000000", 0.35) }

        Rectangle { // footer
            width: parent.width
            height: 30
            bottomLeftRadius: 6
            bottomRightRadius: 6
            color: Qt.alpha(Theme.overlay, 0.55)
            Text {
                anchors.left: parent.left
                anchors.leftMargin: 18
                anchors.verticalCenter: parent.verticalCenter
                text: "esc close"
                color: Qt.alpha(Theme.iris, 0.55)
                font.family: Theme.fontFamily; font.pixelSize: 12
            }
            Text {
                anchors.right: parent.right
                anchors.rightMargin: 18
                anchors.verticalCenter: parent.verticalCenter
                text: `${root.history.count}`
                color: Qt.alpha(Theme.text, 0.4)
                font.family: Theme.fontFamily; font.pixelSize: 12
            }
        }
    }
}
