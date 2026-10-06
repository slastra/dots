import Quickshell.Hyprland
import QtQuick

// Focused window title, waybar's hyprland/window: elided, "" -> "Hyprland".
// On an app switch the old title drops out and the new one falls in from
// the bar edge; a title change on the SAME window (progress, unread
// counts, page loads) just swaps the text, no motion. The border flashes
// the accent across the switch.
Chip {
    id: root
    edge: "top"
    clip: true
    // border lights up in the accent for the swap and eases back after
    active: swap.running

    // the whole chip's width budget, set by the bar; the label gets it
    // less the chip's padding and border
    property int maxWidth: 900

    readonly property var focused: Hyprland.activeToplevel
    readonly property string liveTitle: {
        const t = focused?.title ?? ""
        return t === "" ? "Hyprland" : t
    }
    property string shownTitle: liveTitle

    onFocusedChanged: swap.restart()
    onLiveTitleChanged: if (!swap.running) shownTitle = liveTitle

    SequentialAnimation {
        id: swap
        readonly property int half: Theme.slideDuration / 2
        ParallelAnimation {
            NumberAnimation { target: slide; property: "y"; to: root.height; duration: swap.half; easing.type: Easing.InCubic }
            NumberAnimation { target: label; property: "opacity"; to: 0; duration: swap.half; easing.type: Easing.InCubic }
        }
        ScriptAction { script: { root.shownTitle = root.liveTitle; slide.y = -root.height } }
        ParallelAnimation {
            NumberAnimation { target: slide; property: "y"; to: 0; duration: swap.half; easing.type: Easing.OutCubic }
            NumberAnimation { target: label; property: "opacity"; to: 1; duration: swap.half; easing.type: Easing.OutCubic }
        }
        PauseAnimation { duration: Theme.slideDuration }   // let the highlight linger
    }

    ChipBody {
        ValueText {
            id: label
            text: root.shownTitle
            // text takes the accent with the border while the swap plays
            color: root.active ? Theme.rose : Theme.text
            transform: Translate { id: slide }
            elide: Text.ElideRight
            width: Math.max(0, Math.min(implicitWidth, root.maxWidth - 2 * root.contentPadding - 4))
            // chip resizes with the swap rather than snapping to the new title
            Behavior on width { NumberAnimation { duration: Theme.slideDuration; easing.type: Easing.OutCubic } }
        }
    }
}
