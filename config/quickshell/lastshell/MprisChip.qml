import Quickshell
import Quickshell.Services.Mpris
import QtQuick

// Now-playing chip (waybar mpris): one chip, one player at a time. Wheel
// cycles which player it shows when there are several (the text swaps
// with a slide from the bar edge, border and text in the accent for the
// beat) and skips tracks when there's one; click play-pauses. Which
// player shows is Media's call (follows the latest to start playing).
// Hover lists every registered player; clicking a row shows that one.
Chip {
    id: root
    edge: "bottom"
    clip: true
    active: swap.running

    readonly property var player: Media.player
    readonly property bool paused: player?.playbackState === MprisPlaybackState.Paused
    present: Media.players.length > 0

    onWheelUp: Media.cycle(1)
    onWheelDown: Media.cycle(-1)
    onClicked: player?.togglePlaying()

    function stateIcon(p) {
        return p.isPlaying ? "play"
            : p.playbackState === MprisPlaybackState.Paused ? "pause" : "square"
    }

    readonly property string liveText: {
        if (!player) return ""
        const dyn = Media.describe(player)
        return dyn.length > 40 ? dyn.slice(0, 39) + "…" : dyn
    }
    property string text: ""
    onLiveTextChanged: if (!swap.running) text = liveText
    onPlayerChanged: if (text !== "") swap.restart(); else text = liveText

    SequentialAnimation {
        id: swap
        readonly property int half: Theme.slideDuration / 2
        ParallelAnimation {
            NumberAnimation { target: slide; property: "y"; to: -root.height; duration: swap.half; easing.type: Easing.InCubic }
            NumberAnimation { target: content; property: "opacity"; to: 0; duration: swap.half; easing.type: Easing.InCubic }
        }
        ScriptAction { script: { root.text = root.liveText; slide.y = root.height } }
        ParallelAnimation {
            NumberAnimation { target: slide; property: "y"; to: 0; duration: swap.half; easing.type: Easing.OutCubic }
            NumberAnimation { target: content; property: "opacity"; to: 1; duration: swap.half; easing.type: Easing.OutCubic }
        }
        PauseAnimation { duration: Theme.slideDuration }
        // metadata usually trickles in right after a switch (title, then
        // artist); a change during the tail must not be dropped
        onRunningChanged: if (!running) root.text = root.liveText
    }

    Popout {
        owner: root

        sheetWidth: Theme.popM
        title: "media"
        status: Media.players.length === 1 ? "1 player" : `${Media.players.length} players`
        tone: Media.playing.length > 0 ? Theme.ok : Theme.textMuted

        Repeater {
            model: Media.players

            Rectangle {
                id: row
                required property var modelData
                readonly property bool current: modelData === root.player
                // the hover fill bleeds past the sheet's text edge; the text stays on it
                x: -6
                width: parent.width + 12
                height: rowText.implicitHeight + 10
                color: rowMouse.containsMouse ? Theme.overlay : Theme.clear(Theme.overlay)
                Behavior on color { ColorAnimation { duration: Theme.animDuration } }

                RingIcon {
                    id: glyph
                    x: 6
                    anchors.verticalCenter: parent.verticalCenter
                    diameter: rowText.implicitHeight   // as tall as the two lines beside it
                    name: root.stateIcon(row.modelData)
                    color: row.modelData.isPlaying ? Theme.accent : Theme.textMuted
                }
                Column {
                    id: rowText
                    anchors.left: glyph.right
                    anchors.leftMargin: 8
                    anchors.right: parent.right
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    PopText {
                        width: parent.width
                        elide: Text.ElideRight
                        text: row.modelData.trackTitle || row.modelData.identity || "unknown"
                        color: row.current ? Theme.accent : Theme.text
                        font.italic: !row.modelData.isPlaying
                    }
                    PopText {
                        width: parent.width
                        elide: Text.ElideRight
                        size: 12
                        dim: 0.55
                        text: [row.modelData.trackTitle ? row.modelData.trackArtist : "",
                               row.modelData.identity].filter(x => x).join(" · ")
                    }
                }
                MouseArea {
                    id: rowMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: Media.pick(row.modelData)
                }
            }
        }
    }

    ChipBody {
        id: content
        transform: Translate { id: slide }

        RingIcon {
            anchors.verticalCenter: parent.verticalCenter
            name: root.player ? root.stateIcon(root.player) : "play"
            // the accent while something plays; paused or stopped it recedes
            color: root.player?.isPlaying ? Theme.accent : Qt.alpha(Theme.text, 0.7)
        }
        ValueText {
            font.italic: root.paused
            color: root.active ? Theme.accent : Theme.text
            text: root.text
            Behavior on width { NumberAnimation { duration: Theme.slideDuration; easing.type: Easing.OutCubic } }
        }
    }
}
