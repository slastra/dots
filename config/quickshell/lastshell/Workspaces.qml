import Quickshell.Hyprland
import QtQuick

// Workspace chips 1-5 always shown (waybar persistent_workspaces), higher
// ones appear when occupied. A rose underline slides to the focused one —
// the motion GTK CSS could never do.
Item {
    id: root
    implicitWidth: row.implicitWidth
    implicitHeight: Theme.barHeight

    readonly property int focusedId: Hyprland.focusedWorkspace?.id ?? 1
    readonly property var occupied: {
        const ids = {}
        for (const ws of Hyprland.workspaces.values)
            ids[ws.id] = true
        return ids
    }
    readonly property var shown: {
        const list = []
        for (let i = 1; i <= 9; i++)
            if (i <= 5 || occupied[i] || focusedId === i)
                list.push(i)
        return list
    }

    Row {
        id: row
        anchors.top: parent.top
        spacing: 4

        Repeater {
            model: root.shown

            Chip {
                id: wsChip
                required property var modelData
                edge: "top"
                active: root.focusedId === modelData
                height: Theme.barHeight - 2

                onClicked: Hyprland.dispatch(`hl.dsp.focus({ workspace = ${modelData} })`)

                ChipText {
                    text: wsChip.modelData
                    height: wsChip.height
                    rightPadding: 12
                    // empty workspaces read dim but legible — overlay-on-surface
                    // was too faint to count at a glance
                    color: wsChip.active ? Theme.rose
                         : root.occupied[wsChip.modelData] ? Theme.text
                         : Qt.alpha(Theme.text, 0.45)
                }
            }
        }
    }

    // Sliding underline: sits along the bar's bottom, tracks the active chip.
    Rectangle {
        id: underline
        height: 2
        radius: 1
        color: Theme.rose
        y: Theme.barHeight - 4
        x: row.x + (activeItem ? activeItem.x + 8 : 0)
        width: activeItem ? activeItem.width - 16 : 0
        readonly property Item activeItem: {
            for (let i = 0; i < row.children.length; i++)
                if (row.children[i].active) return row.children[i]
            return null
        }
        Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
    }
}
