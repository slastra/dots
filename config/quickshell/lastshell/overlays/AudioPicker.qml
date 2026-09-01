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

    PwObjectTracker { objects: Pipewire.nodes.values.filter(n => n.isSink && !n.isStream) }

    items: Pipewire.nodes.values
        .filter(n => n.isSink && !n.isStream && (n.description ?? "") !== "")
        .map(n => ({
            key: n.id,
            label: n.description,
            current: n === Pipewire.defaultAudioSink,
            node: n,
        }))

    onActivated: item => Pipewire.preferredDefaultAudioSink = item.node
}
