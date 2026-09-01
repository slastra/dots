import Quickshell
import Quickshell.Services.Mpris
import QtQuick

// Now-playing chip (waybar mpris): title/artist capped, italic when paused,
// click play-pause, wheel next/prev.
Chip {
    id: root
    edge: "bottom"
    visible: player !== null

    readonly property MprisPlayer player: {
        const ps = Mpris.players.values
        return ps.find(p => p.playbackState === MprisPlaybackState.Playing)
            ?? ps.find(p => p.playbackState === MprisPlaybackState.Paused)
            ?? ps[0] ?? null
    }
    readonly property bool paused: player?.playbackState === MprisPlaybackState.Paused

    onClicked: player?.togglePlaying()
    onWheelUp: if (player?.canGoNext) player.next()
    onWheelDown: if (player?.canGoPrevious) player.previous()

    Row {
        height: root.height - 2
        spacing: 8
        leftPadding: 12
        rightPadding: 12

        LucideIcon {
            anchors.verticalCenter: parent.verticalCenter
            name: root.paused ? "pause" : "play"
            font.pixelSize: 13
            color: Qt.alpha(Theme.text, 0.7)
        }
        ValueText {
            font.italic: root.paused
            color: Theme.text
            text: {
                if (!root.player) return ""
                let dyn = [root.player.trackTitle, root.player.trackArtist]
                    .filter(x => x).join(" - ")
                if (dyn.length > 40) dyn = dyn.slice(0, 39) + "…"
                return dyn
            }
        }
    }
}
