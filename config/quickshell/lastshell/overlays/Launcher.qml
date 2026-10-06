import Quickshell
import Quickshell.Hyprland
import QtQuick
import ".."  // root module: Theme and friends

// Launcher + window switcher in one (replaces rofi combi): open windows
// first, ordered by focus recency, then apps ranked by frecency — both
// within SearchOverlay's match bands, so a clean match still beats a
// popular loose one. Enter on a window focuses it; on an app, launches it.
SearchOverlay {
    id: root

    typeIcon: "rocket"

    property var windows: []

    // Browser windows are left out: the tab switcher (SUPER+W) already
    // reaches every tab directly, so listing the windows here is noise.
    // Refresh the window list at the moment of summoning — focusHistoryID
    // is the compositor's own recency order (0 = the window you came from).
    onOpenChanged: if (open) clientsProc.running = true
    JsonProcess {
        id: clientsProc
        command: ["hyprctl", "clients", "-j"]
        onResult: clients => root.windows = clients
            .filter(c => c.mapped && c.title !== "" && !Browsers.isBrowserClass(c.class))
            .sort((a, b) => a.focusHistoryID - b.focusHistoryID)
    }

    items: {
        const rows = []
        // Windows: most recent first; weight well above any app so they own
        // the top of an empty query, and tier 1 so they keep it while you
        // type — "orca" lands on the open OrcaSlicer, not a second launch.
        // The window you're in sorts last of the windows — you rarely switch
        // to where you already are.
        root.windows.forEach((c, i) => {
            const entry = DesktopEntries.heuristicLookup(c.class)
            rows.push({
                key: "win:" + c.address,
                label: c.title,
                sublabel: c.class,
                iconSource: entry?.icon ? Quickshell.iconPath(entry.icon, "application-x-executable") : "",
                weight: c.focusHistoryID === 0 ? 500 : 1000 - i,
                tier: 1,
                address: c.address,
            })
        })
        // Apps: by usage. Entries that would draw identical rows (same name,
        // same icon — a ~/.local override beside the system file it copies,
        // under a different id) collapse to the one used most, and that row
        // carries their combined usage so split history isn't lost.
        const apps = new Map()
        for (const e of DesktopEntries.applications.values) {
            if (e.noDisplay) continue
            const k = e.name + "\n" + e.icon
            const w = Frecency.weight(e.id)
            const prev = apps.get(k)
            if (prev && prev.own >= w) { prev.weight += w; continue }
            apps.set(k, {
                key: e.id,
                label: e.name,
                sublabel: [e.genericName, (e.keywords ?? []).join(" ")].filter(x => x).join(" "),
                iconSource: e.icon ? Quickshell.iconPath(e.icon, "application-x-executable") : "",
                weight: w + (prev?.weight ?? 0),
                own: w,
                entry: e,
            })
        }
        return rows.concat([...apps.values()])
    }

    onActivated: item => {
        if (item.address) {
            // The overlay holds exclusive keyboard focus; SearchOverlay calls
            // dismiss() right after this, and when the layer surface releases
            // focus Hyprland hands it back to the PREVIOUS window (and its
            // workspace) — stomping a focus dispatch issued before that
            // handback. Let the release land first; the close fade hides it.
            focusLater.address = item.address
            focusLater.restart()
        } else {
            Frecency.record(item.key)
            item.entry.execute()
        }
    }
    Timer {
        id: focusLater
        property string address: ""
        interval: 80
        onTriggered: Hyprland.dispatch(`hl.dsp.focus({ window = "address:${address}" })`)
    }
}
