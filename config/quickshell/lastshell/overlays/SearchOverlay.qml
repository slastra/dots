import QtQuick
import ".."  // root module: Theme and friends
import "Fuzzy.js" as Fuzzy

// Shared switcher/launcher chrome, cut into three sections:
//   header  identity icon + the query (fixed caret, no placeholder ghost)
//   body    the filtered list with its gliding rose-outline cursor
//   footer  key hints and the live result count
Overlay {
    id: root

    property var items: []
    property string query: ""
    property string typeIcon: "search"   // lucide name marking what this modal is
    property int visibleRows: 12         // viewport height; matches beyond it scroll
    signal activated(var item)

    cardWidth: 560
    contentPadding: 2  // sections run full-bleed inside the card border
    readonly property int rowH: 40

    readonly property var filtered: {
        const out = []
        for (const it of items) {
            const m = Fuzzy.match(query, it.label + " " + (it.sublabel ?? ""))
            if (m.score > 0)
                out.push(Object.assign({ _score: m.score, _idx: m.idx }, it))
        }
        out.sort((a, b) => b._score - a._score || (b.weight ?? 0) - (a.weight ?? 0))
        return out   // no truncation — the list scrolls
    }
    property int cursor: 0
    onQueryChanged: cursor = 0
    onOpenChanged: if (open) { query = ""; cursor = 0 }

    function activate() {
        if (filtered[cursor]) { activated(filtered[cursor]); dismiss() }
    }

    Column {
        width: parent.width
        focus: true

        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape)
                root.query !== "" ? root.query = "" : root.dismiss()
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                root.activate()
            else if (event.key === Qt.Key_Down || (event.key === Qt.Key_Tab && !(event.modifiers & Qt.ShiftModifier)))
                root.cursor = Math.min(root.filtered.length - 1, root.cursor + 1)
            else if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab)
                root.cursor = Math.max(0, root.cursor - 1)
            else if (event.key === Qt.Key_Backspace)
                root.query = root.query.slice(0, -1)
            else if (event.text && event.text >= " ")
                root.query += event.text
            else
                return
            event.accepted = true
        }

        Rectangle { // ── header: identity + input
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
                    name: root.typeIcon
                    font.pixelSize: 18
                    color: Theme.rose
                }

                LucideIcon { // chevron leads from identity into the input
                    anchors.verticalCenter: parent.verticalCenter
                    name: "chevron-right"
                    font.pixelSize: 14
                    color: Qt.alpha(Theme.text, 0.35)
                }

                Row { // text + caret hug (outer Row spacing pushed the caret away)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        font.family: Theme.fontFamily
                        font.pixelSize: 17
                        color: Theme.text
                        text: root.query
                    }

                    Rectangle { // caret: rides the query's right edge
                        anchors.verticalCenter: parent.verticalCenter
                        width: 2; height: 22; color: Theme.rose
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

        Item { // ── body: a real ListView — wheel scrolls, cursor follows,
               //    the rose outline is the view's own gliding highlight
            width: parent.width
            height: (Math.max(1, Math.min(root.filtered.length, root.visibleRows)) * (root.rowH + 2)) + 18

            ListView {
                id: list
                x: 10; y: 10
                width: parent.width - 20
                height: parent.height - 20
                clip: true
                spacing: 2
                model: root.filtered
                currentIndex: root.cursor
                keyNavigationEnabled: false
                boundsBehavior: Flickable.StopAtBounds

                highlight: Rectangle {
                    radius: 6
                    color: Theme.overlay
                    border.width: 2
                    border.color: Qt.alpha(Theme.rose, 0.8)
                }
                highlightMoveDuration: 110
                highlightResizeDuration: 0
                highlightRangeMode: ListView.ApplyRange
                preferredHighlightBegin: root.rowH
                preferredHighlightEnd: height - root.rowH

                delegate: Item {
                    id: row
                    required property var modelData
                    required property int index
                    width: list.width
                    height: root.rowH

                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        x: 14
                        spacing: 10
                        Image {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 20; height: 20
                            source: row.modelData.iconSource ?? ""
                            sourceSize: Qt.size(40, 40)
                            visible: source != ""
                        }
                        LucideIcon {
                            visible: (row.modelData.lucideIcon ?? "") !== ""
                            anchors.verticalCenter: parent.verticalCenter
                            name: row.modelData.lucideIcon ?? ""
                            font.pixelSize: 15
                            color: Qt.alpha(Theme.iris, 0.8)
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            font.family: Theme.fontFamily
                            font.pixelSize: 15
                            color: row.modelData.current ? Theme.iris
                                 : row.index === root.cursor ? Theme.text : Qt.alpha(Theme.text, 0.75)
                            textFormat: Text.StyledText
                            text: Fuzzy.highlight(row.modelData.label, row.modelData._idx, Theme.gold.toString())
                            width: 450
                            elide: Text.ElideRight
                        }
                    }

                    LucideIcon { // current-selection mark
                        visible: row.modelData.current ?? false
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        name: "check"
                        font.pixelSize: 14
                        color: Theme.iris
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: { root.cursor = row.index; root.activate() }
                    }
                }
            }

            Rectangle { // top fade: content continues above
                visible: !list.atYBeginning && list.contentHeight > list.height
                anchors.top: list.top
                x: list.x; width: list.width; height: 18
                gradient: Gradient {
                    GradientStop { position: 0; color: Theme.surface }
                    GradientStop { position: 1; color: "transparent" }
                }
            }
            Rectangle { // bottom fade: content continues below
                visible: !list.atYEnd && list.contentHeight > list.height
                anchors.bottom: list.bottom
                x: list.x; width: list.width; height: 18
                gradient: Gradient {
                    GradientStop { position: 0; color: "transparent" }
                    GradientStop { position: 1; color: Theme.surface }
                }
            }

            Text { // empty state
                visible: root.filtered.length === 0
                anchors.centerIn: parent
                text: "no matches"
                color: Qt.alpha(Theme.love, 0.7)
                font.family: Theme.fontFamily; font.pixelSize: 14
                font.italic: true
            }
        }

        Rectangle { width: parent.width; height: 1; color: Qt.alpha("#000000", 0.35) }

        Rectangle { // ── footer: hints + count
            width: parent.width
            height: 32
            bottomLeftRadius: 6
            bottomRightRadius: 6
            color: Qt.alpha(Theme.overlay, 0.55)

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 18
                anchors.verticalCenter: parent.verticalCenter
                text: "↑↓ navigate   ↵ open   esc close"
                color: Qt.alpha(Theme.iris, 0.55)
                font.family: Theme.fontFamily; font.pixelSize: 12
            }
            Text {
                anchors.right: parent.right
                anchors.rightMargin: 18
                anchors.verticalCenter: parent.verticalCenter
                text: root.query === "" ? `${root.items.length}` : `${root.filtered.length}/${root.items.length}`
                color: Qt.alpha(Theme.text, 0.4)
                font.family: Theme.fontFamily; font.pixelSize: 12
            }
        }
    }
}
