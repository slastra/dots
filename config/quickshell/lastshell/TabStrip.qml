import Quickshell
import Quickshell.Io
import QtQuick

// Browser tab strip content (bottom bar, left). Pure view: tabstrip (the Go
// daemon) owns discovery, favicon fetch/processing, and ordering; this
// renders its snapshot and sends clicks back through the same CLI.
Row {
    id: root

    property var tabs: []
    spacing: 8

    FileView {
        path: "/run/user/1000/waybar-fftabs.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: parse()
        function parse() {
            try {
                root.tabs = JSON.parse(text()).tabs ?? []
            } catch (e) {
                // mid-write read; the rename lands momentarily
            }
        }
    }

    Repeater {
        model: root.tabs

        Chip {
            id: chip
            required property var modelData
            required property int index

            edge: "bottom"
            active: modelData.active
            anchors.bottom: parent.bottom

            onClicked: Quickshell.execDetached(
                [Quickshell.env("HOME") + "/.local/bin/tabstrip", "goto", String(index + 1)])
            onRightClicked: Quickshell.execDetached(
                ["qs", "-c", "lastshell", "ipc", "call", "overlays", "toggleSwitcher"])
            onWheelUp: Quickshell.execDetached(
                [Quickshell.env("HOME") + "/.local/bin/tabstrip", "next"])
            onWheelDown: Quickshell.execDetached(
                [Quickshell.env("HOME") + "/.local/bin/tabstrip", "prev"])

            Item {
                implicitWidth: 34
                height: chip.height - 2
                Image {
                    anchors.centerIn: parent
                    width: 18; height: 18
                    source: "file://" + chip.modelData.icon
                    sourceSize: Qt.size(36, 36) // decode above device pixels
                    smooth: true
                    // brightness is baked into the chip the daemon picked
                    // (bright vs -dim.png, by window focus) — don't re-dim
                }
            }

            ChipTip {
                owner: chip
                edge: "bottom"
                ownerHovered: chip.hovered
                text: chip.modelData.label ?? ""
            }
        }
    }
}
