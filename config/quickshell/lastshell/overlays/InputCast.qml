import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick
import ".."  // root module: Recorder, Theme, EngineProcess

// What a screen recording shows of your hands: a ClickPulse at every click
// and the KeyCastStack of what you type. gpu-screen-recorder records the
// composited output, so both land in the video (and show on screen, as
// feedback). scripts/inputcast.py reads evdev and only runs while recording;
// nothing here costs anything otherwise. inputcast.py also logs press/release
// timing (not which key) for scripts/capture-sfx.py, which mixes click and
// key sounds into the video once it stops.
//
// Clicks: left is the neutral text tint, right iris, middle foam, so a viewer
// can tell a context menu came from a right click.
//
// The key display goes where the recording is: capture.sh writes
// $XDG_RUNTIME_DIR/lastshell-capture.json as it starts ({"output": name} or
// {"region": [x, y, w, h]}), and the stack sits inside a region's bottom edge
// or above the bar of the recorded output. Unknown target: the focused one.
//
// One fullscreen click-through layer per screen, mapped for the whole
// recording rather than per event: mapping a layer starts Hyprland's
// layersIn fade, which would swallow the first pulse.
//
// LASTSHELL_INPUTCAST_FIXTURE=<script> makes it active without a recording
// and runs that script as the event source (the harness's scripted input:
// wlrctl and wtype never reach evdev).
Scope {
    id: root

    readonly property string fixture: Quickshell.env("LASTSHELL_INPUTCAST_FIXTURE") ?? ""
    readonly property bool active: fixture !== "" || Recorder.recording
    readonly property string runtime: Quickshell.env("XDG_RUNTIME_DIR")

    signal pointer(string name, var value)
    signal key(var value)

    readonly property var tints: ({ left: Theme.text, right: Theme.iris, middle: Theme.foam })

    property var target: ({})
    FileView {
        path: root.runtime + "/lastshell-capture.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try { root.target = JSON.parse(text()) } catch (err) { root.target = {} }
        }
        onLoadFailed: root.target = {}
    }

    EngineProcess {
        command: root.fixture !== ""
            ? ["bash", root.fixture]
            : ["python3", Quickshell.shellDir + "/scripts/inputcast.py",
               "--log", root.runtime + "/lastshell-capture-input.jsonl"]
        running: root.active
        onEvent: (name, value) => {
            if (name === "key") root.key(value)
            else root.pointer(name, value)
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win

            required property var modelData
            screen: modelData

            readonly property var region: root.target.region ?? null
            readonly property bool castHere: {
                if (region) {
                    const cx = region[0] + region[2] / 2, cy = region[1] + region[3] / 2
                    return cx >= modelData.x && cx < modelData.x + modelData.width
                        && cy >= modelData.y && cy < modelData.y + modelData.height
                }
                const out = root.target.output ?? Hyprland.focusedMonitor?.name
                return out === modelData.name
            }

            // the pulse held down per button, so a drag moves it and the
            // release lets go of the right one
            property var held: ({})

            function local(v) { return { x: v.x - modelData.x, y: v.y - modelData.y } }
            function onScreen(p) { return p.x >= 0 && p.y >= 0 && p.x < width && p.y < height }

            Connections {
                target: root
                function onPointer(name, v) {
                    const p = win.local(v)
                    if (name === "down") {
                        if (!win.onScreen(p)) return
                        win.held[v.b]?.release()
                        win.held[v.b] = pulse.createObject(ripples, {
                            x: p.x, y: p.y, tint: root.tints[v.b] ?? Theme.text })
                    } else if (name === "move") {
                        for (const b in win.held) { win.held[b].x = p.x; win.held[b].y = p.y }
                    } else if (name === "up") {
                        const held = win.held[v.b]
                        if (!held) return
                        held.x = p.x; held.y = p.y
                        held.release()
                        delete win.held[v.b]
                    }
                }
                function onKey(v) { if (win.castHere) cast.key(v) }
                // recording stopped: drop everything, a held pulse included
                function onActiveChanged() {
                    if (root.active) return
                    for (const child of ripples.children) child.destroy()
                    win.held = {}
                    cast.clear()
                }
            }

            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "lastshell-inputcast"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            mask: Region {}  // never takes input: clicks land on what's beneath
            color: "transparent"
            visible: root.active

            KeyCastStack {
                id: cast
                visible: win.castHere
                width: Math.min(960, win.region ? win.region[2] : win.width)
                height: 46 * maxRows + 8 * (maxRows - 1)
                x: (win.region ? win.region[0] - win.modelData.x + win.region[2] / 2 : win.width / 2) - width / 2
                y: (win.region ? win.region[1] - win.modelData.y + win.region[3] - 20
                               : win.height - Theme.barHeight - 28) - height
            }

            // above the key display: a click on a pill's spot still shows
            Item { id: ripples; anchors.fill: parent }
            Component { id: pulse; ClickPulse {} }
        }
    }
}
