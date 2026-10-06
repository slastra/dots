import QtQuick

// Claude session chips + quota gauge (bottom bar). Data via the Claude
// singleton; focus via Hyprland dispatch on the address the daemon mapped.
ChipRow {
    spacing: 8

    Repeater {
        model: Claude.sessions.model
        ClaudeChip {
            required property var item
            required property bool gone
            session: item
            present: !gone
            anchors.bottom: parent.bottom
        }
    }

    QuotaChip { anchors.bottom: parent.bottom }
}
