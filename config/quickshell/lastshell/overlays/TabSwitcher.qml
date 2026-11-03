import Quickshell
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

    JsonProcess {
        id: lister
        command: [Quickshell.env("HOME") + "/.local/bin/tabstrip", "list"]
        onResult: tabs => root.raw = tabs
    }

    // Action rows: open a fresh window per known browser, in Browsers'
    // order (Firefox first). They head the list on an empty query and sink
    // under real tabs once you type, so they never crowd a search.
    readonly property var browsers: Browsers.newWindow

    // Tabs arrive most recently touched first (tabstrip's recency log);
    // weight keeps that order. The tab you're looking at sinks below the
    // rest, like the Launcher's current window: the top tab is the one
    // you came from.
    items: raw.map((t, i) => ({
            key: t.id,
            label: t.title,
            sublabel: t.browser,
            iconSource: t.icon ? "file://" + t.icon : "",
            current: t.active,
            weight: t.focused ? 0 : raw.length - i,
        }))
        .concat(browsers.map((b, i) => ({
            key: "new:" + b.name,
            label: `+ New ${b.name} window`,
            iconSource: "file://" + Quickshell.env("HOME")
                + `/.cache/tabctl/favicons/_fallback-${b.name.toLowerCase()}.png`,
            weight: root.query === "" ? raw.length + browsers.length - i : -i - 1,
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
