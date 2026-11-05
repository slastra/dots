import Quickshell
import Quickshell.Io
import QtQuick
import ".."  // root module: Theme and friends

// "Upload this recording?" — offered by capture.sh after a screen recording
// stops (IPC: overlays offerUpload <path>). ↵ uploads to
// revolvetrading.com/v/<slug> through scripts/upload-video.sh, which encodes
// server-side and hands back an unlisted, noindex link; the link lands on the
// clipboard. Typing while asking sets the title (blank = the file name).
// Closing mid-upload keeps it going; a notification carries the link then.
Overlay {
    id: root

    cardWidth: 520
    contentPadding: 2

    readonly property string script: Quickshell.shellDir + "/scripts/upload-video.sh"

    property string path: ""
    property string title: ""
    // ask | uploading | done | error
    property string phase: "ask"
    property int progress: 0
    property string url: ""
    property string message: ""

    readonly property string fileName: path.split("/").pop()

    function offer(p) {
        if (phase === "uploading") return // one at a time; the new file stays on disk
        path = p
        title = ""
        phase = "ask"
        progress = 0
        url = ""
        message = ""
        open = true
    }

    function start() {
        phase = "uploading"
        progress = 0
        message = ""
        up.command = ["bash", script, path, title.trim()]
        up.running = true
    }

    function openLink() {
        if (url !== "") Quickshell.execDetached(["xdg-open", url])
        dismiss()
    }

    Process {
        id: up
        stdout: SplitParser {
            onRead: line => {
                const sp = line.indexOf(" ")
                const kind = sp < 0 ? line : line.slice(0, sp)
                const rest = sp < 0 ? "" : line.slice(sp + 1)
                if (kind === "progress") root.progress = Number(rest) || 0
                else if (kind === "url") root.url = rest
                else if (kind === "error") root.message = rest
            }
        }
        onExited: code => {
            if (code === 0 && root.url !== "") {
                root.phase = "done"
                Quickshell.execDetached(["wl-copy", root.url])
                if (!root.open)
                    Quickshell.execDetached(["notify-send", "-i", "video-x-generic",
                        "Recording uploaded", "Link copied: " + root.url])
            } else {
                root.phase = "error"
                if (root.message === "") root.message = "upload failed (exit " + code + ")"
                if (!root.open)
                    Quickshell.execDetached(["notify-send", "-u", "critical",
                        "Recording upload failed", root.message])
            }
        }
    }

    Column {
        width: parent.width
        focus: true

        Keys.onPressed: event => {
            const k = event.key
            const enter = k === Qt.Key_Return || k === Qt.Key_Enter
            if (k === Qt.Key_Escape) root.dismiss()
            else if (root.phase === "ask") {
                if (enter) root.start()
                else if (k === Qt.Key_Backspace) root.title = root.title.slice(0, -1)
                else if (event.text && event.text >= " ") root.title += event.text
                else return
            }
            else if (root.phase === "done" && enter) root.openLink()
            else if (root.phase === "error" && enter) root.start()
            else return
            event.accepted = true
        }

        ModalHeader {
            icon: root.phase === "done" ? "link" : root.phase === "error" ? "alert-circle" : "upload"
            title: root.phase === "ask" ? "Upload recording" : root.title.trim() || root.fileName
            showQuery: root.phase === "ask"
            query: root.title
            active: root.open && root.phase === "ask"
        }

        Column {
            x: 18
            width: parent.width - 36
            topPadding: 16
            bottomPadding: 16
            spacing: 10

            PopText {
                width: parent.width
                elide: Text.ElideMiddle
                size: 14
                color: root.phase === "error" ? Theme.love
                     : root.phase === "done" ? Theme.foam
                     : Theme.text
                dim: root.phase === "ask" && root.title === "" ? 0.55 : 1
                text: root.phase === "ask"
                        ? (root.title === "" ? "title: " + root.fileName : "for clients, unlisted, not indexed")
                    : root.phase === "uploading" ? (root.progress < 100 ? "uploading… " + root.progress + "%" : "finishing…")
                    : root.phase === "done" ? root.url
                    : root.message
            }

            SliderTrack {
                visible: root.phase === "uploading"
                width: parent.width
                frac: root.progress / 100
                fill: Theme.iris
            }

            PopText {
                visible: root.phase === "done"
                size: 12
                dim: 0.5
                width: parent.width
                elide: Text.ElideRight
                text: "link copied · plays once the server finishes encoding"
            }
        }

        ModalFooter {
            hint: root.phase === "ask" ? "type a title   ↵ upload   esc keep local"
                : root.phase === "uploading" ? "esc hide (keeps uploading)"
                : root.phase === "done" ? "↵ open   esc close"
                : "↵ retry   esc close"
            count: root.phase === "ask" ? root.fileName : ""
        }
    }
}
