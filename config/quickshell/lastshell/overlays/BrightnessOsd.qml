import Quickshell
import Quickshell.Wayland
import QtQuick
import ".."  // root module: Theme and friends

// Transient brightness pill, VolumeOsd's twin. Reacts to Backlight's
// userChanged (kernel uevents that auto brightness did not cause), so
// hardware keys, chip scrolls and brightnessctl all trigger it identically
// while auto's own gentle adjustments stay silent. Never takes keyboard,
// never eats clicks.
PanelWindow {
    id: root

    property bool shown: false
    property bool armed: false  // suppress the startup ghost while props populate

    readonly property real b: Backlight.frac

    Connections {
        target: Backlight
        function onUserChanged() {
            if (!root.armed) return
            root.shown = true
            hideTimer.restart()
        }
    }
    Timer { interval: 1000; running: Backlight.present; onTriggered: root.armed = true }
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
            LucideIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: "sun"
                font.pixelSize: 17
            }
            SliderTrack {
                anchors.verticalCenter: parent.verticalCenter
                width: 170
                frac: root.b
                fill: Theme.gold
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                font.family: Theme.fontFamily; font.pixelSize: 15
                color: Theme.text
                text: `${Math.round(root.b * 100)}%`
            }
        }
    }
}
