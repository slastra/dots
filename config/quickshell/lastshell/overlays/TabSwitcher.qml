import Quickshell
import Quickshell.Io
import QtQuick
import ".."  // root module: Theme and friends

// Fuzzy browser-tab switcher. Unlike the bar's strip — which is
// deliberately workspace-filtered (show what you can see) — the modal is
// the GLOBAL view: `tabstrip list` returns every tab in every browser
// window on every workspace, and activation routes by id through the
// fleet, so it can pull you to a tab anywhere.
SearchOverlay {
    id: root

    typeIcon: "app-window"
    property var raw: []

    onOpenChanged: if (open) lister.running = true

    Process {
        id: lister
        command: [Quickshell.env("HOME") + "/.local/bin/tabstrip", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.raw = JSON.parse(text) } catch (e) { root.raw = [] }
            }
        }
    }

    // Action rows: open a fresh window per known browser. Tiny negative
    // weight sorts them under real tabs on an empty query.
    readonly property var browsers: [
        { name: "Firefox", cmd: ["firefox", "--new-window"] },
        { name: "Chrome",  cmd: ["google-chrome-stable", "--new-window"] },
    ]

    items: raw.map(t => ({
            key: t.id,
            label: t.title,
            sublabel: t.browser,
            iconSource: "file://" + t.icon,
            current: t.active,
        }))
        .concat(browsers.map(b => ({
            key: "new:" + b.name,
            label: `+ New ${b.name} window`,
            iconSource: "file://" + Quickshell.env("HOME")
                + `/.cache/tabctl/favicons/_fallback-${b.name.toLowerCase()}.png`,
            weight: -1,
            cmd: b.cmd,
        })))

    onActivated: item => {
        if (item.cmd)
            Quickshell.execDetached(item.cmd)
        else
            Quickshell.execDetached(
                [Quickshell.env("HOME") + "/.local/bin/tabstrip", "activate", item.key])
    }
}
