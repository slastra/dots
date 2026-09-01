import Quickshell.Hyprland
import QtQuick

// Focused window title, waybar's hyprland/window: elided, "" -> "Hyprland".
Chip {
    id: root
    edge: "top"

    ChipText {
        text: {
            const t = Hyprland.activeToplevel?.title ?? ""
            return t === "" ? "Hyprland" : t
        }
        height: root.height
        rightPadding: 12
        elide: Text.ElideRight
        width: Math.min(implicitWidth, 900)
    }
}
