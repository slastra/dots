import Quickshell
import Quickshell.Io
import QtQuick
import ".."  // root module

// Clipboard history picker (replaces rofi clipboard.sh). cliphist list is
// fetched at summon in recency order; text rows fuzzy-search on their
// preview, image rows show an icon and a readable size/dimensions label.
// Selection pipes the ORIGINAL line through cliphist decode | wl-copy —
// the id must survive the round trip, exactly as the script noted.
SearchOverlay {
    id: root

    typeIcon: "clipboard-list"
    visibleRows: 12

    property var entries: []

    onOpenChanged: if (open) list.running = true

    Process {
        id: list
        command: ["cliphist", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                const rows = []
                for (const line of text.split("\n")) {
                    if (!line) continue
                    const tab = line.indexOf("\t")
                    if (tab < 0) continue
                    const preview = line.slice(tab + 1)
                    const bin = preview.match(/^\[\[ binary data ([0-9.]+ [KMG]iB) (\w+) (\d+)x(\d+) \]\]$/)
                    rows.push({
                        line: line,
                        preview: bin ? `image · ${bin[2]} · ${bin[1]} · ${bin[3]}×${bin[4]}` : preview,
                        isImage: !!bin,
                    })
                }
                root.entries = rows
            }
        }
    }

    items: entries.map((e, i) => ({
        key: e.line,
        label: e.preview,
        lucideIcon: e.isImage ? "image" : "",
        weight: -i,   // preserve cliphist recency on an empty query
        line: e.line,
    }))

    onActivated: item => {
        paste.line = item.line
        paste.running = true
    }

    Process {
        id: paste
        property string line: ""
        command: ["sh", "-c", "cliphist decode | wl-copy"]
        stdinEnabled: true
        onStarted: { write(line); stdinEnabled = false }
    }
}
