import Quickshell
import Quickshell.Io
import QtQuick
import ".."  // root module

// Hotkey cheatsheet (SUPER+/, the last rofi surface). Data comes from
// hotkeys.py --json — the same live binds.lua parse the rofi sheet used,
// kept because its whole point is that the sheet cannot drift. Sections
// flow into columns; typing filters rows and hides emptied sections.
Overlay {
    id: root

    property var sections: []
    property string query: ""

    cardWidth: 1180
    contentPadding: 2

    onOpenChanged: {
        if (open) { query = ""; loader.running = true }
    }

    Process {
        id: loader
        command: ["python3", Quickshell.env("HOME") + "/.config/rofi/scripts/hotkeys.py", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.sections = JSON.parse(text) } catch (e) { root.sections = [] }
            }
        }
    }

    readonly property var filtered: {
        if (query === "") return sections
        const q = query.toLowerCase()
        const out = []
        for (const sec of sections) {
            const rows = sec.rows.filter(r =>
                (r.key + " " + r.desc + " " + sec.section).toLowerCase().includes(q))
            if (rows.length > 0)
                out.push({ section: sec.section, rows: rows })
        }
        return out
    }
    readonly property int shownCount: filtered.reduce((n, s) => n + s.rows.length, 0)

    Column {
        width: parent.width
        focus: true

        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape)
                root.query !== "" ? root.query = "" : root.dismiss()
            else if (event.key === Qt.Key_Backspace)
                root.query = root.query.slice(0, -1)
            else if (event.text && event.text >= " ")
                root.query += event.text
            else
                return
            event.accepted = true
        }

        Rectangle { // header
            width: parent.width
            height: 54
            topLeftRadius: 6
            topRightRadius: 6
            color: Theme.overlay

            Row {
                anchors.verticalCenter: parent.verticalCenter
                x: 18
                spacing: 12
                LucideIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: "keyboard"; font.pixelSize: 18; color: Theme.rose
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Hotkeys"
                    color: Theme.text; font.family: Theme.fontFamily
                    font.pixelSize: 16; font.bold: true
                }
                LucideIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: "chevron-right"; font.pixelSize: 14
                    color: Qt.alpha(Theme.text, 0.35)
                }
                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        font.family: Theme.fontFamily; font.pixelSize: 16
                        color: Theme.text
                        text: root.query
                    }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 2; height: 20; color: Theme.rose
                        SequentialAnimation on opacity {
                            running: root.open; loops: Animation.Infinite
                            NumberAnimation { to: 0; duration: 500 }
                            NumberAnimation { to: 1; duration: 500 }
                        }
                    }
                }
            }
        }

        Rectangle { width: parent.width; height: 1; color: Qt.alpha("#000000", 0.35) }

        Flow { // body: sections flow into columns
            width: parent.width - 36
            x: 18
            topPadding: 14
            bottomPadding: 14
            spacing: 26

            Repeater {
                model: root.filtered

                Column {
                    required property var modelData
                    width: 356
                    spacing: 3

                    Text {
                        text: modelData.section.toUpperCase()
                        color: Theme.iris
                        font.family: Theme.fontFamily; font.pixelSize: 12
                        font.bold: true; font.letterSpacing: 1
                        bottomPadding: 3
                    }

                    Repeater {
                        model: parent.modelData.rows
                        Item {
                            id: bindRow
                            required property var modelData
                            width: 356; height: 26
                            // one block per key, joined by quiet "+" glue —
                            // "SUPER + SHIFT + C" reads as three caps
                            readonly property var caps: modelData.key.trim().split(" + ")

                            Row {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 5

                                Repeater {
                                    model: bindRow.caps
                                    Row {
                                        required property string modelData
                                        required property int index
                                        spacing: 5
                                        Text {
                                            visible: index > 0
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: "+"
                                            color: Qt.alpha(Theme.text, 0.35)
                                            font.family: Theme.fontFamily; font.pixelSize: 11
                                        }
                                        Rectangle { // keycap
                                            width: capText.implicitWidth + 14
                                            height: 21; radius: 5
                                            anchors.verticalCenter: parent.verticalCenter
                                            color: Theme.overlay
                                            border.color: Qt.alpha(Theme.rose, 0.35)
                                            border.width: 1
                                            Text {
                                                id: capText
                                                anchors.centerIn: parent
                                                text: parent.parent.modelData
                                                color: Theme.rose
                                                font.family: Theme.fontFamily; font.pixelSize: 11
                                            }
                                        }
                                    }
                                }
                            }

                            Text {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                text: bindRow.modelData.desc
                                color: Qt.alpha(Theme.text, 0.85)
                                font.family: Theme.fontFamily; font.pixelSize: 13
                                width: 150; elide: Text.ElideRight
                                horizontalAlignment: Text.AlignRight
                            }
                        }
                    }
                }
            }
        }

        Rectangle { width: parent.width; height: 1; color: Qt.alpha("#000000", 0.35) }

        Rectangle { // footer
            width: parent.width
            height: 30
            bottomLeftRadius: 6
            bottomRightRadius: 6
            color: Qt.alpha(Theme.overlay, 0.55)
            Text {
                anchors.left: parent.left
                anchors.leftMargin: 18
                anchors.verticalCenter: parent.verticalCenter
                text: "type to filter   esc close"
                color: Qt.alpha(Theme.iris, 0.55)
                font.family: Theme.fontFamily; font.pixelSize: 12
            }
            Text {
                anchors.right: parent.right
                anchors.rightMargin: 18
                anchors.verticalCenter: parent.verticalCenter
                text: `${root.shownCount} binds`
                color: Qt.alpha(Theme.text, 0.4)
                font.family: Theme.fontFamily; font.pixelSize: 12
            }
        }
    }
}
