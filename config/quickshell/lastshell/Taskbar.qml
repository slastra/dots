import Quickshell
import Quickshell.Wayland
import QtQuick

// Icon-only taskbar (waybar wlr/taskbar): click activates, right-click
// fullscreens, tooltip shows the title.
Row {
    spacing: 4

    Repeater {
        model: ToplevelManager.toplevels

        Chip {
            id: task
            required property Toplevel modelData
            edge: "top"
            active: modelData.activated
            height: Theme.barHeight - 2

            onClicked: modelData.activate()
            onRightClicked: modelData.fullscreen()

            Item {
                implicitWidth: 40
                // the chip's 2px border sits only on the bottom (edge "top"),
                // so center within the borderless region or the icon reads low
                height: task.height - 2
                Image {
                    anchors.centerIn: parent
                    width: 18; height: 18
                    source: {
                        const e = DesktopEntries.heuristicLookup(task.modelData.appId)
                        return e?.icon ? Quickshell.iconPath(e.icon, "image-missing") : ""
                    }
                    sourceSize: Qt.size(36, 36)
                }
            }

            ChipTip {
                owner: task
                edge: "top"
                ownerHovered: task.hovered
                text: task.modelData.title === "Picture in picture" ? "MPV" : task.modelData.title
            }
        }
    }
}
