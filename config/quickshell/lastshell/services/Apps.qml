pragma Singleton
import Quickshell
import QtQuick

// Launch applications into their own systemd scope (app-lastshell-<name>-<id>.scope
// under app.slice), the way GNOME and KDE do, instead of as children of qs.
// A child of qs shares whatever cgroup qs is in: run lastshell as a unit and
// every app opened from the launcher would die with each lastshell restart.
// Own scopes also give each app its own CPU/memory accounting (deskwatch's
// desk.hot sees them) and keep an app's runaway from being billed to the shell.
//
// Helper commands that belong to the shell (ipc calls, scripts, notify-send)
// keep using Quickshell.execDetached directly.
Singleton {
    id: root

    function slug(s) {
        return String(s || "app").replace(/\.desktop$/, "").replace(/[^A-Za-z0-9_.-]/g, "_").slice(0, 60)
    }

    // cmd: argv list. name: what the scope is named after. dir: working directory.
    function launch(cmd, name, dir) {
        if (!cmd || cmd.length === 0)
            return
        const unit = `app-lastshell-${slug(name ?? cmd[0].split("/").pop())}-${Math.random().toString(16).slice(2, 10)}`
        const argv = ["systemd-run", "--user", "--scope", "--quiet", "--collect",
                      "--slice=app.slice", `--unit=${unit}`, "--"].concat(cmd)
        Quickshell.execDetached(dir ? { command: argv, workingDirectory: dir } : argv)
    }

    // A DesktopEntry: its parsed command (field codes removed), in a terminal
    // when the entry asks for one.
    function launchEntry(entry) {
        const cmd = entry.runInTerminal ? ["kitty", "-e"].concat(entry.command) : entry.command
        launch(cmd, entry.id, entry.workingDirectory)
    }
}
