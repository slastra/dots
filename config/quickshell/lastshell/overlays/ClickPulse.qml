import QtQuick
import ".."  // root module: Theme

// One click, drawn at the item's own (x, y): the press is a soft disc that
// blooms in and stays under the cursor while the button is held (it follows a
// drag), and the release lets it go as a thin ring that spreads and fades.
// A click faster than the bloom still plays the whole bloom first, so a quick
// tap reads in a video at 60 fps. Quick click, start to gone: ~500 ms.
//
// Every light stroke has a dark twin just outside it, and the disc sits on a
// faint dark underlay: light-on-light vanished on a white page, dark-on-dark
// would on a terminal, the pair reads on both.
//
// All motion is Scale/OpacityAnimator: they run on the render thread, so a
// busy shell (bars, popouts, IPC) can't stutter a pulse mid-recording, and
// nothing re-tessellates per frame. The ring is drawn at its FINAL size and
// scaled up into it, so its stroke reaches its true 2px as it fades instead
// of thickening past it.
Item {
    id: pulse

    property color tint: Theme.text
    readonly property color shade: Theme.base

    readonly property real size: 34     // held disc diameter
    readonly property real reach: 2.2   // ring's final diameter, in discs
    property bool releaseQueued: false

    function release() {
        if (bloom.running) releaseQueued = true
        else letGo.start()
    }

    Item {
        id: disc
        scale: 0.45
        opacity: 0

        Rectangle {
            x: -width / 2; y: -height / 2
            width: pulse.size + 3; height: width; radius: width / 2
            color: Qt.alpha(pulse.shade, 0.20)
            border.width: 1.5
            border.color: Qt.alpha(pulse.shade, 0.55)
        }
        Rectangle {
            x: -width / 2; y: -height / 2
            width: pulse.size; height: width; radius: width / 2
            color: Qt.alpha(pulse.tint, 0.24)
            border.width: 1.5
            border.color: Qt.alpha(pulse.tint, 0.92)
        }
    }

    Item {
        id: ring
        scale: 1 / pulse.reach
        opacity: 0

        Rectangle {
            x: -width / 2; y: -height / 2
            width: pulse.size * pulse.reach + 3; height: width; radius: width / 2
            color: "transparent"
            border.width: 2
            border.color: Qt.alpha(pulse.shade, 0.5)
        }
        Rectangle {
            x: -width / 2; y: -height / 2
            width: pulse.size * pulse.reach; height: width; radius: width / 2
            color: "transparent"
            border.width: 2
            border.color: pulse.tint
        }
    }

    ParallelAnimation {
        id: bloom
        running: true
        ScaleAnimator { target: disc; from: 0.45; to: 1; duration: 120; easing.type: Easing.OutCubic }
        OpacityAnimator { target: disc; from: 0; to: 1; duration: 70 }
        onFinished: if (pulse.releaseQueued) letGo.start()
    }

    ParallelAnimation {
        id: letGo
        ScaleAnimator { target: disc; to: 0.6; duration: 170; easing.type: Easing.OutCubic }
        OpacityAnimator { target: disc; to: 0; duration: 170; easing.type: Easing.OutCubic }
        ScaleAnimator { target: ring; from: 1 / pulse.reach; to: 1; duration: 380; easing.type: Easing.OutQuart }
        OpacityAnimator { target: ring; from: 0.85; to: 0; duration: 380; easing.type: Easing.OutQuad }
        onFinished: pulse.destroy()
    }
}
