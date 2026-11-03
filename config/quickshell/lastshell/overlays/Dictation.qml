import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick
import ".."  // root module

// Voice dictation (Super+X; Shift+Super+X also presses Return after the
// paste, to send a chat message or a Claude prompt; scripts/dictate.py is
// the engine). Tap to start,
// tap again (or Enter) to stop; the transcript comes back cleaned up for the
// window it is headed to, and Enter pastes it there. Pasting rather than
// typing keeps a newline from pressing Return in a terminal: kitty takes
// Ctrl+Shift+V as a bracketed paste, GUI apps take Ctrl+V.
Overlay {
    id: root

    cardWidth: 560
    contentPadding: 2

    readonly property string engine: Quickshell.shellDir + "/scripts/dictate.py"
    readonly property var terminals: ["kitty", "foot", "Alacritty", "org.wezfurlong.wezterm", "com.mitchellh.ghostty", "konsole"]

    // locating -> recording -> transcribing -> cleaning -> review | error
    property string phase: "locating"
    property real level: 0
    property real secs: 0
    property string raw: ""
    property string cleaned: ""
    property string note: ""
    property string error: ""
    property bool showRaw: false
    property var target: ({ address: "", cls: "", title: "" })
    property bool submit: false     // Shift+Super+X: Return after the paste

    readonly property bool busy: phase === "transcribing" || phase === "cleaning"
    readonly property string shown: showRaw ? raw : cleaned

    // Super+X: open, or stop if listening, or close. withSubmit (Shift)
    // marks this dictation to be sent: Return follows the paste.
    function hotkey(withSubmit) {
        if (!open) { submit = withSubmit === true; open = true }
        else if (phase === "recording") { if (withSubmit) submit = true; stop() }
        else dismiss()
    }
    function stop() { if (proc.running) proc.write("stop\n") }

    function reset() {
        level = 0; secs = 0; raw = ""; cleaned = ""; note = ""; error = ""; showRaw = false
    }
    function run(args) {
        reset()
        proc.running = false
        proc.command = ["python3", "-I", engine].concat(args)
            .concat(["--app", target.cls, "--title", target.title])
        proc.running = true
    }
    function record() { phase = "recording"; run(["record"]) }
    function redo(rewrite) { phase = "transcribing"; run(rewrite ? ["redo", "--rewrite"] : ["redo"]) }

    onOpenChanged: {
        if (open) {
            reset()
            phase = "locating"
            locate.running = true
        } else if (proc.running) {
            if (phase === "recording") proc.write("cancel\n")
            else proc.running = false   // results for a closed overlay go nowhere
        }
    }

    // The window the text is for. A layer-shell overlay never becomes the
    // active window, so this reads the same before and after it opens.
    JsonProcess {
        id: locate
        command: ["hyprctl", "activewindow", "-j"]
        fallback: ({})
        onResult: w => {
            root.target = { address: w.address ?? "", cls: w.class ?? "", title: w.title ?? "" }
            if (root.open) root.record()
        }
    }

    EngineProcess {
        id: proc
        onEvent: (name, v) => {
            if (name === "level") root.level = v
            else if (name === "time") root.secs = v
            else if (name === "state") root.phase = v
            else if (name === "raw") root.raw = v
            else if (name === "clean") { root.cleaned = v; root.phase = "review" }
            else if (name === "note") root.note = v
            else if (name === "error") { root.error = v; root.phase = "error" }
        }
        onExited: code => {
            if (code !== 0 && root.open && root.phase !== "error" && root.phase !== "review") {
                root.error = `dictate.py exited (${code})`
                root.phase = "error"
            }
        }
    }

    // --- delivery ------------------------------------------------------------
    function insert(copyOnly) {
        if (shown === "") return
        deliver.text = shown
        deliver.copyOnly = copyOnly
        deliver.submit = submit && !copyOnly
        deliver.terminal = terminals.includes(target.cls)
        dismiss()            // keyboard focus goes back to the window
        deliver.restart()
    }
    Timer {
        id: deliver
        property string text
        property bool copyOnly
        property bool terminal
        property bool submit
        interval: 120        // past the overlay's focus hand-back
        onTriggered: {
            if (root.target.address)
                Hyprland.dispatch(`hl.dsp.focus({ window = "address:${root.target.address}" })`)
            paste.command = ["sh", "-c", `
                printf %s "$1" | wl-copy
                [ "$2" = copy ] && exit 0
                if command -v wtype >/dev/null; then
                    sleep 0.08
                    if [ "$3" = term ]; then wtype -M ctrl -M shift -k v -m shift -m ctrl
                    else wtype -M ctrl -k v -m ctrl; fi
                    if [ "$4" = submit ]; then sleep 0.12; wtype -k Return; fi
                else
                    notify-send -a Dictation "Copied to clipboard" "Install wtype to paste it into the window"
                fi`, "sh", text, copyOnly ? "copy" : "paste", terminal ? "term" : "gui", submit ? "submit" : "keep"]
            paste.running = true
        }
    }
    Process { id: paste }

    // --- view ----------------------------------------------------------------
    Column {
        width: parent.width
        focus: true

        Keys.onPressed: event => {
            const k = event.key, shift = event.modifiers & Qt.ShiftModifier
            const enter = k === Qt.Key_Return || k === Qt.Key_Enter
            if (k === Qt.Key_Escape) root.dismiss()
            else if (root.phase === "recording" && (enter || k === Qt.Key_Space)) root.stop()
            else if (root.phase === "review" && enter) root.insert(shift)
            else if (root.phase === "review" && k === Qt.Key_Tab) root.showRaw = !root.showRaw
            else if ((root.phase === "review" || root.phase === "error") && k === Qt.Key_R)
                shift ? root.redo(true) : root.record()
            else if (root.phase === "error" && k === Qt.Key_T) root.redo(false)
            else return
            event.accepted = true
        }

        ModalHeader {
            icon: root.phase === "error" ? "mic-off" : "mic"
            title: root.submit ? "Dictation  ·  send" : "Dictation"   // Shift+Super+X presses Return after the paste
            showQuery: false

            PopText { // where the text will land
                anchors.right: parent.right
                anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, 300)
                elide: Text.ElideRight
                size: 12; dim: 0.5
                text: root.target.cls ? `→ ${root.target.cls}${root.target.title ? "  ·  " + root.target.title : ""}` : ""
            }
        }

        Item {
            width: parent.width
            height: body.height + 36

            Column {
                id: body
                x: 18; y: 18
                width: parent.width - 36
                spacing: 14

                // listening: level bar + time
                Row {
                    visible: root.phase === "recording" || root.phase === "locating"
                    spacing: 14
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: body.width - clock.width - 14
                        height: 8; radius: 4
                        color: Theme.overlay
                        Rectangle { // no Behavior: ~12 updates a second already read as motion
                            width: Math.max(8, parent.width * root.level)
                            height: parent.height; radius: 4
                            color: root.level > 0.85 ? Theme.gold : Theme.foam
                        }
                    }
                    PopText {
                        id: clock
                        anchors.verticalCenter: parent.verticalCenter
                        size: 13; dim: 0.6
                        text: `${Math.floor(root.secs / 60)}:${String(Math.floor(root.secs % 60)).padStart(2, "0")}`
                    }
                }
                PopText {
                    visible: root.phase === "recording" || root.phase === "locating"
                    size: 14; dim: 0.5
                    text: root.phase === "locating" ? "Starting…" : "Listening…"
                }

                // working
                PopText {
                    visible: root.busy
                    size: 14; color: Theme.iris
                    text: root.phase === "transcribing" ? "Transcribing…" : "Cleaning up…"
                }
                PopText { // the raw words while cleanup runs
                    visible: root.phase === "cleaning" && root.raw !== ""
                    width: body.width
                    wrapMode: Text.Wrap
                    size: 14; dim: 0.45
                    text: root.raw
                }

                // review
                Flickable {
                    visible: root.phase === "review"
                    width: body.width
                    height: Math.min(result.implicitHeight, 320)
                    contentHeight: result.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    PopText {
                        id: result
                        width: parent.width
                        wrapMode: Text.Wrap
                        size: 16
                        color: root.showRaw ? Theme.textMuted : Theme.text
                        text: root.shown
                    }
                }
                PopText {
                    visible: root.phase === "review" && (root.note !== "" || root.showRaw)
                    size: 12; color: Theme.gold
                    text: root.showRaw ? "raw transcript" : root.note
                }

                // error
                PopText {
                    visible: root.phase === "error"
                    width: body.width
                    wrapMode: Text.Wrap
                    size: 14; color: Theme.love
                    text: root.error
                }
            }
        }

        ModalFooter {
            hint: ({
                locating: "esc cancel",
                recording: "↵ stop   esc cancel",
                transcribing: "esc close",
                cleaning: "esc close",
                review: root.submit
                    ? "↵ paste & send   ⇧↵ copy   ⇥ raw   r again   ⇧r rewrite   esc discard"
                    : "↵ paste   ⇧↵ copy   ⇥ raw   r again   ⇧r rewrite   esc discard",
                error: "r record again   t retry   esc close",
            })[root.phase] ?? ""
            count: root.phase === "review" ? `${root.shown.split(/\s+/).filter(w => w).length} words` : ""
        }
    }
}
