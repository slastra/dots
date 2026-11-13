import Quickshell
import QtQuick
import ".."  // root module

// The look: the choices that sit on top of whatever color scheme is
// applied. Corner radius and border thickness for everything that draws a
// box, which of the scheme's six hues is the primary (the accent) and
// which the secondary (small print), and the font pair: a monospace for the
// terminal and the shell with its matching sans for apps, from tint's
// fonts.toml. `tint look` is the engine and holds
// the state; every change is applied to the whole desktop as it is made.
Overlay {
    id: root

    cardWidth: 480
    contentPadding: 2
    backdrop: 0.3     // the desktop is what is being changed: keep it in view

    readonly property string tint: Quickshell.env("LASTSHELL_TINT") || (Quickshell.env("HOME") + "/.local/bin/tint")
    readonly property var rows: ["radius", "border", "accent", "secondary"].concat(fonts.length ? ["font"] : [])
    property int cursor: 0

    // what tint reports, and the values on screen (ahead of it while a
    // change is on its way)
    property var info: ({})
    property int radius: 0
    property int border: 1
    property string accent: "auto"
    property string secondary: "auto"
    property string font: ""
    readonly property var fonts: info.fonts ?? []
    readonly property var fontNow: fonts.find(f => f.name === font) ?? null
    readonly property var slots: info.slots ?? []
    readonly property var choices: ["auto"].concat(slots.map(s => s.name))

    onOpenChanged: if (open) { cursor = 0; armed = false; arm.restart(); load.running = true }
    // the pointer happens to be over some row when the card appears; only a
    // pointer that arrives later moves the cursor
    property bool armed: false
    Timer { id: arm; interval: 400; onTriggered: root.armed = true }

    function take(j) {
        if (!j || j.radius === undefined) return
        info = j
        if (!send.running && !settle.running) {
            radius = j.radius; border = j.border; accent = j.accent; secondary = j.secondary; font = j.font ?? ""
        }
    }
    JsonProcess { id: load; command: [root.tint, "look", "--json"]; fallback: ({}); onResult: j => root.take(j) }

    // One apply at a time, a beat after the last change: holding an arrow
    // key should not queue a run of them.
    property bool dirty: false
    function changed() { dirty = true; settle.restart() }
    function flush() {
        if (send.running || !dirty) return
        dirty = false
        send.command = [tint, "look", "--json", "--radius", String(radius), "--border", String(border),
                        "--accent", accent, "--secondary", secondary].concat(font ? ["--font", font] : [])
        send.running = true
    }
    Timer { id: settle; interval: 220; onTriggered: root.flush() }
    JsonProcess {
        id: send
        fallback: ({})
        onResult: j => { root.take(j); if (root.dirty) root.flush() }
    }

    // the useful range is the low end of what tint allows
    readonly property var top: ({ radius: 16, border: 4 })
    function setNumber(key, v) {
        const n = Math.max(0, Math.min(top[key], Math.round(v)))
        if (root[key] === n) return
        root[key] = n
        changed()
    }
    function setChoice(key, name) {
        if (root[key] === name) return
        root[key] = name
        changed()
    }
    function step(d) {
        const key = rows[cursor]
        if (key === "radius" || key === "border") setNumber(key, root[key] + d)
        else if (key === "font") {
            const i = Math.max(0, fonts.findIndex(f => f.name === font))
            setChoice("font", fonts[(i + d + fonts.length) % fonts.length].name)
        } else {
            const i = Math.max(0, choices.indexOf(root[key]))
            setChoice(key, choices[(i + d + choices.length) % choices.length])
        }
    }
    // the color a role shows: the pinned slot's, or what tint picks by itself
    function colorOf(key, name) {
        if (name === "auto") return (info.auto ?? {})[key] ?? Theme.text
        return slots.find(s => s.name === name)?.color ?? Theme.text
    }

    // One setting: its name and current value on the left, the control on
    // the right. The row under the cursor carries the overlay fill.
    component Setting: Rectangle {
        id: setting
        property int index
        property string label
        property string value
        default property alias control: slot.data
        width: parent.width
        height: 44
        color: root.cursor === index ? Theme.overlay : Theme.clear(Theme.overlay)
        Behavior on color { ColorAnimation { duration: Theme.animDuration } }
        Rectangle { // the cursor's rule, as on an active bar item
            visible: root.cursor === setting.index
            width: 2; height: parent.height
            color: Theme.accent
        }
        PopText { x: 18; anchors.verticalCenter: parent.verticalCenter; text: setting.label }
        PopText {
            x: 118
            anchors.verticalCenter: parent.verticalCenter
            dim: 0.55
            text: setting.value
        }
        Item {
            id: slot
            anchors.right: parent.right
            anchors.rightMargin: 18
            width: 250
            height: parent.height
        }
        HoverHandler { onHoveredChanged: if (hovered && root.armed) root.cursor = setting.index }
    }

    component Swatches: Row {
        id: sw
        property string role
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6
        Repeater {
            model: root.choices
            Rectangle {
                id: chip
                required property string modelData
                readonly property bool picked: root[sw.role] === modelData
                readonly property bool isAuto: modelData === "auto"
                width: isAuto ? autoText.implicitWidth + 30 : 24
                height: 24
                radius: Theme.innerRadius
                color: isAuto ? Theme.surface : root.colorOf(sw.role, modelData)
                border.width: picked ? 2 : isAuto ? 1 : 0
                border.color: picked ? Theme.text : Theme.border
                Rectangle { // auto shows the color it resolves to
                    visible: chip.isAuto
                    x: 8; width: 8; height: 8; radius: 4
                    anchors.verticalCenter: parent.verticalCenter
                    color: root.colorOf(sw.role, "auto")
                }
                PopText {
                    id: autoText
                    visible: chip.isAuto
                    x: 22
                    anchors.verticalCenter: parent.verticalCenter
                    size: 12
                    dim: chip.picked ? 1 : 0.55
                    text: "auto"
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.setChoice(sw.role, chip.modelData)
                }
            }
        }
    }

    Column {
        width: parent.width
        focus: true

        Keys.onPressed: event => {
            const k = event.key
            if (k === Qt.Key_Escape || k === Qt.Key_Return || k === Qt.Key_Enter) root.dismiss()
            else if (k === Qt.Key_Down || k === Qt.Key_J || k === Qt.Key_Tab) root.cursor = (root.cursor + 1) % root.rows.length
            else if (k === Qt.Key_Up || k === Qt.Key_K || k === Qt.Key_Backtab) root.cursor = (root.cursor + root.rows.length - 1) % root.rows.length
            else if (k === Qt.Key_Left || k === Qt.Key_H) root.step(-1)
            else if (k === Qt.Key_Right || k === Qt.Key_L) root.step(1)
            else return
            event.accepted = true
        }

        ModalHeader { icon: "sliders-horizontal"; title: "Look"; showQuery: false }

        Column {
            width: parent.width
            topPadding: 8
            bottomPadding: 8

            Setting {
                index: 0; label: "radius"; value: `${root.radius} px`
                SliderTrack {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    frac: root.radius / root.top.radius
                    interactive: true
                    onSeek: f => root.setNumber("radius", f * root.top.radius)
                }
            }
            Setting {
                index: 1; label: "border"; value: `${root.border} px`
                SliderTrack {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    frac: root.border / root.top.border
                    interactive: true
                    onSeek: f => root.setNumber("border", f * root.top.border)
                }
            }
            Setting {
                index: 2; label: "primary"; value: root.accent
                Swatches { role: "accent" }
            }
            Setting {
                index: 3; label: "secondary"; value: root.secondary
                Swatches { role: "secondary" }
            }
            Setting { // the pair by name, then a sample of each face: the mono, its sans
                visible: root.fonts.length > 0
                index: 4; label: "font"; value: root.font
                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10
                    LucideIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: "chevron-left"; font.pixelSize: 14; color: Theme.textFaint
                        MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor
                                    onClicked: { root.cursor = 4; root.step(-1) } }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        font.family: root.fontNow?.mono ?? Theme.fontFamily
                        font.pixelSize: 13
                        color: Theme.text
                        text: "mono 0O1l"
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        font.family: root.fontNow?.sans ?? Theme.fontFamily
                        font.pixelSize: 13
                        color: Theme.secondary
                        text: "Sans Aa"
                    }
                    LucideIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: "chevron-right"; font.pixelSize: 14; color: Theme.textFaint
                        MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor
                                    onClicked: { root.cursor = 4; root.step(1) } }
                    }
                }
            }
        }

        ModalFooter {
            hint: "↑↓ setting   ←→ change   esc close"
            count: root.info.scheme ?? ""
        }
    }
}
