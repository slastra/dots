import QtQuick

// The top bar: workspaces + window title left, taskbar center, system
// chips right. Modules land here phase by phase.
//
// Space is claimed by priority, so a narrow screen (the laptop, ~1600 px)
// degrades instead of overlapping: the system chips keep their width, the
// taskbar stays centered until it would reach them and then slides left,
// and the window title elides into whatever is left of the taskbar.
//
// On the laptop the taskbar packs left instead, right after the title, and
// the title takes whatever the icons leave before the system chips.
BarWindow {
    id: bar
    anchors.top: true

    readonly property int gap: 8
    // the title always keeps at least this much before the taskbar
    readonly property int titleMin: 120
    readonly property bool packLeft: Host.laptop
    // where the title chip starts: left margin, workspaces, spacing
    readonly property int titleX: gap + workspaces.width + gap

    ChipRow {
        id: left
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.leftMargin: bar.gap
        spacing: bar.gap
        Workspaces { id: workspaces }
        WindowTitle {
            anchors.top: parent.top
            // up to the taskbar (centered) or up to the system chips less the
            // icons that follow it (packed left); never below titleMin
            maxWidth: Math.max(bar.titleMin, Math.min(900, bar.packLeft
                ? sys.x - bar.gap - tasks.width - bar.gap - bar.titleX
                : tasks.x - bar.gap - bar.titleX))
        }
    }

    Taskbar {
        id: tasks
        anchors.top: parent.top
        // positioned by binding, not anchor, so a width change (a chip
        // coming or going) glides the whole strip instead of jumping it.
        // Centered, but never under the system chips, and never over the
        // workspaces plus the title's minimum.
        x: bar.packLeft ? left.x + left.width + bar.gap
            : Math.round(Math.max(bar.titleX + bar.titleMin + bar.gap,
                                  Math.min((parent.width - width) / 2, sys.x - bar.gap - width)))
        Behavior on x { NumberAnimation { duration: Theme.slideDuration; easing.type: Easing.OutCubic } }
        // Too many windows for the room left: narrow every icon slot (40 ->
        // 26, the 18 px icon plus 4 each side) before the strip can overlap.
        // A chip costs slot + 4 border + 4 spacing.
        readonly property int room: sys.x - bar.gap - (bar.titleX + bar.titleMin + bar.gap)
        slot: Math.max(26, Math.min(40, Math.floor(room / Math.max(1, count)) - 8))
    }

    ChipRow {
        id: sys
        anchors.top: parent.top
        // positioned by binding, not anchor, so a width change (a chip
        // coming or going) glides the whole strip instead of jumping it
        x: parent.width - width - 8
        Behavior on x { NumberAnimation { duration: Theme.slideDuration; easing.type: Easing.OutCubic } }
        spacing: 8
        Tray {}
        SysChips {}
        // Desk-only chips sit in Loaders so their services never start on
        // another host (Host.qml); hidden, so the Row adds no spacing for them.
        Loader { active: Host.desk; visible: active; sourceComponent: Component { HdrChip {} } }
        BrightnessChip {}
        BatteryChip {}
        Loader { active: Host.presence; visible: active; sourceComponent: Component { PresenceChip {} } }
        Loader { active: Host.desk; visible: active; sourceComponent: Component { DeskwatchChip {} } }
        ClockChip {}
    }
}
