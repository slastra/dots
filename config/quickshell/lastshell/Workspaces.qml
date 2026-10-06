import Quickshell.Hyprland
import QtQuick

// One chip per populated workspace (plus the focused one, even if empty).
// Chips come and go through a SyncedList so a workspace
// emptying out slides its chip away rather than blinking it off.
Item {
    id: root
    implicitWidth: row.implicitWidth
    implicitHeight: Theme.barHeight

    readonly property int focusedId: Hyprland.focusedWorkspace?.id ?? 1
    // Hyprland keeps visited-but-empty workspaces alive; only count windows.
    // From toplevels, which Quickshell keeps current from open/close/move
    // window events. lastIpcObject.windows was a snapshot refreshed only when
    // a workspace is created (before its first window lands) or fullscreen
    // toggles, so a populated workspace read 0 and vanished once unfocused.
    readonly property var occupied: {
        const ids = {}
        for (const ws of Hyprland.workspaces.values)
            if (ws.toplevels.values.length > 0) ids[ws.id] = true
        return ids
    }
    readonly property var shown: {
        const list = []
        for (const ws of Hyprland.workspaces.values)
            if (ws.id > 0 && (occupied[ws.id] || focusedId === ws.id))
                list.push(ws.id)
        return list.sort((a, b) => a - b)
    }
    onShownChanged: resync()
    Component.onCompleted: resync()
    function resync() { chips.sync(shown.map(id => ({ id: id })), "id") }
    SyncedList { id: chips }

    ChipRow {
        id: row
        anchors.top: parent.top
        spacing: 8

        Repeater {
            model: chips.model

            Chip {
                id: wsChip
                required property var item
                required property bool gone
                readonly property int wsId: item.id
                edge: "top"
                present: !gone
                active: root.focusedId === wsId
                height: Theme.barHeight - 2

                onClicked: Hyprland.dispatch(`hl.dsp.focus({ workspace = ${wsId} })`)

                ChipBody {
                    ValueText {
                        text: wsChip.wsId
                        // empty workspaces read dim but legible — overlay-on-surface
                        // was too faint to count at a glance
                        color: wsChip.active ? Theme.rose
                             : root.occupied[wsChip.wsId] ? Theme.text
                             : Theme.textMuted
                    }
                }
            }
        }
    }
}
