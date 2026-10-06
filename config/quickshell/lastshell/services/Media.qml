pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import QtQuick

// The MPRIS roster and which player the bar shows, decided once for every
// screen's MprisChip. Left alone it follows the player that most recently
// started playing; a hand pick (wheel, popout row) sticks until that player
// goes away or some other player starts.
Singleton {
    id: root

    // playerctld is a proxy that re-exports whichever player was last
    // active under its own name: counting it shows every track twice.
    // Anything that talks to it (a busctl query, `playerctl -p playerctld`)
    // D-Bus-activates it, so it comes and goes.
    readonly property var players: Mpris.players.values
        .filter(p => !(p.dbusName ?? "").includes("playerctld"))
    readonly property var playing: players.filter(p => p.isPlaying)

    property MprisPlayer player: null
    property var picked: null      // hand-picked player
    property var started: []       // players in the order they last went to Playing
    property var lastPlaying: []

    function choose() {
        if (picked && !players.includes(picked)) picked = null
        started = started.filter(p => players.includes(p))
        const current = players.includes(player) ? player : null
        const newest = started.filter(p => p.isPlaying).pop()
        const next = picked
            ?? newest
            ?? (current?.isPlaying ? current : null)
            ?? playing[0]
            ?? current
            ?? started[started.length - 1]
            ?? players.find(p => p.playbackState === MprisPlaybackState.Paused)
            ?? players[0] ?? null
        if (next !== player) player = next
    }

    // A player only counts as started when it goes to Playing. Roster
    // arrival alone doesn't: a player registers before its state is read,
    // and used to lose that race to whatever was already showing and then
    // never get picked up when it started.
    onPlayingChanged: {
        const fresh = playing.filter(p => !lastPlaying.includes(p))
        lastPlaying = playing
        if (fresh.length > 0) {
            started = started.filter(p => !fresh.includes(p)).concat(fresh)
            if (picked && !fresh.includes(picked)) picked = null
        }
        choose()
    }
    onPlayersChanged: choose()
    Component.onCompleted: { lastPlaying = playing; choose() }

    function pick(p) { picked = p; choose() }

    // One player: step skips tracks. Several: step picks the player.
    function cycle(step) {
        if (players.length < 2) {
            if (step > 0 && player?.canGoNext) player.next()
            if (step < 0 && player?.canGoPrevious) player.previous()
            return
        }
        const i = Math.max(0, players.indexOf(player))
        pick(players[(i + step + players.length) % players.length])
    }

    function describe(p) {
        const dyn = [p?.trackTitle, p?.trackArtist].filter(x => x).join(" - ")
        return dyn !== "" ? dyn : (p?.identity ?? "")
    }

    // `qs ipc -c lastshell call mpris list`: the roster as the bar sees it.
    IpcHandler {
        target: "mpris"
        function list(): string {
            return Mpris.players.values.map(p =>
                `${p === root.player ? "*" : " "} ${p.dbusName}  ${MprisPlaybackState.toString(p.playbackState)}  ${root.describe(p)}`
                + (root.players.includes(p) ? "" : "  (ignored)")
                + (p === root.picked ? "  (picked)" : "")
            ).join("\n")
        }
    }
}
