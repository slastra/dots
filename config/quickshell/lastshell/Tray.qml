import Quickshell
import Quickshell.Services.SystemTray
import QtQuick

// System tray: one chip per StatusNotifierItem, matching the taskbar's
// per-icon pattern. Interaction goes through Chip's own signals — content
// MouseAreas never fire, because Chip's MouseArea sits above the content
// (that's why the first version's clicks went nowhere).
Row {
    spacing: 4
    visible: SystemTray.items.values.length > 0

    Repeater {
        model: SystemTray.items

        Chip {
            id: slot
            required property SystemTrayItem modelData

            edge: "top"

            onClicked: modelData.onlyMenu ? menu.show() : modelData.activate()
            onRightClicked: if (modelData.hasMenu) menu.show()

            TrayMenu {
                id: menu
                owner: slot
                handle: slot.modelData.menu
            }

            Item {
                implicitWidth: 34
                height: slot.height - 2
                Image {
                    anchors.centerIn: parent
                    width: 18; height: 18
                    source: slot.modelData.icon
                    sourceSize: Qt.size(36, 36)
                }
            }

            ChipTip {
                owner: slot
                edge: "top"
                ownerHovered: slot.hovered
                text: slot.modelData.tooltipTitle || slot.modelData.title || ""
            }
        }
    }
}
