import Quickshell
import Quickshell.Wayland
import QtQuick
import ".."  // root module: Theme and friends

// Transient volume pill, bottom-center above the bar. Reacts to Pipewire
// state itself, so chip scrolls, hardware keys, and wpctl all trigger it
// identically. Never takes keyboard, never eats clicks.
PanelWindow {
    id: root

    property bool shown: false
    property bool armed: false  // suppress the startup ghost while props populate

    readonly property real vol: Audio.vol
    readonly property bool muted: Audio.muted

    onVolChanged: ping()
    onMutedChanged: ping()
    function ping() {
        if (!armed) return
        shown = true
        hideTimer.restart()
    }
    Timer { interval: 1000; running: true; onTriggered: root.armed = true }
    Timer { id: hideTimer; interval: 1200; onTriggered: root.shown = false }

    visible: shown || pill.opacity > 0
    color: "transparent"
    anchors.bottom: true
    margins.bottom: Theme.barHeight + 14
    implicitWidth: pill.width
    implicitHeight: pill.height
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: Region {} // click-through, always

    Card {
        id: pill
        width: 280; height: 44
        opacity: root.shown ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 150 } }

        Row {
            anchors.centerIn: parent
            spacing: 12
            Text {
                anchors.verticalCenter: parent.verticalCenter
                font.family: Theme.fontFamily; font.pixelSize: 18
                color: root.muted ? Theme.love : Theme.text
                text: root.muted ? "󰝟" : root.vol < 0.34 ? "󰕿" : root.vol < 0.67 ? "󰖀" : "󰕾"
            }
            SliderTrack {
                anchors.verticalCenter: parent.verticalCenter
                width: 170
                frac: root.vol
                fill: root.muted ? Theme.love : Theme.pine
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                font.family: Theme.fontFamily; font.pixelSize: 15
                color: Theme.text
                text: `${Math.round(root.vol * 100)}%`
            }
        }
    }
}
