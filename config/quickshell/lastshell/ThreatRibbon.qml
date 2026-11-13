import QtQuick

// The one line that matters, as an instrument: a countdown to the storm the
// daemon says is aimed at home, or the warning in force there. The accent
// bar carries the tier colour; the words stay in ink.
Item {
    id: root

    property bool compact: false
    readonly property var storm: Radar.nearest
    readonly property bool warned: Radar.tornadoWarning || Radar.severeWarning
    readonly property var warning: Radar.homeAlerts.find(a => /Warning/.test(a.event) && /Tornado|Thunderstorm/.test(a.event)) ?? null
    readonly property color tone:
        Radar.tornadoWarning || storm?.tier === "urgent" ? Theme.crit : Theme.warn

    visible: storm !== null || warned
    implicitHeight: visible ? body.implicitHeight + (compact ? 12 : 18) : 0

    Rectangle { // ground, so the ribbon reads as one object
        anchors.fill: parent
        radius: Theme.innerRadius
        color: Qt.alpha(root.tone, 0.08)
        border.color: Qt.alpha(root.tone, 0.35)
        border.width: 1
    }
    Rectangle { // accent bar
        x: 0; y: 6
        width: 3; height: parent.height - 12

        color: root.tone
    }

    Row {
        id: body
        x: 14
        anchors.verticalCenter: parent.verticalCenter
        spacing: root.compact ? 10 : 14

        Column { // the countdown
            anchors.verticalCenter: parent.verticalCenter
            visible: root.storm !== null && root.storm.eta_min >= 0
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.storm ? String(Math.round(root.storm.eta_min)) : ""
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(root.compact ? 24 : 34)
                font.bold: true
            }
            PopText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "min"
                dim: 0.55
                size: 11
            }
        }

        LucideIcon { // no storm countdown, but a warning at home
            anchors.verticalCenter: parent.verticalCenter
            visible: root.storm === null || root.storm.eta_min < 0
            name: Radar.tornadoWarning ? "tornado" : "siren"
            color: root.tone
            font.pixelSize: root.compact ? 22 : 30
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 3
            width: root.width - x - 28

            PopText {
                width: parent.width
                elide: Text.ElideRight
                font.bold: true
                size: root.compact ? 13 : 15
                text: root.warned && root.warning
                    ? `${root.warning.event} at home${root.warning.ends ? " until " + Radar.clock(root.warning.ends) : ""}`
                    : root.storm?.over_home ? "Storm over home now"
                    : root.storm ? `Storm passes ${Radar.miles(root.storm.cpa_km)} ${Radar.point(root.storm.pass_dir)} of home ~${Radar.clock(root.storm.eta_at)}`
                    : ""
            }
            PopText {
                width: parent.width
                wrapMode: Text.WordWrap
                dim: 0.65
                size: 12
                // under a warning the headline is the warning, so the track
                // moves down here; otherwise the headline is the track
                text: !root.storm ? "no ProbSevere storm is tracking toward home"
                    : root.warned && !root.storm.over_home && root.storm.eta_min >= 0
                    ? `#${root.storm.id} passes ${Radar.miles(root.storm.cpa_km)} ${Radar.point(root.storm.pass_dir)} ~${Radar.clock(root.storm.eta_at)} · tor ${root.storm.probtor}% · ${Math.round(root.storm.mph)} mph → ${Radar.point(root.storm.heading)}`
                    : `${Radar.probs(root.storm)} · ${Math.round(root.storm.mph)} mph → ${Radar.point(root.storm.heading)} · #${root.storm.id}`
            }
        }
    }
}
