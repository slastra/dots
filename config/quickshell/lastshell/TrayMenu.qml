import Quickshell
import QtQuick

// DBus menu rendered in lastshell's own chrome (QsMenuAnchor hands menus
// to a native QtWidgets popup that ignores our design entirely).
// QsMenuOpener exposes the menu as a model; rows invoke entry.triggered().
// Submenus drill in: the opener's handle swaps and a back row appears.
PopupWindow {
    id: root

    required property Item owner
    property var handle: null   // the tray item's DBusMenuHandle

    // drill-in stack: [rootHandle, submenuEntry, ...]
    property var stack: []

    function show() {
        stack = [handle]
        visible = true
    }
    function hide() { visible = false; stack = [] }

    QsMenuOpener {
        id: opener
        menu: root.stack.length > 0 ? root.stack[root.stack.length - 1] : null
    }

    anchor {
        item: owner
        edges: Edges.Bottom
        gravity: Edges.Bottom
    }

    visible: false
    color: "transparent"
    implicitWidth: card.width
    implicitHeight: card.height

    Rectangle {
        id: card
        width: Math.max(180, rows.implicitWidth + 24)
        height: rows.implicitHeight + 16
        radius: Theme.overlayRadius
        color: Theme.surface
        border.color: Theme.overlay
        border.width: 2

        Column {
            id: rows
            x: 12; y: 8
            width: parent.width - 24

            Item { // back row while inside a submenu
                visible: root.stack.length > 1
                width: parent.width
                implicitHeight: visible ? 30 : 0
                height: implicitHeight
                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8
                    Text {
                        text: "‹"
                        color: Theme.iris; font.family: Theme.fontFamily; font.pixelSize: 15
                    }
                    Text {
                        text: "back"
                        color: Qt.alpha(Theme.text, 0.6)
                        font.family: Theme.fontFamily; font.pixelSize: 13
                    }
                }
                Rectangle {
                    anchors.fill: parent; radius: 5; z: -1
                    color: backHover.hovered ? Theme.overlay : "transparent"
                }
                HoverHandler { id: backHover }
                TapHandler { onTapped: root.stack = root.stack.slice(0, -1) }
            }

            Repeater {
                model: opener.children

                Item {
                    id: row
                    required property var modelData
                    width: rows.width
                    // implicitHeight, not just height: the Column sizes the
                    // card from implicit sizes, and 0 clipped the first row
                    implicitHeight: modelData.isSeparator ? 9 : 32
                    height: implicitHeight
                    implicitWidth: rowContent.implicitWidth + 30

                    Rectangle { // separator
                        visible: row.modelData.isSeparator
                        anchors.centerIn: parent
                        width: parent.width; height: 1
                        color: Theme.overlay
                    }

                    Rectangle { // hover plate
                        visible: !row.modelData.isSeparator
                        anchors.fill: parent
                        radius: 5
                        color: Theme.overlay
                        opacity: rowHover.hovered && row.modelData.enabled ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 100 } }
                    }

                    Row {
                        id: rowContent
                        visible: !row.modelData.isSeparator
                        anchors.verticalCenter: parent.verticalCenter
                        x: 8
                        spacing: 8

                        Text { // check mark space (checkbox/radio entries)
                            visible: row.modelData.buttonType !== 0
                            text: row.modelData.checkState === Qt.Checked ? "✓" : " "
                            color: Theme.rose
                            font.family: Theme.fontFamily; font.pixelSize: 13
                            width: 12
                        }
                        Image {
                            visible: source != ""
                            anchors.verticalCenter: parent.verticalCenter
                            width: 16; height: 16
                            source: row.modelData.icon ?? ""
                            sourceSize: Qt.size(32, 32)
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: row.modelData.text
                            color: row.modelData.enabled ? Theme.text : Qt.alpha(Theme.text, 0.35)
                            font.family: Theme.fontFamily; font.pixelSize: 14
                        }
                    }

                    Text { // submenu marker
                        visible: !row.modelData.isSeparator && row.modelData.hasChildren
                        anchors.right: parent.right
                        anchors.rightMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        text: "›"
                        color: Theme.iris
                        font.family: Theme.fontFamily; font.pixelSize: 15
                    }

                    HoverHandler { id: rowHover }
                    TapHandler {
                        enabled: !row.modelData.isSeparator && row.modelData.enabled
                        onTapped: {
                            if (row.modelData.hasChildren) {
                                root.stack = root.stack.concat([row.modelData])
                            } else {
                                row.modelData.triggered()
                                root.hide()
                            }
                        }
                    }
                }
            }
        }
    }
}
