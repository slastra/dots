import Quickshell.Hyprland
import QtQuick

// One Claude session: drawn state dot, label, agent-count badge, and a
// rich hover card. Border shows window focus (the shared active language).
Chip {
    id: root
    required property var session

    edge: "bottom"
    active: session.focused

    onClicked: if (session.address)
        Hyprland.dispatch(`hl.dsp.focus({ window = "address:${session.address}" })`)

    Row {
        height: root.height - 2
        spacing: 8
        leftPadding: 12
        rightPadding: 12

        StateDot {
            anchors.verticalCenter: parent.verticalCenter
            state: root.session.state
        }

        ValueText {
            color: root.session.state === "waiting" ? Theme.gold : Theme.text
            text: root.session.label
            Behavior on color { ColorAnimation { duration: Theme.animDuration } }
        }

        Rectangle { // agent-count badge, only when >1
            visible: root.session.agents > 1
            anchors.verticalCenter: parent.verticalCenter
            width: badgeText.implicitWidth + 10
            height: 16
            radius: 8
            color: Theme.overlay
            border.color: Qt.alpha(Theme.iris, 0.6)
            border.width: 1
            Text {
                id: badgeText
                anchors.centerIn: parent
                font.family: Theme.fontFamily
                font.pixelSize: 11
                color: Theme.iris
                text: `×${root.session.agents}`
            }
        }
    }

    Popout {
        owner: root
        edge: "bottom"
        ownerHovered: root.hovered

        Column {
            spacing: 6

            Text {
                text: root.session.cwd
                color: Theme.text; font.family: Theme.fontFamily
                font.pixelSize: 14; font.bold: true
            }
            Row {
                spacing: 8
                StateDot { anchors.verticalCenter: parent.verticalCenter; state: root.session.state }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.session.state === "waiting" ? "waiting on you" : root.session.state
                    color: root.session.state === "waiting" ? Theme.gold : Qt.alpha(Theme.text, 0.8)
                    font.family: Theme.fontFamily; font.pixelSize: 13
                }
            }
            Repeater {
                model: root.session.jobs ?? []
                Text {
                    required property var modelData
                    text: `󰒓 ${modelData.name} — ${modelData.status}`
                    color: Qt.alpha(Theme.text, 0.7)
                    font.family: Theme.fontFamily; font.pixelSize: 13
                }
            }
            Rectangle { width: 220; height: 1; color: Theme.overlay }
            Text {
                text: `${root.session.session ?? "—"}\nup ${root.session.uptime}`
                color: Qt.alpha(Theme.text, 0.55)
                font.family: Theme.fontFamily; font.pixelSize: 12
                lineHeight: 1.3
            }
        }
    }
}
