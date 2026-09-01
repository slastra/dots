import Quickshell
import Quickshell.Io
import QtQuick
import ".."  // root module: Recorder (recording-aware Print behavior)

// Overlay host: IPC surface + the surfaces themselves. Summoned from
// binds.lua via `qs -c lastshell ipc call overlays <fn>`, and from bar
// widgets directly (no IPC round trip in-process).
Scope {
    id: root

    property alias switcher: switcher

    // Modals live in LazyLoaders: eight always-instantiated fullscreen
    // windows held a large share of the shell's RSS in surface buffers.
    // Created on first summon, kept warm after — first-open jank once
    // beats resident cost forever.
    function summon(loader) {
        if (!loader.active) loader.active = true
        loader.item.toggle()
    }

    IpcHandler {
        target: "overlays"
        function toggleSwitcher(): void { root.summon(switcher) }
        function toggleLauncher(): void { root.summon(launcher) }
        function toggleAudio(): void { root.summon(audio) }
        function toggleEffects(): void { root.summon(effects) }
        function toggleClipboard(): void { root.summon(clipboard) }
        function toggleNotifications(): void { root.summon(center) }
        function toggleHotkeys(): void { root.summon(hotkeys) }
        function toggleCapture(): void {
            // Print while recording = stop, no menu — matching the script.
            if (Recorder.recording)
                Quickshell.execDetached(["bash",
                    Quickshell.env("HOME") + "/.config/rofi/scripts/capture.sh", "stop"])
            else
                root.summon(capture)
        }
    }

    // OSD and popups stay resident (they must observe state to react);
    // the eight modals load on demand.
    VolumeOsd {}
    NotificationPopups { id: popups }

    LazyLoader { id: switcher; TabSwitcher {} }
    LazyLoader { id: launcher; Launcher {} }
    LazyLoader { id: audio; AudioPicker {} }
    LazyLoader { id: effects; EffectPicker {} }
    LazyLoader { id: clipboard; ClipboardPicker {} }
    LazyLoader { id: center; NotificationCenter { history: popups.historyModel } }
    LazyLoader { id: capture; CapturePicker {} }
    LazyLoader { id: hotkeys; HotkeySheet {} }
}
