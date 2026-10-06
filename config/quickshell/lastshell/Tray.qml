import Quickshell
import Quickshell.Services.SystemTray
import QtQuick

// System tray: one chip per StatusNotifierItem, matching the taskbar's
// per-icon pattern. Interaction goes through Chip's own signals — content
// MouseAreas never fire, because Chip's MouseArea sits above the content
// (that's why the first version's clicks went nowhere).
ChipRow {
    spacing: 8
    visible: SystemTray.items.values.length > 0

    Repeater {
        model: SystemTray.items

        Chip {
            id: slot
            required property SystemTrayItem modelData

            edge: "top"
            contentPadding: 0   // fixed-width icon slot

            onClicked: modelData.onlyMenu ? menu.show() : modelData.activate()
            onRightClicked: if (modelData.hasMenu) menu.show()

            TrayMenu {
                id: menu
                owner: slot
                handle: slot.modelData.menu
            }

            IconChipBody { source: slot.modelData.icon }

            ChipTip {
                owner: slot
                text: slot.modelData.tooltipTitle || slot.modelData.title || ""
            }
        }
    }
}
