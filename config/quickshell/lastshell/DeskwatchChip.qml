import Quickshell
import QtQuick

// deskwatch chip: the desk's health at a glance. A quiet activity trace
// while everything is fine; a shield with a count when something needs
// you. Hover lists what is bad with the exact fix, plus the last verdicts
// the triager returned. Click opens the daemon's status in a terminal.
Chip {
    id: root
    edge: "top"
    present: Deskwatch.loaded

    readonly property bool bad: Deskwatch.bad.length > 0

    function levelTone(lvl) {
        switch (lvl) {
        case "crit": case "high": return Theme.love
        case "watch": return Theme.gold
        case "low": return Theme.foam
        default: return Theme.text
        }
    }

    // The header's word for the worst level. "watch" is avoided: it is the
    // daemon's self-check key prefix and its LLM verdict word, and a third
    // meaning in the same card was one too many.
    function levelLabel(lvl) {
        switch (lvl) {
        case "crit": return "critical"
        case "high": return "high"
        case "watch": return "attention"
        default: return "low"
        }
    }

    // One glyph per level so the rows read at a glance: siren for crit,
    // octagon for high, eye for watch (the daemon's "default": look, don't
    // jump), info for low.
    function levelIcon(lvl) {
        switch (lvl) {
        case "crit": return "siren"
        case "high": return "alert-octagon"
        case "watch": return "eye"
        default: return "info"
        }
    }

    readonly property color tone:
        Deskwatch.stale || !Deskwatch.tailUp ? Qt.alpha(Theme.text, 0.45)
        : bad ? levelTone(Deskwatch.level)
        : Theme.foam

    onClicked: Quickshell.execDetached(
        ["kitty", "--hold", "-e", Quickshell.env("HOME") + "/go/bin/deskwatch", "status"])

    ChipBody {

        Badge { // attention count, only when crit/high is live
            visible: Deskwatch.attention > 0
            anchors.verticalCenter: parent.verticalCenter
            tone: Theme.love
            text: String(Deskwatch.attention)
        }

        LucideIcon {
            anchors.verticalCenter: parent.verticalCenter
            name: Deskwatch.stale || !Deskwatch.tailUp ? "radar"
                : root.bad ? "shield-alert" : "activity"
            color: root.tone
        }
    }

    Popout {
        owner: root

        Column {
            spacing: 8
            width: 360

            PopoutHeader {
                title: "deskwatch"
                status: Deskwatch.stale ? "stale snapshot"
                    : !Deskwatch.tailUp ? "gateway tail down"
                    : root.bad ? root.levelLabel(Deskwatch.level) : "all clear"
                tone: root.tone
            }

            Repeater {
                model: Deskwatch.bad
                Column {
                    required property var modelData
                    width: parent.width
                    spacing: 2
                    Row {
                        spacing: 6
                        LucideIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            name: root.levelIcon(modelData.level)
                            color: root.levelTone(modelData.level)
                            font.pixelSize: 13
                        }
                        PopText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.key
                            color: root.levelTone(modelData.level)
                            size: 13
                        }
                    }
                    PopText {
                        width: parent.width
                        text: modelData.detail
                        wrapMode: Text.WordWrap
                        dim: 0.85
                        size: 13
                    }
                    PopText {
                        visible: (modelData.fix ?? "") !== ""
                        width: parent.width
                        text: `$ ${modelData.fix}`
                        wrapMode: Text.WrapAnywhere
                        color: Qt.alpha(Theme.foam, 0.8)
                        size: 12
                    }
                }
            }

            Divider { width: parent.width; visible: Deskwatch.verdicts.length > 0 }

            Repeater {
                model: Deskwatch.verdicts.slice(0, 3)
                Column {
                    required property var modelData
                    width: parent.width
                    spacing: 1
                    // Verdicts use the same glyph language as the flags:
                    // escalate is a siren, watch an eye, benign a check.
                    Row {
                        width: parent.width
                        spacing: 6
                        readonly property color vtone:
                            modelData.verdict === "benign" ? Theme.text
                          : modelData.verdict === "watch" ? Theme.gold : Theme.love
                        LucideIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            name: modelData.verdict === "benign" ? "check"
                                : modelData.verdict === "watch" ? "eye" : "siren"
                            color: parent.vtone
                            font.pixelSize: 12
                        }
                        PopText {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 18
                            elide: Text.ElideMiddle
                            text: modelData.gkey.split("|").slice(0, 2).join(" ")
                            color: parent.vtone
                            size: 12
                        }
                    }
                    PopText {
                        width: parent.width
                        text: modelData.reason
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        dim: 0.55
                        size: 12
                    }
                }
            }

            PopText {
                text: [
                    Deskwatch.presence ? `presence ${Deskwatch.presence}` : "",
                    `${Deskwatch.evalsLastHour} evals/h`,
                    `gateway ${Deskwatch.age}s ago`,
                ].filter(s => s).join("  ·  ")
                dim: 0.45
                size: 12
            }
        }
    }
}
