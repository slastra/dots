import QtQuick

// Claude session chips + quota gauge (bottom bar). Data via the Claude
// singleton; focus via Hyprland dispatch on the address the daemon mapped.
Row {
    spacing: 8

    Repeater {
        model: Claude.sessions
        ClaudeChip {
            required property var modelData
            required property int index
            session: modelData
            anchors.bottom: parent.bottom
        }
    }

    QuotaChip { anchors.bottom: parent.bottom }
}
