import Quickshell
import Quickshell.Services.Pipewire
import QtQuick
import ".."  // root module: Theme, Audio and friends

// Per-app volume (Super+Shift+A), the picker's sibling: the default output
// on top, then one row per playback stream. A stream is a row, not an app,
// so two Firefox tabs are two rows, each titled by its media name.
// ↑↓ select, ←→ step 5% (Shift 1%), 1–9 and 0 jump to 10–100%, m mutes.
Overlay {
    id: root

    cardWidth: 560
    contentPadding: 2

    readonly property int rowH: 52
    readonly property int maxRows: 7

    // Playback streams only (a capture stream is a sink-less recorder). Raw
    // filter of Pipewire.nodes, nothing derived from defaultAudioSink: see
    // the tracker note in AudioPicker.qml. The output row rides on the
    // Audio singleton, which tracks the sinks itself.
    readonly property var streams: Pipewire.nodes.values
        .filter(n => n.isStream && n.isSink && n.audio)
        .sort((a, b) => appName(a).localeCompare(appName(b)) || a.id - b.id)
    PwObjectTracker { objects: root.streams }

    property int cursor: 0          // 0 = the output, 1.. = streams
    onOpenChanged: if (open) cursor = 0
    onStreamsChanged: cursor = Math.min(cursor, streams.length)

    function nodeAt(i) { return i === 0 ? Audio.sink : streams[i - 1] ?? null }

    // ALSA clients arrive wrapped ("PipeWire ALSA [emotune]"); unwrap them.
    function appName(n) {
        const p = n.properties ?? {}
        const a = p["application.name"] ?? n.name ?? "unknown"
        return a.replace(/^PipeWire ALSA \[(.*)\]$/, "$1")
    }
    // The media name when it says something the app name doesn't.
    function mediaName(n) {
        const m = (n.properties ?? {})["media.name"] ?? ""
        return /^(-|playback|ALSA Playback|audio stream|Playback)?$/i.test(m)
            || m === appName(n) ? "" : m
    }
    function iconFor(n) {
        const p = n.properties ?? {}
        const named = p["application.icon-name"] ?? ""
        if (named !== "") {
            const path = Quickshell.iconPath(named, true)
            if (path !== "") return path
        }
        void DesktopEntries.applications.values  // re-run once entries load
        const e = DesktopEntries.heuristicLookup(p["application.process.binary"] ?? appName(n))
        return e?.icon ? Quickshell.iconPath(e.icon, true) : ""
    }

    // Streams cap at 100%; the output keeps the chip's 150% headroom.
    function setVol(i, v) {
        if (i === 0) { Audio.setVolume(v); return }
        const n = nodeAt(i)
        if (n?.audio) n.audio.volume = Math.max(0, Math.min(1, v))
    }
    function step(i, d) { setVol(i, (nodeAt(i)?.audio?.volume ?? 0) + d) }
    function toggleMute(i) {
        const n = nodeAt(i)
        if (n?.audio) n.audio.muted = !n.audio.muted
    }

    // keep the selected stream in view when the list scrolls
    onCursorChanged: {
        if (cursor === 0) { flick.contentY = 0; return }
        const top = (cursor - 1) * (rowH + 2)
        if (top < flick.contentY) flick.contentY = top
        else if (top + rowH > flick.contentY + flick.height) flick.contentY = top + rowH - flick.height
    }

    // One mixer strip: icon, name over media, slider, level, mute.
    component MixRow: Item {
        id: row
        property int slot   // cursor position: 0 = the output
        property PwNode node
        property string label
        property string sublabel: ""
        property string iconSource: ""
        property string glyph: "audio-lines"
        readonly property bool selected: root.cursor === slot
        readonly property real vol: node?.audio?.volume ?? 0
        readonly property bool muted: node?.audio?.muted ?? false

        width: parent.width
        height: root.rowH

        Rectangle {
            anchors.fill: parent
            radius: Theme.innerRadius
            color: row.selected ? Theme.overlay : "transparent"
            border.width: 2
            border.color: row.selected ? Qt.alpha(Theme.rose, 0.8) : "transparent"
            Behavior on border.color { ColorAnimation { duration: Theme.animDuration } }
        }
        MouseArea { // under the slider and mute: selects, wheel steps 2%
            anchors.fill: parent
            onPressed: root.cursor = row.slot
            onWheel: wheel => {
                root.cursor = row.slot
                root.step(row.slot, wheel.angleDelta.y > 0 ? 0.02 : -0.02)
            }
        }

        Image {
            id: icon
            x: 14
            anchors.verticalCenter: parent.verticalCenter
            width: 22; height: 22
            source: row.iconSource
            sourceSize: Qt.size(44, 44)
            visible: row.iconSource !== ""
            opacity: row.muted ? 0.45 : 1
        }
        LucideIcon {
            visible: row.iconSource === ""
            anchors.centerIn: icon
            name: row.glyph
            font.pixelSize: 17
            color: Qt.alpha(Theme.iris, row.muted ? 0.4 : 0.8)
        }

        Column {
            x: 48
            anchors.verticalCenter: parent.verticalCenter
            width: 176
            spacing: 2
            PopText {
                width: parent.width
                size: 14
                elide: Text.ElideRight
                color: row.muted ? Theme.textMuted : row.selected ? Theme.text : Qt.alpha(Theme.text, 0.8)
                text: row.label
            }
            PopText {
                visible: text !== ""
                width: parent.width
                size: 11
                dim: 0.45
                elide: Text.ElideRight
                text: row.sublabel
            }
        }

        SliderTrack {
            x: 236
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - x - 104
            frac: row.vol
            fill: row.muted ? Qt.alpha(Theme.love, 0.6) : row.selected ? Theme.rose : Theme.pine
            interactive: true
            onSeek: f => { root.cursor = row.slot; root.setVol(row.slot, f) }
        }

        ValueText { // places itself on the row's center line
            anchors.right: mute.left
            anchors.rightMargin: 10
            color: row.muted ? Theme.textMuted : Theme.text
            text: `${Theme.pad(Math.round(row.vol * 100), 3)}%`
        }

        LucideIcon {
            id: mute
            anchors.right: parent.right
            anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            name: row.muted ? "volume-x" : "volume-2"
            font.pixelSize: 16
            color: row.muted ? Theme.love : muteHit.containsMouse ? Theme.text : Theme.textFaint
            MouseArea {
                id: muteHit
                anchors.fill: parent
                anchors.margins: -6
                hoverEnabled: true
                onClicked: { root.cursor = row.slot; root.toggleMute(row.slot) }
            }
        }
    }

    Column {
        width: parent.width
        focus: true

        Keys.onPressed: event => {
            const k = event.key
            const fine = event.modifiers & Qt.ShiftModifier
            const last = root.streams.length
            if (k === Qt.Key_Escape) root.dismiss()
            else if (k === Qt.Key_Down || k === Qt.Key_J || (k === Qt.Key_Tab && !fine))
                root.cursor = Math.min(last, root.cursor + 1)
            else if (k === Qt.Key_Up || k === Qt.Key_K || k === Qt.Key_Backtab)
                root.cursor = Math.max(0, root.cursor - 1)
            else if (k === Qt.Key_Right || k === Qt.Key_L) root.step(root.cursor, fine ? 0.01 : 0.05)
            else if (k === Qt.Key_Left || k === Qt.Key_H) root.step(root.cursor, fine ? -0.01 : -0.05)
            else if (k === Qt.Key_M || k === Qt.Key_Space) root.toggleMute(root.cursor)
            else if (k >= Qt.Key_1 && k <= Qt.Key_9) root.setVol(root.cursor, (k - Qt.Key_0) / 10)
            else if (k === Qt.Key_0) root.setVol(root.cursor, 1)
            else return
            event.accepted = true
        }

        ModalHeader { icon: "sliders-horizontal"; title: "Mixer"; showQuery: false }

        Column {
            x: 10
            width: parent.width - 20
            topPadding: 12
            bottomPadding: 12
            spacing: 2

            SectionLabel { x: 14; height: 22; verticalAlignment: Text.AlignVCenter; text: "output" }
            MixRow {
                slot: 0
                node: Audio.sink
                label: Audio.description
                glyph: Audio.bluetooth ? "bluetooth" : "volume-2"
            }

            Item { width: 1; height: 8 }
            SectionLabel { x: 14; height: 22; verticalAlignment: Text.AlignVCenter; text: "apps" }

            Flickable {
                id: flick
                width: parent.width
                height: Math.max(root.rowH, Math.min(content.height, root.maxRows * (root.rowH + 2) - 2))
                contentHeight: content.height
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                Behavior on contentY { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }

                Column {
                    id: content
                    width: flick.width
                    spacing: 2
                    // ScriptModel diffs by identity: a stream coming or going
                    // leaves the other rows (and a drag in progress) alone
                    Repeater {
                        model: ScriptModel { values: root.streams }
                        MixRow {
                            required property PwNode modelData
                            required property int index
                            slot: index + 1
                            node: modelData
                            label: root.appName(modelData)
                            sublabel: root.mediaName(modelData)
                            iconSource: root.iconFor(modelData)
                        }
                    }
                }

                PopText { // empty state
                    visible: root.streams.length === 0
                    anchors.centerIn: parent
                    size: 14
                    font.italic: true
                    color: Qt.alpha(Theme.love, 0.7)
                    text: "nothing playing"
                }
            }
        }

        ModalFooter {
            hint: "↑↓ select   ←→ volume   m mute   esc close"
            count: `${root.streams.length} ${root.streams.length === 1 ? "stream" : "streams"}`
        }
    }
}
