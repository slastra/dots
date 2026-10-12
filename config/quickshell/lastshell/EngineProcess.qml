import Quickshell.Io

// A Python engine the shell talks to by lines (scripts/dictate.py,
// scripts/reader.py): commands go in on stdin, events come out on stdout as
// `<name> <json>`, one per line. send() starts the engine on first use and
// queues anything written before it is up; a malformed line is dropped.
Process {
    id: root

    signal event(string name, var value)

    property var pending: []
    function send(line) {
        if (running) write(line + "\n")
        else { pending = pending.concat([line]); running = true }
    }

    stdinEnabled: true
    onStarted: {
        for (const line of pending) write(line + "\n")
        pending = []
    }
    stdout: SplitParser {
        onRead: line => {
            const sp = line.indexOf(" ")
            if (sp < 0) return
            let value
            try { value = JSON.parse(line.slice(sp + 1)) } catch (e) { return }
            root.event(line.slice(0, sp), value)
        }
    }
}
