import QtQuick

// The reader's player (Super+T reads; services/Reader.qml): the passage being
// read, progress, transport, speed, voice and tidy. Lifted unchanged from the
// old ReaderChip popout so the Voice popout can hold it; `live` gates the
// progress sweep to when it's on screen.
Column {
    id: root
    property bool live: true
    readonly property var s: Reader.state
    readonly property bool starting: Reader.starting

    spacing: 12
    width: 380

    PopText { // the passage being read
        width: parent.width
        wrapMode: Text.Wrap
        maximumLineCount: 8
        elide: Text.ElideRight
        size: 14
        color: root.starting ? Theme.textMuted : Theme.text
        text: root.s.passage || "Preparing…"
    }

    Column {
        width: parent.width
        spacing: 4
        SliderTrack {
            width: parent.width
            height: 6
            frac: root.live ? Reader.progress : 0
            fill: Theme.foam
        }
        Item {
            width: parent.width
            height: elapsed.implicitHeight
            PopText { id: elapsed; size: 12; dim: 0.7; text: Reader.clock(root.s.elapsed) }
            PopText {
                anchors.right: parent.right
                size: 12; dim: 0.45
                text: (root.s.settled ? "of " : "of ~") + Reader.clock(root.s.total)
            }
        }
    }

    Row { // transport
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 24
        Repeater {
            model: [
                { icon: "skip-back", act: () => Reader.prev(), tip: "previous" },
                { icon: Reader.playing ? "pause" : "play", act: () => Reader.toggle(), big: true },
                { icon: "skip-forward", act: () => Reader.next(), tip: "next" },
                { icon: "square", act: () => Reader.stop(), tip: "stop" },
            ]
            LucideIcon {
                required property var modelData
                name: modelData.icon
                font.pixelSize: modelData.big ? 22 : 16
                color: tap.containsMouse ? Theme.rose : modelData.big ? Theme.text : Theme.textMuted
                anchors.verticalCenter: parent.verticalCenter
                MouseArea {
                    id: tap
                    anchors.fill: parent
                    anchors.margins: -6
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: parent.modelData.act()
                }
            }
        }
    }

    Divider { width: parent.width }

    // speed: 0.5x .. 3x in 0.05 steps; marks at 1, 1.5, 2, 2.5; the
    // wheel nudges a step
    Column {
        width: parent.width
        spacing: 6
        Item {
            width: parent.width
            height: speedLabel.implicitHeight
            SectionLabel { id: speedLabel; text: "speed" }
            PopText {
                anchors.right: parent.right
                size: 12
                color: Math.abs(Reader.speed - 1) < 0.001 ? Theme.textMuted : Theme.iris
                text: `${Reader.speed.toFixed(2)}×`
            }
        }
        Item {
            width: parent.width
            height: 14
            SliderTrack {
                id: speedTrack
                width: parent.width
                anchors.verticalCenter: parent.verticalCenter
                interactive: true
                fill: Theme.iris
                frac: (Reader.speed - 0.5) / 2.5
                onSeek: f => Reader.setSpeed(0.5 + f * 2.5)
            }
            Repeater {
                model: [1, 1.5, 2, 2.5]
                Rectangle {
                    required property real modelData
                    x: speedTrack.width * (modelData - 0.5) / 2.5 - 1
                    anchors.verticalCenter: parent.verticalCenter
                    width: 2; height: 14; radius: 1
                    color: Qt.alpha(Theme.text, 0.25)
                }
            }
            MouseArea { // wheel only; presses fall through to the track
                anchors.fill: parent
                acceptedButtons: Qt.NoButton
                onWheel: w => Reader.nudgeSpeed(w.angleDelta.y > 0 ? 1 : -1)
            }
        }
    }

    Column { // voice: the config's shortlist, else every voice found
        width: parent.width
        spacing: 6
        SectionLabel { text: "voice" }
        ListView {
            id: voiceList
            width: parent.width
            readonly property int rowH: 28
            height: Math.min(count, 5) * (rowH + 2)
            clip: true
            spacing: 2
            boundsBehavior: Flickable.StopAtBounds
            model: Reader.voices
            currentIndex: Reader.voices.findIndex(v => v.key === Reader.config.voice)
            onVisibleChanged: if (visible) positionViewAtIndex(currentIndex, ListView.Center)
            delegate: Rectangle {
                required property var modelData
                readonly property bool current: modelData.key === Reader.config.voice
                width: voiceList.width
                height: voiceList.rowH
                radius: Theme.innerRadius
                color: vHover.hovered ? Theme.overlay : "transparent"
                border.color: current ? Qt.alpha(Theme.rose, 0.6) : "transparent"
                border.width: 1
                PopText {
                    x: 10
                    width: parent.width - 20
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideRight
                    size: 13
                    color: parent.current ? Theme.rose : Theme.text
                    text: parent.modelData.label
                }
                HoverHandler { id: vHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: Reader.pickVoice(parent.modelData.key) }
            }
        }
    }

    Column { // tidy: rewrite terminal-looking text for speech first
        width: parent.width
        spacing: 6
        Item {
            width: parent.width
            height: tidyLabel.implicitHeight
            SectionLabel { id: tidyLabel; text: "tidy" }
            PopText {
                anchors.right: parent.right
                size: 12; dim: 0.45
                text: Reader.config.tidy_available ? "rewrite terminal output for speech" : "no OpenRouter key"
            }
        }
        Segmented {
            width: parent.width
            enabled: Reader.config.tidy_available === true
            options: Reader.tidyModes.map(m => ({ value: m, label: m.toLowerCase() }))
            current: Reader.config.tidy
            onPicked: v => Reader.setTidy(v)
        }
    }
}
