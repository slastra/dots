pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// deskwatch health, from the daemon's snapshot. The daemon owns collection,
// baselines, LLM verdicts and routing; this only watches the file it
// fingerprints-then-renames, so every change is exactly one reload.
Singleton {
    id: root

    property bool loaded: false
    property string level: "ok"         // ok | low | watch | high | crit
    property var counts: ({ crit: 0, high: 0, watch: 0, low: 0 })
    property var bad: []                // flags with bad == true, worst first
    property var verdicts: []           // newest first, from the daemon
    property bool stale: false
    property bool tailUp: true
    property int age: 0
    property int evalsLastHour: 0
    property string presence: ""

    readonly property int attention: (counts.crit ?? 0) + (counts.high ?? 0)
    readonly property bool ok: level === "ok" && !stale && tailUp

    readonly property var rank: ({ crit: 0, high: 1, watch: 2, low: 3 })

    // Per-flag levels arrive in the daemon's own words (urgent/default/min);
    // the aggregate uses crit/watch/low. Fold them so the chip speaks one
    // vocabulary. Colouring lives in DeskwatchChip: Theme is not in scope
    // here, and a Theme.* reference from a service resolves to undefined,
    // which paints black.
    function norm(lvl) {
        switch (lvl) {
        case "urgent": return "crit"
        case "default": return "watch"
        case "min": return "low"
        default: return lvl
        }
    }

    FileView {
        // LASTSHELL_DESKWATCH_SNAPSHOT points the harness at a fixture.
        path: Quickshell.env("LASTSHELL_DESKWATCH_SNAPSHOT") || (Quickshell.env("XDG_RUNTIME_DIR") + "/lastshell-deskwatch.json")
        watchChanges: true
        onFileChanged: reload()
        onLoaded: parse()
        function parse() {
            try {
                const j = JSON.parse(text())
                const h = j.health ?? {}
                root.level = h.level ?? "ok"
                root.counts = h.counts ?? { crit: 0, high: 0, watch: 0, low: 0 }
                const flags = (h.flags ?? []).filter(f => f.bad)
                    .map(f => Object.assign({}, f, { level: root.norm(f.level) }))
                flags.sort((a, b) => (root.rank[a.level] ?? 9) - (root.rank[b.level] ?? 9))
                root.bad = flags
                root.verdicts = h.verdicts ?? []
                root.stale = !!j.stale
                root.tailUp = j.tail?.up ?? true
                root.age = j.age ?? 0
                root.evalsLastHour = j.counts?.evals_last_hour ?? 0
                const p = j.desk?.presence
                root.presence = p === 1 ? "desk" : p === 0 ? "away" : ""
                root.loaded = true
            } catch (e) { /* mid-write */ }
        }
    }
}
