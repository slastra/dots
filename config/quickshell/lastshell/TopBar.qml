import QtQuick

// The top bar: workspaces + window title left, taskbar center, system
// chips right. Modules land here phase by phase.
BarWindow {
    anchors.top: true

    Row {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.leftMargin: 8
        spacing: 8
        Workspaces {}
        WindowTitle { anchors.top: parent.top }
    }

    Taskbar {
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
    }

    Row {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.rightMargin: 8
        spacing: 8
        Tray {}
        SysChips {}
        VolumeChip {}
        BatteryChip {}
        ClockChip {}
    }
}
