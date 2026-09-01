import Quickshell
import Quickshell.Wayland
import QtQuick
import ".."  // root module: Theme and friends

// Modal overlay base: a full-screen transparent catcher on the overlay
// layer, a centered card, exclusive keyboard while open (None otherwise —
// that flip is what hands focus back on dismiss).
PanelWindow {
    id: root

    property bool open: false
    default property alias content: inner.data
    property alias cardWidth: card.implicitWidth
    property int contentPadding: 18

    function toggle() { open = !open }
    function dismiss() { open = false }

    visible: open || card.opacity > 0
    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "lastshell-overlay"
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    MouseArea { // click-outside dismissal + the backdrop mask
        anchors.fill: parent
        onClicked: root.dismiss()

        // Uniform backdrop mask: flat, heavy, and animated — the desktop
        // steps behind one even sheet of base. (A vignette variant lived
        // here briefly; uniform read cleaner.)
        Rectangle {
            anchors.fill: parent
            color: Theme.base
            opacity: root.open ? 0.85 : 0
            Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
        }
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        anchors.verticalCenterOffset: root.open ? 0 : 10
        implicitHeight: inner.childrenRect.height + root.contentPadding * 2
        radius: Theme.overlayRadius
        color: Theme.surface
        border.color: Theme.overlay
        border.width: 2

        opacity: root.open ? 1 : 0
        scale: root.open ? 1 : 0.97
        Behavior on opacity { NumberAnimation { duration: Theme.animDuration; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: Theme.animDuration; easing.type: Easing.OutCubic } }
        Behavior on anchors.verticalCenterOffset { NumberAnimation { duration: Theme.animDuration; easing.type: Easing.OutCubic } }

        MouseArea { anchors.fill: parent } // swallow clicks inside the card

        Item {
            id: inner
            x: root.contentPadding; y: root.contentPadding
            width: parent.width - root.contentPadding * 2
            height: parent.height - root.contentPadding * 2
        }
    }
}
