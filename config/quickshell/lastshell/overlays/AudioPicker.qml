import Quickshell
import Quickshell.Services.Pipewire
import QtQuick
import ".."  // root module

// Default-sink picker (replaces rofi audio.sh): native Pipewire, no wpctl
// parsing. The current sink is marked; Enter makes a sink the default.
SearchOverlay {
    id: root

    typeIcon: "volume-2"
    visibleRows: 10

    // Track the raw sink list, NOT the deduped one below. The tracker's object
    // list must not depend on Pipewire.defaultAudioSink: when the default sink
    // is the node being destroyed, defaultAudioSink changes *inside* the
    // QObject destructor, which re-runs the binding and writes a list holding a
    // half-destroyed node into the tracker. That segfaulted quickshell on a
    // bluetooth disconnect (2026-09-08).
    PwObjectTracker { objects: Pipewire.nodes.values.filter(n => n.isSink && !n.isStream) }

    // The nvidia HDMI card leaks an identical sink node on every TV power cycle
    // (tv-screen.sh off/on): same node.name, same device, same profile, and the
    // stale ones are never removed -- 70+ "AD103 ..." rows after a week of
    // uptime. Collapse by node.name, keeping the lowest id, which is the
    // original and the one that still plays.
    readonly property var sinks: {
        const byName = ({})
        for (const n of Pipewire.nodes.values) {
            if (!n.isSink || n.isStream || (n.description ?? "") === "") continue
            const prev = byName[n.name]
            if (!prev || n.id < prev.id) byName[n.name] = n
        }
        return Object.keys(byName).map(k => byName[k])
    }

    items: root.sinks.map(n => ({
        key: n.id,
        label: n.description,
        current: n === Pipewire.defaultAudioSink,
        node: n,
    }))

    onActivated: item => Pipewire.preferredDefaultAudioSink = item.node
}
