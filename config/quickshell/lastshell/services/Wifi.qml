pragma Singleton
import Quickshell
import QtQuick
import ".."  // root module: EngineProcess, Net

// The laptop's Wi-Fi, through iwd (scripts/wifi.py; the protocol is there).
// The engine runs only while it is needed: the picker or the password dialog
// open, a connect in flight, or iwd waiting on a passphrase. A few seconds
// after the last of those it is stopped, so between uses no process, polling
// or D-Bus listener is left behind. `networks` keeps the last list, so the
// picker opens on it at once and the scan it starts refreshes it.
Singleton {
    id: root

    property var networks: []        // [{name, type, signal (dBm), known, connected}]
    property bool scanning: false
    property string connecting: ""   // the network a connect is in flight for
    property string prompt: ""       // iwd asked for this network's passphrase
    property string askFor: ""       // the network the password dialog is for
    property bool pickerOpen: false
    property bool dialogOpen: false

    signal result(string name, bool ok, string error)

    readonly property bool busy: pickerOpen || dialogOpen || connecting !== "" || prompt !== ""
    onBusyChanged: busy ? linger.stop() : linger.restart()
    Timer { id: reprobe; interval: 3000; onTriggered: Net.refresh() }
    Timer { id: linger; interval: 4000; onTriggered: proc.running = false }

    onPromptChanged: if (prompt !== "") askFor = prompt

    function scan() { proc.send("scan") }
    function connect(name, passphrase) {
        connecting = name
        proc.send("connect " + JSON.stringify(passphrase ? { name: name, passphrase: passphrase } : { name: name }))
    }
    // a password for iwd's own request, else the start of a new connect
    function submit(name, passphrase) {
        if (prompt === name) proc.send("passphrase " + JSON.stringify(passphrase))
        else connect(name, passphrase)
    }
    function cancel() { if (prompt !== "") proc.send("cancel") }

    EngineProcess {
        id: proc
        command: ["python3", Quickshell.shellDir + "/scripts/wifi.py"]
        onExited: { root.connecting = ""; root.prompt = ""; root.scanning = false }
        onEvent: (name, v) => {
            if (name === "state") {
                root.networks = v.networks
                root.scanning = v.scanning
            } else if (name === "prompt") {
                root.prompt = v ? v.name : ""
            } else if (name === "result") {
                if (v.name === root.connecting) root.connecting = ""
                // iwd reports connected before networkd has the address; look twice
                if (v.ok) { Net.refresh(); reprobe.restart() }
                root.result(v.name, v.ok, v.error)
                // the password dialog reports its own; a picker connect reports here
                if (!root.dialogOpen)
                    Quickshell.execDetached(["notify-send", "-a", "Wi-Fi", "-i", "network-wireless",
                        v.ok ? `Connected to ${v.name}` : `Couldn't join ${v.name}`, v.ok ? "" : v.error])
            }
        }
    }
}
