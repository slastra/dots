import QtQuick

// deskpresence chip: is anyone at the desk, as the radar and the input
// layer see it. Foam while you are here, muted while away (or an hour
// without input), love when the sensor has gone quiet (input idle guards
// the OLED alone), gold while paused. Hover for the verdict,
// how long it has held, the TV state and the closest target. Click opens
// the live gate view; right-click toggles the daemon's pause file. The
// popout has rows to stop the Office Light or audio following presence
// and to hold the daemon off (keep awake) for 30 minutes.
Chip {
    id: root
    edge: "top"
    present: Presence.loaded


    readonly property bool stale: !Presence.sensorOk || !Presence.known
    readonly property color tone:
        root.stale ? Theme.crit
        : Presence.paused ? Theme.warn
        : Presence.present ? Theme.ok
        : Qt.alpha(Theme.text, 0.45)

    // ticks once a second while the popout is up so "for 4m 12s" stays honest
    // (the card outlives the chip hover: the pointer can sit on it)
    property double now: Date.now()
    Timer { interval: 1000; running: pop.visible; repeat: true; onTriggered: root.now = Date.now() }

    function holdLeft() {
        const s = Math.max(0, Math.round((Presence.holdUntil - now) / 1000))
        return s >= 60 ? `${Math.ceil(s / 60)}m` : `${s}s`
    }

    function held() {
        if (!Presence.since) return ""
        const s = Math.max(0, Math.floor((now - Presence.since) / 1000))
        if (s < 60) return `${s}s`
        if (s < 3600) return `${Math.floor(s / 60)}m ${s % 60}s`
        return `${Math.floor(s / 3600)}h ${Math.floor(s % 3600 / 60)}m`
    }

    onClicked: Presence.openView()
    onRightClicked: Presence.togglePause()

    ChipBody {

        LucideIcon {
            anchors.verticalCenter: parent.verticalCenter
            name: root.stale ? "radar" : Presence.paused ? "eye" : Presence.present ? "user" : "radar"
            color: root.tone
        }
    }

    Popout {
        id: pop
        owner: root
        onVisibleChanged: {
            Presence.historyWatchers += visible ? 1 : -1
            if (visible) root.now = Date.now()
        }

        sheetWidth: Theme.popM
        title: "deskpresence"
        status: root.stale ? "sensor silent"
            : Presence.holdUntil > 0 ? "held awake"
            : Presence.input === "away" ? "away, no input for 1 h"
            : Presence.paused ? "paused"
            : Presence.present ? "present" : "away"
        tone: root.tone
        note: "click: live view  ·  right-click: " + (Presence.paused ? "resume" : "pause")

        PopText {
            visible: root.stale
            width: parent.width
            wrapMode: Text.WordWrap
            text: "No frames from the LD2410C. Keyboard and mouse idle decides the screen alone."
            color: Qt.alpha(Theme.crit, 0.9)
            size: 12
        }

        // gate energy is the radar's; the laptop's ToF sensor has none
        PresenceGraph { width: parent.width; height: 56; live: pop.visible; visible: Host.desk }
        PopNote {
            visible: Host.desk
            text: `near-gate moving energy, 60 s  ·  present ≥ ${Presence.threshold}`
        }

        KeyValueRow { key: "for"; value: root.held() }
        KeyValueRow { key: "input"; value: Presence.input === "unknown" ? "unknown (hypridle not running)" : (Presence.input || "?") }
        KeyValueRow { key: Host.desk ? "tv" : "screen"; value: Presence.busy ? `${Presence.tv || "?"} (switching)` : (Presence.tv || "unknown") }
        KeyValueRow { key: "target"; value: Presence.state === 0 ? "none" : `${Presence.stateWord} at ${Presence.distance} cm` }

        // divider, then the controls
        Divider { width: parent.width }

        PopSwitch {
            visible: Host.desk   // the office light is the desk's
            icon: Presence.lightFollow ? "lightbulb" : "lightbulb-off"
            on: Presence.lightFollow
            label: "office light"
            word: on ? "follows" : "manual"
            onClicked: Presence.toggleLight()
        }
        PopSwitch {
            icon: Presence.audioFollow ? "volume-2" : "volume-x"
            on: Presence.audioFollow
            label: "audio"
            word: on ? "fades" : "manual"
            onClicked: Presence.toggleAudio()
        }
        // away timer: how long the desk must read empty before the TV
        // goes off, 10 s to 30 min. Longer for a film night, when sitting
        // still reads as gone; shorter when the OLED matters more.
        Item {
            width: parent.width
            height: 28
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                LucideIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: "timer"
                    color: Theme.textMuted
                }
                PopText { anchors.verticalCenter: parent.verticalCenter; text: "away after" }
            }
            Row {
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                spacing: 8
                PopText {
                    anchors.verticalCenter: parent.verticalCenter
                    size: 12
                    dim: 0.55
                    text: Presence.absenceSecs >= 60
                        ? `${Math.floor(Presence.absenceSecs / 60)}m${Presence.absenceSecs % 60 ? " " + Presence.absenceSecs % 60 + "s" : ""}`
                        : `${Presence.absenceSecs}s`
                }
                SliderTrack {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 110
                    frac: (Presence.absenceSecs - Presence.absenceMin) / (Presence.absenceMax - Presence.absenceMin)
                    interactive: true
                    onSeek: f => Presence.setAbsence(Presence.absenceMin + f * (Presence.absenceMax - Presence.absenceMin))
                }
            }
        }

        PopSwitch {
            icon: "coffee"
            on: Presence.holdUntil > 0
            label: "keep awake"
            word: on ? `${root.holdLeft()} left` : "30 min"
            onClicked: Presence.hold(on ? 0 : 30)
        }

    }
}
