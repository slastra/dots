import Quickshell
import QtQuick
import ".."  // root module

// Screen capture menu (Print key). scripts/capture.sh is the engine,
// invoked by subcommand; its old rofi menu remains as a no-argument fallback.
//
// Fullscreen and window captures, image AND video, must not photograph this
// modal's own exit: the mask and card are still fading when grim or the
// recorder's first frame would fire. Those actions run through a delay timer
// sized past the overlay animations, the same ghost-capture lesson capture.sh
// documents for layer fades. Region actions need no delay: slurp's selection
// takes far longer, and capture.sh waits out slurp's own fade after it.
SearchOverlay {
    id: root

    typeIcon: "camera"
    visibleRows: 8

    readonly property string script:
        Quickshell.shellDir + "/scripts/capture.sh"

    // weights pin the menu order — SearchOverlay's sort is not stable
    // across equal weights and shuffled the list
    items: [
        { key: "region-image",     label: "Region → Image",        lucideIcon: "square-dashed", delay: false },
        { key: "region-video",     label: "Region → Video",        lucideIcon: "video",         delay: false },
        { key: "window-image",     label: "Window → Image",        lucideIcon: "app-window",    delay: true },
        { key: "window-video",     label: "Window → Video",        lucideIcon: "video",         delay: true },
        { key: "fullscreen-image", label: "Full Screen → Image",   lucideIcon: "monitor",       delay: true },
        { key: "fullscreen-video", label: "Full Screen → Video",   lucideIcon: "video",         delay: true },
        { key: "region-scan",      label: "Region → Scan Barcode", lucideIcon: "scan-barcode",  delay: false },
    ].map((it, i) => Object.assign(it, { weight: -i }))

    onActivated: item => {
        if (item.delay) {
            delayed.action = item.key
            delayed.restart()
        } else {
            Quickshell.execDetached(["bash", script, item.key])
        }
    }

    Timer {
        id: delayed
        property string action: ""
        interval: 420  // overlay fade (260ms mask) + margin, frames presented
        onTriggered: Quickshell.execDetached(["bash", root.script, action])
    }
}
