import Quickshell
import Quickshell.Io
import QtQuick
import ".."  // root module

// Color scheme picker, over `tint` (~/Projects/Python/tint): every Gogh
// scheme and your own, each with its colors. The scheme under the cursor
// is applied to the live targets as you move (terminals, this shell,
// window borders, the wallpaper), so the desktop behind the card IS the
// preview; Enter applies it everywhere, Esc puts back what was there.
SearchOverlay {
    id: root

    typeIcon: "palette"
    visibleRows: 12
    backdrop: 0.3
    hint: "tab dark / light   ↑↓ preview   ↵ apply   esc keep " + (original || "current")

    // every scheme, or only the dark or the light ones (by background)
    readonly property var kinds: [null, true, false]
    scopes: [
        { label: "all", count: schemes.length },
        { label: "dark", count: schemes.filter(s => s.dark).length },
        { label: "light", count: schemes.filter(s => !s.dark).length },
    ]

    // LASTSHELL_TINT points the harness at a wrapper that renders into a
    // scratch root, so a test never recolors the real desktop
    readonly property string tint: Quickshell.env("LASTSHELL_TINT") || (Quickshell.env("HOME") + "/.local/bin/tint")
    property var schemes: []
    property string original: ""    // applied when the picker opened
    property string showing: ""     // on the live targets right now
    property bool committed: false

    onOpenChanged: {
        if (open) { committed = false; loader.running = true }
        else {
            settle.stop()
            if (!committed && showing !== "" && showing !== original) show(original)
        }
    }

    JsonProcess {
        id: loader
        command: [root.tint, "list", "--json"]
        fallback: ({})
        onResult: j => {
            root.original = j.current ?? ""
            root.showing = root.original
            root.schemes = j.schemes ?? []
        }
    }

    // the applied scheme leads the list, then your own, then the rest
    items: schemes.filter(s => kinds[scope] === null || s.dark === kinds[scope]).map(s => ({
        key: s.name, label: s.name, swatches: s.swatches,
        current: s.name === root.original,
        weight: s.name === root.original ? 2 : s.yours ? 1 : 0,
    }))

    // Preview follows the cursor, once it has rested a moment: each one is
    // a `tint apply --live`, and holding an arrow key should not queue 40.
    readonly property string under: filtered[cursor]?.key ?? ""
    onUnderChanged: if (open && under !== "") settle.restart()
    Timer { id: settle; interval: 160; onTriggered: if (root.open) root.show(root.under) }

    // One apply at a time; the latest request wins.
    property string wanted: ""
    function show(name) {
        if (name === "" || (name === showing && !apply.running)) return
        wanted = name
        if (!apply.running) run()
    }
    function run() {
        showing = wanted
        apply.command = [tint, "apply", wanted, "--live"]
        apply.running = true
    }
    Process {
        id: apply
        onExited: if (root.wanted !== root.showing) root.run()
    }

    onActivated: item => {
        committed = true
        settle.stop()
        Quickshell.execDetached([tint, "apply", item.key])
    }
}
