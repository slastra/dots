import Quickshell
import QtQuick
import ".."  // root module

// Screen capture menu (Print key; replaces rofi capture.sh's menu — the
// script itself stays as the capture engine, invoked by subcommand).
//
// Fullscreen/window IMAGE captures must not photograph this modal's own
// exit: the mask and card are still fading when grim would fire. Those
// actions run through a delay timer sized past the overlay animations —
// the same ghost-capture lesson capture.sh documents for rofi's fade.
SearchOverlay {
    id: root

    typeIcon: "camera"
    visibleRows: 8

    readonly property string script:
        Quickshell.env("HOME") + "/.config/rofi/scripts/capture.sh"

    // weights pin the menu order — SearchOverlay's sort is not stable
    // across equal weights and shuffled the list
    items: [
        { key: "region-image",     label: "Region → Image",        lucideIcon: "square-dashed", delay: false },
        { key: "region-video",     label: "Region → Video",        lucideIcon: "video",         delay: false },
        { key: "window-image",     label: "Window → Image",        lucideIcon: "app-window",    delay: true },
        { key: "window-video",     label: "Window → Video",        lucideIcon: "video",         delay: false },
        { key: "fullscreen-image", label: "Full Screen → Image",   lucideIcon: "monitor",       delay: true },
        { key: "fullscreen-video", label: "Full Screen → Video",   lucideIcon: "video",         delay: false },
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
