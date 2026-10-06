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

        Column {
            spacing: 6
            width: 320

            PopoutHeader {
                title: "media"
                status: Media.players.length === 1 ? "1 player" : `${Media.players.length} players`
                tone: Media.playing.length > 0 ? Theme.foam : Theme.textMuted
            }

            Divider { width: parent.width }

            Repeater {
                model: Media.players

                Rectangle {
                    id: row
                    required property var modelData
                    readonly property bool current: modelData === root.player
                    width: parent.width
                    height: rowText.implicitHeight + 12
                    radius: Theme.innerRadius
                    color: rowMouse.containsMouse ? Theme.overlay : "transparent"
                    border.color: current ? Qt.alpha(Theme.rose, 0.6) : "transparent"
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: Theme.animDuration } }

                    LucideIcon {
                        id: glyph
                        x: 8
                        anchors.verticalCenter: parent.verticalCenter
                        name: root.stateIcon(row.modelData)
                        font.pixelSize: 13
                        color: row.modelData.isPlaying ? Theme.foam : Theme.textMuted
                    }
                    Column {
                        id: rowText
                        anchors.left: glyph.right
                        anchors.leftMargin: 8
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        PopText {
                            width: parent.width
                            elide: Text.ElideRight
                            text: row.modelData.trackTitle || row.modelData.identity || "unknown"
                            color: row.current ? Theme.rose : Theme.text
                            font.italic: !row.modelData.isPlaying
                        }
                        PopText {
                            width: parent.width
                            elide: Text.ElideRight
                            size: 12
                            dim: 0.5
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
    }

    ChipBody {
        id: content
        transform: Translate { id: slide }

        LucideIcon {
            anchors.verticalCenter: parent.verticalCenter
            name: root.player ? root.stateIcon(root.player) : "play"
            font.pixelSize: 13
            color: Qt.alpha(root.active ? Theme.rose : Theme.text, 0.7)
        }
        ValueText {
            font.italic: root.paused
            color: root.active ? Theme.rose : Theme.text
            text: root.text
            Behavior on width { NumberAnimation { duration: Theme.slideDuration; easing.type: Easing.OutCubic } }
        }
    }
}
