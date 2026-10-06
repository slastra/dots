import Quickshell
import Quickshell.Io
import QtQuick

// Browser tab strip content (bottom bar, left). Pure view: tabstrip (the Go
// daemon) owns discovery, favicon fetch/processing, and ordering; this
// renders its snapshot and sends clicks back through the same CLI.
ChipRow {
    id: root

    SyncedList { id: tabs }
    spacing: 8

    FileView {
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/waybar-fftabs.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: parse()
        function parse() {
            try {
                tabs.sync(JSON.parse(text()).tabs ?? [], "id")
            } catch (e) {
                // mid-write read; the rename lands momentarily
            }
        }
    }

    // Leading static chip: a plus, click for a new default-browser
    // window. Sits ahead of the tabs so it never moves as they come and go.
    Chip {
        id: newWin
        edge: "bottom"
        contentPadding: 0   // fixed-width icon slot
        anchors.bottom: parent.bottom
        onClicked: Quickshell.execDetached(["firefox", "--new-window"])

        Item {
            implicitWidth: 34
            height: newWin.height - 2
            LucideIcon {
                anchors.centerIn: parent
                name: "plus"
                font.pixelSize: 16
                color: Theme.text
            }
        }
        ChipTip {
            owner: newWin
            text: "New Firefox window"
        }
    }

    Repeater {
        model: tabs.model

        Chip {
            id: chip
            required property var item
            required property bool gone
            required property int index
            present: !gone

            edge: "bottom"
            contentPadding: 0   // fixed-width icon slot
            active: item.active
            anchors.bottom: parent.bottom

            onClicked: Quickshell.execDetached(
                [Quickshell.env("HOME") + "/.local/bin/tabstrip", "goto", String(index + 1)])
            onRightClicked: Quickshell.execDetached(
                ["qs", "-c", "lastshell", "ipc", "call", "overlays", "toggleSwitcher"])
            onWheelUp: Quickshell.execDetached(
                [Quickshell.env("HOME") + "/.local/bin/tabstrip", "next"])
            onWheelDown: Quickshell.execDetached(
                [Quickshell.env("HOME") + "/.local/bin/tabstrip", "prev"])

            // brightness is baked into the chip the daemon picked (bright vs
            // -dim.png, by window focus) — don't re-dim
            IconChipBody { source: "file://" + chip.item.icon }

            ChipTip {
                owner: chip
                text: chip.item.label ?? ""
            }
        }
    }
}
