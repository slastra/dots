import Quickshell
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

    JsonProcess {
        id: loader
        command: ["python3", Quickshell.env("HOME") + "/.config/rofi/scripts/hotkeys.py", "--json"]
        onResult: sections => root.sections = sections
    }

    // Filtering hides rows rather than rebuilding them: the model stays
    // fixed, so a keystroke toggles `visible` on ~300 existing delegates
    // instead of tearing them down (Column and Flow skip hidden children).
    readonly property string q: query.toLowerCase()
    function hit(row, section) {
        return q === "" || (row.key + " " + row.desc + " " + section).toLowerCase().includes(q)
    }
    readonly property int shownCount: sections.reduce((n, s) =>
        n + s.rows.reduce((m, r) => m + (hit(r, s.section) ? 1 : 0), 0), 0)

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

        ModalHeader { icon: "keyboard"; title: "Hotkeys"; query: root.query; active: root.open }

        Flow { // body: sections flow into columns
            width: parent.width - 36
            x: 18
            topPadding: 14
            bottomPadding: 14
            spacing: 26

            Repeater {
                model: root.sections

                Column {
                    id: section
                    required property var modelData
                    readonly property int hits: modelData.rows.reduce((m, r) => m + (root.hit(r, modelData.section) ? 1 : 0), 0)
                    visible: hits > 0
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
                        model: section.modelData.rows
                        Item {
                            id: bindRow
                            required property var modelData
                            visible: root.hit(modelData, section.modelData.section)
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
                                            height: 21; radius: Theme.innerRadius
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

        ModalFooter { hint: "type to filter   esc close"; count: `${root.shownCount} binds` }
    }
}
