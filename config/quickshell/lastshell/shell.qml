import Quickshell
import "overlays"

ShellRoot {
    // Bars are instantiated per screen through Variants: when Hyprland
    // removes and re-adds the output (observed on TV wake after long
    // standby — HDMI-A-1 dropped, FALLBACK appeared, HDMI-A-1 returned),
    // windows bound to the dead screen are destroyed and never come back.
    // Variants recreates them on the re-added screen automatically.
    Variants {
        model: Quickshell.screens

        Scope {
            required property var modelData
            TopBar { screen: modelData }
            BottomBar { screen: modelData }
        }
    }

    Overlays {}
}
