import QtQuick
import ".."  // root module: Theme

// The key display: a short stack of pills, newest at the bottom. Typing runs
// into one pill ("hello world⏎"); a combo, a named key or a lone modifier
// gets its own pill of keycaps (Super W), and pressing the same one again
// counts it (↓ ×4) instead of stacking copies. A pill lingers for holdMs
// after its last key, then fades; a typing pause of runGapMs starts a new
// pill, so separate thoughts read separately.
//
// The item is a fixed box; the stack grows up from its bottom edge and each
// pill centers horizontally in it. Fed by InputCast through key().
Item {
    id: root

    property int maxRows: 3
    readonly property int runGapMs: 1400
    readonly property int holdMs: 1900
    readonly property int maxChars: 44

    // rows: newest at index 0 (the ListView lays out bottom to top)
    //   kind "text" | "keys"; body: the typed run; caps: \u001f-joined
    //   keycap labels; count: repeats of the same keys; stamp: last touch;
    //   open: a text run still taking characters (Enter closes it)
    ListModel { id: rows }

    function clear() { rows.clear() }

    function key(ev) {
        const now = Date.now()
        const last = rows.count ? rows.get(0) : null
        const fresh = last !== null && now - last.stamp < runGapMs
        if (ev.kind === "char") {
            if (fresh && last.kind === "text" && last.open) {
                let body = last.body + ev.text
                if (body.length > maxChars) body = "…" + body.slice(body.length - maxChars + 1)
                rows.set(0, { body: body, stamp: now, open: ev.text !== "⏎" })
            } else {
                push({ kind: "text", body: ev.text, caps: "", count: 1, stamp: now, open: ev.text !== "⏎" })
            }
            return
        }
        const caps = ev.caps.join("\u001f")
        if (fresh && last.kind === "keys" && last.caps === caps)
            rows.set(0, { count: last.count + 1, stamp: now })
        else
            push({ kind: "keys", body: "", caps: caps, count: 1, stamp: now, open: false })
    }

    function push(row) {
        rows.insert(0, row)
        while (rows.count > maxRows) rows.remove(rows.count - 1)
    }

    Timer {
        interval: 100
        repeat: true
        running: rows.count > 0
        onTriggered: {
            const now = Date.now()
            for (let i = rows.count - 1; i >= 0; i--)
                if (now - rows.get(i).stamp > root.holdMs) rows.remove(i)
        }
    }

    component Keycap: Rectangle {
        property string label
        height: 30
        width: Math.max(height, cap.implicitWidth + 18)
        radius: Theme.innerRadius
        color: Theme.overlay
        border.width: 1
        border.color: Theme.border
        // the keycap's lower lip: reads as a key, not a tag
        Rectangle {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 1 }
            height: 3
            radius: Theme.innerRadius
            color: Qt.alpha("#000000", 0.28)
        }
        Text {
            id: cap
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -1
            text: parent.label
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fs(16)
            color: Theme.text
        }
    }

    ListView {
        id: list
        anchors.fill: parent
        model: rows
        interactive: false
        verticalLayoutDirection: ListView.BottomToTop
        spacing: 8

        // The row spans the list and the pill centers in it: ListView owns
        // its delegates' x, so a pill can't center itself as the delegate.
        delegate: Item {
            id: row
            required property string kind
            required property string body
            required property string caps
            required property int count

            width: ListView.view.width
            height: 46

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: content.implicitWidth + 30
                height: parent.height
                radius: Theme.innerRadius
                color: Qt.alpha(Theme.base, 0.88)
                border.width: 1
                border.color: Qt.alpha(Theme.text, 0.10)

                Row {
                    id: content
                    anchors.centerIn: parent
                    spacing: 6

                    Text {
                        visible: row.kind === "text"
                        anchors.verticalCenter: parent.verticalCenter
                        // a lone space would be an empty pill: show the glyph
                        text: row.body.trim() === "" ? "␣" : row.body
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(22)
                        color: Theme.text
                    }
                    Repeater {
                        model: row.kind === "keys" ? row.caps.split("\u001f") : []
                        delegate: Keycap {
                            required property string modelData
                            anchors.verticalCenter: parent.verticalCenter
                            label: modelData
                        }
                    }
                    Text {
                        visible: row.kind === "keys" && row.count > 1
                        anchors.verticalCenter: parent.verticalCenter
                        leftPadding: 2
                        text: "×" + row.count
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(17)
                        color: Theme.textMuted
                    }
                }
            }
        }

        add: Transition {
            ParallelAnimation {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 140; easing.type: Easing.OutCubic }
                NumberAnimation { property: "scale"; from: 0.94; to: 1; duration: 160; easing.type: Easing.OutCubic }
            }
        }
        remove: Transition {
            NumberAnimation { property: "opacity"; to: 0; duration: 240; easing.type: Easing.InOutQuad }
        }
        displaced: Transition {
            NumberAnimation { property: "y"; duration: 170; easing.type: Easing.OutCubic }
        }
    }
}
