import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick
import ".."  // root module: Presence

// Absence warning: the screen fades to black over the last seconds before
// deskpresence declares the desk empty and powers the TV off. The daemon's
// fade level comes in 0.05 steps on a 4 Hz tick (250 or 500 ms apart), and
// easing each step made the dim pulse. The level is linear in time, so its
// first rise starts one linear run to 1 over what is left of the window
// (rule.fade_ms) and later steps only confirm it. Linear opacity is an even
// fade to the eye here: Hyprland blends in the output's PQ encoding, which is
// close to perceptually uniform. One breath resets it and the shade lifts.
// Never takes input: the mask is empty, so clicks land on what's beneath.
//
// Once fully faded (the 10 min blackout before power-off), the shade hands
// over to blackout.frag as Hyprland's screen shader and hides the cursor.
// The shade alone is not black enough: in HDR its black lands at
// sdr_min_luminance (0.2 nits) on the OLED, and the cursor and any later
// popup on the Overlay layer draw above it. The shader runs on the output
// signal, after all of that. hypridle's input-resume also clears both, in
// case the shell dies mid-blackout.
PanelWindow {
    id: root

    readonly property bool blackout: Host.presence && Presence.fade >= 1 && level >= 0.999
    readonly property string shader: Qt.resolvedUrl("blackout.frag").toString().replace("file://", "")

    function applyBlackout(on) {
        Quickshell.execDetached(["hyprctl", "eval",
            `hl.config({ decoration = { screen_shader = "${on ? shader : ""}" }, cursor = { invisible = ${on} } })`])
    }

    onBlackoutChanged: applyBlackout(blackout)
    // a restart mid-blackout must not leave the screen dark under a present user
    Component.onCompleted: if (Host.presence) applyBlackout(blackout)
    Component.onDestruction: if (blackout) applyBlackout(false)

    // Hyprland's live reload puts the config values back
    Connections {
        target: Hyprland
        enabled: root.blackout
        function onRawEvent(event) {
            if (event.name === "configreloaded") root.applyBlackout(true)
        }
    }

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "lastshell-dim"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: Region {}
    color: "transparent"
    // Only mapped while there is something to show: a resident fullscreen
    // layer is surface memory and a compositor pass for nothing.
    visible: level > 0.001

    // only where deskpresence runs; the ternary keeps the singleton unbuilt elsewhere
    readonly property real target: Host.presence ? Presence.fade : 0
    property real level: 0

    onTargetChanged: {
        if (target <= 0) {             // you are back: lift quickly
            dim.stop()
            if (level > 0) lift.restart()
            return
        }
        lift.stop()
        // A run in progress already lands on time. A jump (shell restarted
        // while away, or the radar flipping straight to absent) runs fast.
        if (!dim.running) {
            dim.duration = Math.max(300, (1 - target) * Presence.fadeMs)
            dim.restart()
        }
    }

    NumberAnimation { id: dim; target: root; property: "level"; to: 1; easing.type: Easing.Linear }
    NumberAnimation { id: lift; target: root; property: "level"; to: 0; duration: 220; easing.type: Easing.OutQuad }

    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: root.level
    }
}
