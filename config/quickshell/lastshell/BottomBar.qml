import QtQuick

// The bottom bar: browser tabs left, claude strip centre, mpris + volume right.
// One window, one exclusive zone — content items only below here.
BarWindow {
    anchors.bottom: true

    TabStrip {
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.leftMargin: 8
    }

    ClaudeStrip {
        anchors.bottom: parent.bottom
        // positioned by binding, not anchor, so a width change (a chip
        // coming or going) glides the whole strip instead of jumping it
        x: Math.round((parent.width - width) / 2)
        Behavior on x { NumberAnimation { duration: Theme.slideDuration; easing.type: Easing.OutCubic } }
    }

    ChipRow {
        anchors.bottom: parent.bottom
        // positioned by binding, not anchor, so a width change (a chip
        // coming or going) glides the whole strip instead of jumping it
        x: parent.width - width - 8
        Behavior on x { NumberAnimation { duration: Theme.slideDuration; easing.type: Easing.OutCubic } }
        spacing: 8
        MprisChip {}
        VolumeChip {}
    }
}
