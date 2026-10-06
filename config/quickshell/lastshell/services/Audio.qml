pragma Singleton
import Quickshell
import Quickshell.Services.Pipewire
import QtQuick

// The default sink, bound once for every surface that shows it (chip, OSD).
// The tracker follows every sink node, never a list derived from
// Pipewire.defaultAudioSink: when the default sink is the node being
// destroyed, defaultAudioSink changes inside the destructor, re-runs such a
// binding and hands the tracker a half-destroyed node (segfault on a
// bluetooth disconnect, 2026-09-08; see overlays/AudioPicker.qml).
Singleton {
    id: root

    PwObjectTracker { objects: Pipewire.nodes.values.filter(n => n.isSink && !n.isStream) }

    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property real vol: sink?.audio?.volume ?? 0
    readonly property bool muted: sink?.audio?.muted ?? false
    readonly property bool bluetooth: (sink?.name ?? "").startsWith("bluez")
    readonly property string description: sink?.description ?? "no sink"

    function setVolume(v) {
        if (sink?.audio) sink.audio.volume = Math.max(0, Math.min(1.5, v))
    }
    function step(delta) { setVolume(vol + delta) }
    function toggleMute() {
        if (sink?.audio) sink.audio.muted = !sink.audio.muted
    }
}
