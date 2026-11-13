import Quickshell.Hyprland
import QtQuick

// One Claude session: drawn state dot, label, agent-count badge, and a
// rich hover card. The accent rule shows window focus (the shared active language).
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
            color: root.session.state === "waiting" ? Theme.warn : Theme.text
            text: root.session.label
        }

        Badge { // agent count, only when >1
            visible: root.session.agents > 1
            anchors.verticalCenter: parent.verticalCenter
            tone: Theme.agent
            text: `×${root.session.agents}`
        }
    }

    Popout {
        owner: root
        title: root.session.cwd
        status: root.session.state === "waiting" ? "waiting on you" : root.session.state
        tone: root.session.state === "waiting" ? Theme.warn
            : root.session.state === "busy" ? Theme.ok : Theme.textMuted

        Repeater {
            model: root.session.jobs ?? []
            KeyValueRow {
                required property var modelData
                key: modelData.name
                value: modelData.status
            }
        }
        KeyValueRow { key: "session"; value: root.session.session ?? "—" }
        KeyValueRow { key: "up"; value: root.session.uptime }
    }
}
