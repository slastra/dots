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

    // Order: tier, then match band (Fuzzy.band), then the caller's weight
    // (usage/recency), then fuzzy score, then label for a stable list.
    // An item's optional `tier` lifts it above every lower tier, but only
    // while a word in its text starts with the query (band 3+): a loose
    // hit in a long title ("fire" across "linkify-…-firmware", any lone
    // letter mid-word) is noise and has to compete like everything else.
    readonly property var filtered: {
        const out = []
        for (const it of items) {
            const m = Fuzzy.match(query, it.label + " " + (it.sublabel ?? ""))
            if (m.score > 0) {
                const band = Fuzzy.band(query, it.label, it.sublabel)
                out.push(Object.assign({
                    _score: m.score, _idx: m.idx, _band: band,
                    _tier: it.tier && band >= 3 ? it.tier : 0,
                }, it))
            }
        }
        out.sort((a, b) => b._tier - a._tier || b._band - a._band
            || (b.weight ?? 0) - (a.weight ?? 0) || b._score - a._score
            || a.label.localeCompare(b.label))
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

        ModalHeader { icon: root.typeIcon; query: root.query; active: root.open }

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
                    radius: Theme.innerRadius
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

        ModalFooter {
            hint: "↑↓ navigate   ↵ open   esc close"
            count: root.query === "" ? `${root.items.length}` : `${root.filtered.length}/${root.items.length}`
        }
    }
}
