import Quickshell
import Quickshell.Io
import QtQuick
import ".."  // root module

// hyprglaze effect picker (replaces rofi effect.sh): lists effects from the
// binary, marks the one in hyprglaze.toml, writes the choice back — the
// daemon hot-reloads on save, exactly as the script relied on.
SearchOverlay {
    id: root

    typeIcon: "wand-sparkles"
    visibleRows: 12

    property var effects: []
    property string current: ""
    readonly property string config: Quickshell.env("HOME") + "/.config/hypr/hyprglaze.toml"

    onOpenChanged: if (open) { list.running = true; readCurrent.running = true }

    Process {
        id: list
        command: ["hyprglaze", "--list-effects"]
        stdout: StdioCollector {
            onStreamFinished: root.effects = text.trim().split("\n").filter(x => x)
        }
    }
    Process {
        id: readCurrent
        command: ["sh", "-c", `awk -F'"' '/^effect[[:space:]]*=/{print $2; exit}' "${root.config}"`]
        stdout: StdioCollector { onStreamFinished: root.current = text.trim() }
    }

    items: effects.map(e => ({ key: e, label: e, current: e === root.current }))

    onActivated: item => Quickshell.execDetached(["sed", "-i", "-E",
        `s/^effect[[:space:]]*=.*/effect = "${item.key}"/`, root.config])
}
