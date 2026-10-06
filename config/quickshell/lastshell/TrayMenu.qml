import Quickshell
import Quickshell.Hyprland
import QtQuick

// DBus menu rendered in lastshell's own chrome (QsMenuAnchor hands menus
// to a native QtWidgets popup that ignores our design entirely).
// QsMenuOpener exposes the menu as a model; rows invoke entry.triggered().
// Submenus drill in: the opener's handle swaps and a back row appears.
// A PopupWindow has no native "click away" — the focus grab below closes
// it on any click outside the card.
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

    // Stay bound to the root menu while hidden so its layout is fetched
    // and the rows are built BEFORE show(): binding on open meant the popup
    // mapped empty and grew as the DBus reply landed (visible stutter).
    // show() then re-selects the same handle — no refetch, no resize.
    QsMenuOpener {
        id: opener
        menu: root.stack.length > 0 ? root.stack[root.stack.length - 1] : root.handle
    }

    // Dismiss on click-away: the grab holds while the menu is up and clears
    // the moment the pointer is pressed outside the popup. Keyed on
    // backingWindowVisible, not visible: `visible` flips before the popup's
    // surface is mapped, and a grab on an unmapped window silently no-ops.
    HyprlandFocusGrab {
        windows: [root]
        active: root.backingWindowVisible
        onCleared: root.hide()
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

    Card {
        id: card
        width: Math.max(180, rows.implicitWidth + 24)
        height: rows.implicitHeight + 16

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
                    PopText {
                        text: "‹"
                        color: Theme.iris; size: 15
                    }
                    PopText {
                        text: "back"
                        dim: 0.6
                        size: 13
                    }
                }
                Rectangle {
                    anchors.fill: parent; radius: Theme.innerRadius; z: -1
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
                        radius: Theme.innerRadius
                        color: Theme.overlay
                        opacity: rowHover.hovered && row.modelData.enabled ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Theme.animDuration } }
                    }

                    Row {
                        id: rowContent
                        visible: !row.modelData.isSeparator
                        anchors.verticalCenter: parent.verticalCenter
                        x: 8
                        spacing: 8

                        PopText { // check mark space (checkbox/radio entries)
                            visible: row.modelData.buttonType !== 0
                            text: row.modelData.checkState === Qt.Checked ? "✓" : " "
                            color: Theme.rose
                            size: 13
                            width: 12
                        }
                        Image {
                            visible: source != ""
                            anchors.verticalCenter: parent.verticalCenter
                            width: 16; height: 16
                            source: row.modelData.icon ?? ""
                            sourceSize: Qt.size(32, 32)
                        }
                        PopText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: row.modelData.text
                            color: row.modelData.enabled ? Theme.text : Qt.alpha(Theme.text, 0.35)
                            size: 14
                        }
                    }

                    PopText { // submenu marker
                        visible: !row.modelData.isSeparator && row.modelData.hasChildren
                        anchors.right: parent.right
                        anchors.rightMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        text: "›"
                        color: Theme.iris
                        size: 15
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
