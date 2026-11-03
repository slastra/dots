pragma Singleton
import Quickshell
import Quickshell.Io
import ".."  // root module: Theme, Reader
import QtQuick

// deskvoice, the desk's one speaker and microphone (~/Projects/Python/deskvoice):
// who is talking (deskdoc, a Claude cue, the reader), whether the wake word is
// listening, live dictation, and what was said lately. One socket subscription;
// deskvoice pushes a status only when something changes, so an idle desk sends
// nothing. LASTSHELL_DESKVOICE_SOCKET points it elsewhere (the test harness's
// scripted stand-in).
Singleton {
    id: root

    readonly property string socketPath: Quickshell.env("LASTSHELL_DESKVOICE_SOCKET")
        || `${Quickshell.env("XDG_RUNTIME_DIR")}/deskvoice.sock`

    readonly property bool up: sock.connected
    property var status: ({})

    readonly property var speaking: status.speaking ?? null
    readonly property var listen: status.listen ?? null
    readonly property var dictation: status.dictation ?? null
    readonly property var voices: status.voices ?? ({})
    // every voice deskvoice can speak in, [{name, engine, label}], asked for on connect
    property var voiceList: []
    readonly property var recent: status.recent ?? []
    readonly property bool micOn: listen?.mic === true
    readonly property bool claudeQuiet: status.flags?.claude_quiet === true   // [status.flags] in deskvoice's config
    readonly property bool readerHeld: status.reader_held === true
    readonly property bool ducking: status.duck?.ducked === true
    // what deskvoice is waiting on: "reply" (deskdoc working out an answer),
    // "dictation" (a voice dictation being cleaned up and pasted), "transcribing"
    readonly property string thinking: status.thinking ?? ""

    // The one voice the chip shows, most urgent first: you dictating, the mic
    // open for a request, deskdoc or Claude speaking, the reader, nobody.
    readonly property string who: {
        if (!up) return Reader.active ? "reader" : "down"
        if (dictation) return "dictating"
        const ls = listen?.state
        if (ls === "listening" || ls === "transcribing") return "listening"
        if (speaking) return speaking.channel === "assistant" ? "deskdoc" : "claude"
        if (thinking) return "thinking"
        if (Reader.active) return "reader"
        return "idle"
    }

    // One colour per voice, everywhere: deskdoc speaks (and thinks) in the
    // shell's own rose, Claude in iris, the reader in foam (as it always has);
    // listening is gold (lastshell's "needs you"), dictating love (the
    // recorder's REC).
    function tone(w) {
        return ({ deskdoc: Theme.rose, thinking: Theme.rose, claude: Theme.iris, reader: Theme.foam,
                  listening: Theme.gold, dictating: Theme.love })[w] ?? Theme.textMuted
    }
    function kindTone(entry) {
        if (entry.kind === "heard") return Theme.gold
        if (entry.kind === "dictated") return Theme.love
        return entry.channel === "assistant" ? Theme.rose : Theme.iris
    }
    function kindLabel(entry) {
        if (entry.kind === "heard") return "you"
        if (entry.kind === "dictated") return entry.submitted ? "sent" : "typed"
        return entry.channel === "assistant" ? "doc" : "claude"
    }
    function clockOf(ts) { return Qt.formatTime(new Date(ts * 1000), "hh:mm") }

    // Overlays.qml listens: the same overlay as Super+X / Shift+Super+X.
    signal dictationRequested(bool send)

    function send(msg) {
        if (!sock.connected) return
        sock.write(JSON.stringify(msg) + "\n")
        sock.flush()
    }
    function setMic(on) { send({ op: "mic", enabled: on }) }
    function stopSpeaking() { send({ op: "stop" }) }
    function setClaudeQuiet(quiet) { send({ op: "flag", name: "claude_quiet", on: quiet }) }
    // A channel's voice from now on (deskvoice remembers it), then a line in it
    // so you hear what you picked; picking again cuts the last preview short.
    function pickVoice(channel, name) {
        send({ op: "voice", channel: channel, voice: name })
        send({ op: "stop", channel: channel })
        const who = (voiceList.find(v => v.name === name)?.label ?? name).replace(/ \(.*\)$/, "")
        send({ op: "say", id: `pick-${Date.now()}`, channel: channel, text: `Hi, I'm ${who}. This is how I sound.` })
    }
    function dictate(sendIt) { dictationRequested(sendIt === true) }

    Socket {
        id: sock
        path: root.socketPath
        connected: true
        onConnectionStateChanged: {
            if (connected) {
                root.send({ op: "subscribe" })
                root.send({ op: "voices", req: "voices" })
            }
            else root.status = ({})
        }
        parser: SplitParser {
            onRead: line => {
                let m
                try { m = JSON.parse(line) } catch (e) { return }
                if (m.event === "status") root.status = m
                else if (m.req === "voices") root.voiceList = m.voices ?? []
            }
        }
    }
    // deskvoice restarts (or starts after the shell): try again every few seconds
    Timer {
        interval: 3000
        repeat: true
        running: !sock.connected
        onTriggered: sock.connected = true
    }
}
