import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import QtQuick
import ".."  // root module

// Eco mode control (laptop). eco.sh stays the engine — it saves and
// restores the prior profile, Bluetooth and keyboard light — so this only
// reads state and calls it. Space toggles eco; 1–3 or ←/→ set the CPU
// profile directly. State is polled while open: every source (ppd, rfkill,
// sysfs, systemd, hyprctl) would need its own watcher otherwise.
Overlay {
    id: root

    cardWidth: 460
    contentPadding: 2

    readonly property string script: Quickshell.env("HOME") + "/.config/hypr/scripts/eco.sh"
    readonly property var profiles: [
        ["power-saver", "saver"], ["balanced", "balanced"], ["performance", "performance"]
    ]

    property var st: ({})
    // eco itself is services/Eco.qml's (eco.sh's state file); the poll
    // below is only for what eco touches
    readonly property bool eco: Eco.active
    property bool scriptFound: true
    property bool busy: false

    readonly property var dev: UPower.displayDevice
    readonly property bool onBattery: dev?.state === UPowerDeviceState.Discharging

    onOpenChanged: if (open) poll.running = true

    function toggleEco() {
        if (busy) return
        busy = true
        run.command = ["bash", script, eco ? "off" : "on"]
        run.running = true
    }
    function setProfile(p) {
        if (busy || p === st.profile) return
        busy = true
        run.command = ["powerprofilesctl", "set", p]
        run.running = true
    }
    function stepProfile(d) {
        const i = profiles.findIndex(p => p[0] === st.profile)
        const j = Math.max(0, Math.min(profiles.length - 1, (i < 0 ? 1 : i) + d))
        setProfile(profiles[j][0])
    }

    Process {
        id: poll
        command: ["bash", "-c", `
            [ -x '${root.script}' ] && echo found=1 || echo found=0
            echo "profile=$(powerprofilesctl get 2>/dev/null)"
            rfkill list bluetooth 2>/dev/null | grep -q 'Soft blocked: yes' && echo bt=off || echo bt=on
            echo "kbd=$(cat /sys/class/leds/platform::kbd_backlight/brightness 2>/dev/null || echo 0)"
            echo "glaze=$(systemctl --user is-active hyprglaze.service 2>/dev/null)"
            echo "hz=$(hyprctl monitors -j 2>/dev/null | jq -r '.[0].refreshRate | round')"
        `]
        stdout: StdioCollector {
            onStreamFinished: {
                const s = {}
                for (const line of text.split("\n")) {
                    const i = line.indexOf("=")
                    if (i > 0) s[line.slice(0, i)] = line.slice(i + 1)
                }
                root.st = s
                root.scriptFound = s.found !== "0"
            }
        }
    }
    Process {
        id: run
        onExited: { root.busy = false; poll.running = true }
    }
    Timer {
        interval: 2000; repeat: true
        running: root.open && !root.busy
        onTriggered: poll.running = true
    }

    Column {
        width: parent.width
        focus: true

        Keys.onPressed: event => {
            const k = event.key
            if (k === Qt.Key_Escape) root.dismiss()
            else if (k === Qt.Key_Space || k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_E) root.toggleEco()
            else if (k === Qt.Key_Left || k === Qt.Key_H) root.stepProfile(-1)
            else if (k === Qt.Key_Right || k === Qt.Key_L) root.stepProfile(1)
            else if (k >= Qt.Key_1 && k <= Qt.Key_3) root.setProfile(root.profiles[k - Qt.Key_1][0])
            else return
            event.accepted = true
        }

        ModalHeader { icon: "leaf"; title: "Eco mode"; showQuery: false }

        Column {
            x: 18
            width: parent.width - 36
            topPadding: 16
            bottomPadding: 16
            spacing: 16

            // master switch: the whole row is the hit target
            Item {
                width: parent.width
                height: 44

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 3
                    PopText {
                        size: 15; font.bold: true
                        color: root.eco ? Theme.foam : Theme.text
                        text: !root.scriptFound ? "eco.sh not found" : root.eco ? "On" : "Off"
                    }
                    PopText {
                        size: 12; dim: 0.5
                        text: root.eco ? "power saver · 60 Hz · no effects · Bluetooth off"
                                       : "maximum battery life, restores everything on exit"
                    }
                }

                Rectangle { // switch
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 46; height: 24; radius: 12
                    color: root.eco ? Qt.alpha(Theme.foam, 0.3) : Theme.overlay
                    border.color: root.eco ? Theme.foam : Theme.border
                    border.width: 1
                    opacity: root.busy ? 0.5 : 1
                    Behavior on color { ColorAnimation { duration: Theme.animDuration } }

                    Rectangle {
                        width: 16; height: 16; radius: 8
                        anchors.verticalCenter: parent.verticalCenter
                        x: root.eco ? parent.width - width - 4 : 4
                        color: root.eco ? Theme.foam : Theme.textMuted
                        Behavior on x { NumberAnimation { duration: Theme.animDuration; easing.type: Easing.OutCubic } }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleEco()
                }
            }

            Rectangle { width: parent.width; height: 1; color: Theme.divider }

            // CPU profile: independent of eco (eco just picks saver)
            Column {
                width: parent.width
                spacing: 8
                SectionLabel { text: "cpu profile" }
                Segmented {
                    width: parent.width
                    options: root.profiles.map((p, i) => ({ value: p[0], label: `${i + 1}  ${p[1]}` }))
                    current: root.st.profile
                    onPicked: v => root.setProfile(v)
                }
            }

            Rectangle { width: parent.width; height: 1; color: Theme.divider }

            // what eco touches, as it stands right now
            Grid {
                columns: 2
                columnSpacing: 24
                rowSpacing: 8
                width: parent.width

                component Stat: Row {
                    property string icon
                    property string label
                    property string value
                    property color tone: Theme.text
                    spacing: 10
                    width: (parent.width - 24) / 2
                    LucideIcon { name: parent.icon; font.pixelSize: 14; color: Theme.textMuted; anchors.verticalCenter: parent.verticalCenter }
                    PopText { text: parent.label; dim: 0.5; size: 12; width: 76; anchors.verticalCenter: parent.verticalCenter }
                    PopText { text: parent.value; color: parent.tone; size: 12; anchors.verticalCenter: parent.verticalCenter }
                }

                Stat { icon: "monitor"; label: "refresh"; value: root.st.hz ? `${root.st.hz} Hz` : "–" }
                Stat {
                    icon: "gauge"; label: "draw"
                    value: root.onBattery && root.dev.changeRate > 0 ? `${root.dev.changeRate.toFixed(1)} W` : "on AC"
                    tone: root.onBattery ? Theme.level(root.dev.changeRate, 8, 12) : Theme.textMuted
                }
                Stat {
                    icon: root.st.bt === "off" ? "bluetooth-off" : "bluetooth"; label: "bluetooth"
                    value: root.st.bt ?? "–"
                    tone: root.st.bt === "on" ? Theme.text : Theme.textMuted
                }
                Stat {
                    icon: "keyboard"; label: "kbd light"
                    value: root.st.kbd > 0 ? `level ${root.st.kbd}` : "off"
                    tone: root.st.kbd > 0 ? Theme.text : Theme.textMuted
                }
                Stat {
                    icon: "sparkles"; label: "hyprglaze"
                    value: root.st.glaze === "active" ? "running" : "stopped"
                    tone: root.st.glaze === "active" ? Theme.text : Theme.textMuted
                }
                Stat {
                    icon: "battery"; label: "battery"
                    value: `${Math.round((root.dev?.percentage ?? 0) * 100)}%`
                    tone: Theme.level(100 - (root.dev?.percentage ?? 0) * 100, 80, 90)
                }
            }
        }

        ModalFooter {
            hint: "space toggle   1–3 ←→ profile   esc close"
            count: root.busy ? "applying…" : ""
        }
    }
}
