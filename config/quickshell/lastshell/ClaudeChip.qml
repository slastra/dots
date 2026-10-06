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

    ChipBody {

        StateDot {
            anchors.verticalCenter: parent.verticalCenter
            state: root.session.state
        }

        ValueText {
            color: root.session.state === "waiting" ? Theme.gold : Theme.text
            text: root.session.label
        }

        Badge { // agent count, only when >1
            visible: root.session.agents > 1
            anchors.verticalCenter: parent.verticalCenter
            tone: Theme.iris
            text: `×${root.session.agents}`
        }
    }

    Popout {
        owner: root

        Column {
            spacing: 6

            PopText {
                text: root.session.cwd
                size: 14; font.bold: true
            }
            Row {
                spacing: 8
                StateDot { anchors.verticalCenter: parent.verticalCenter; state: root.session.state }
                PopText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.session.state === "waiting" ? "waiting on you" : root.session.state
                    color: root.session.state === "waiting" ? Theme.gold : Qt.alpha(Theme.text, 0.8)
                    size: 13
                }
            }
            Repeater {
                model: root.session.jobs ?? []
                PopText {
                    required property var modelData
                    text: `󰒓 ${modelData.name} — ${modelData.status}`
                    dim: 0.7
                    size: 13
                }
            }
            Divider { width: 220 }
            PopText {
                text: `${root.session.session ?? "—"}\nup ${root.session.uptime}`
                dim: 0.55
                size: 12
                lineHeight: 1.3
            }
        }
    }
}
