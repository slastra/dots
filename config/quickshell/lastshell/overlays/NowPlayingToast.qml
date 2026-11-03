import Quickshell
import Quickshell.Services.Mpris
import Quickshell.Wayland
import QtQuick
import ".."  // root module: Theme, Media and friends

// Now-playing card, bottom-right above the media chip: art, title, artist and
// album for a few seconds whenever a music player changes track. Browsers are
// left out (every video and autoplaying tab would announce itself), as are
// resumes and a player re-announcing the track it is already on. Like the
// volume OSD it never takes keyboard and never eats clicks.
PanelWindow {
    id: root

    property bool shown: false
    property bool armed: false   // players replay their metadata at startup
    property var shownKey: ""    // the track on the card, to drop re-announcements
    property MprisPlayer player: null

    property string title: ""
    property string artist: ""
    property string album: ""
    property string art: ""

    function isMusic(p) {
        return p && Browsers.mediatorFor(p.desktopEntry, p.identity) === ""
    }

    // Metadata trickles in after a switch (title, then artist, then art), so
    // a change only starts the settle timer; the card shows what's there
    // once the player has gone quiet for a moment.
    function changed(p) {
        if (!armed || !isMusic(p) || !p.isPlaying) return
        player = p
        settle.restart()
    }
    Timer {
        id: settle
        interval: 350
        onTriggered: {
            const p = root.player
            if (!p || !p.isPlaying || (p.trackTitle ?? "") === "") return
            const key = `${p.dbusName}|${p.trackTitle}|${p.trackArtist}`
            if (key === root.shownKey) return  // a resume, or the same track re-announced
            root.shownKey = key
            root.title = p.trackTitle
            root.artist = p.trackArtist ?? ""
            root.album = p.trackAlbum ?? ""
            root.art = p.trackArtUrl ?? ""
            root.shown = true
            hide.restart()
        }
    }
    Timer { id: hide; interval: 4500; onTriggered: root.shown = false }
    Timer { interval: 2000; running: true; onTriggered: root.armed = true }

    Variants {
        model: Media.players
        Connections {
            required property var modelData
            target: modelData
            function onTrackTitleChanged() { root.changed(modelData) }
            function onTrackArtistChanged() { root.changed(modelData) }
            function onTrackArtUrlChanged() { if (root.shown && modelData === root.player) settle.restart() }
            // a skip from paused names the new track before it reports Playing
            function onIsPlayingChanged() { root.changed(modelData) }
        }
    }

    visible: shown || card.opacity > 0
    color: "transparent"
    anchors { bottom: true; right: true }
    margins { bottom: Theme.barHeight + 14; right: 14 }
    implicitWidth: card.width
    implicitHeight: card.height
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "lastshell-nowplaying"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: Region {} // click-through, always

    Card {
        id: card
        width: 340
        height: 76
        opacity: root.shown ? 1 : 0
        transform: Translate { y: root.shown ? 0 : 8; Behavior on y { NumberAnimation { duration: Theme.animDuration; easing.type: Easing.OutCubic } } }
        Behavior on opacity { NumberAnimation { duration: Theme.animDuration; easing.type: Easing.OutCubic } }

        Rectangle { // art, or a note glyph while it loads or when there is none
            id: frame
            x: 10
            anchors.verticalCenter: parent.verticalCenter
            width: 56; height: 56
            radius: Theme.innerRadius
            color: Theme.overlay
            clip: true

            Image {
                id: cover
                anchors.fill: parent
                source: root.art
                sourceSize: Qt.size(112, 112)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                visible: status === Image.Ready
            }
            LucideIcon {
                visible: cover.status !== Image.Ready
                anchors.centerIn: parent
                name: "music"
                font.pixelSize: 22
                color: Qt.alpha(Theme.iris, 0.8)
            }
        }

        Column {
            anchors.left: frame.right
            anchors.leftMargin: 12
            anchors.right: parent.right
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            spacing: 3

            PopText {
                width: parent.width
                size: 15
                font.bold: true
                elide: Text.ElideRight
                text: root.title
            }
            PopText {
                visible: text !== ""
                width: parent.width
                size: 13
                color: Theme.rose
                elide: Text.ElideRight
                text: root.artist
            }
            PopText {
                visible: text !== ""
                width: parent.width
                size: 12
                dim: 0.5
                elide: Text.ElideRight
                text: root.album
            }
        }
    }
}
